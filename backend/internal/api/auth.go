package api

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
)

// NewVerifier builds an OIDC token verifier from the issuer's discovery document.
// It performs a network call (discovery + JWKS), so call it once at startup.
func NewVerifier(ctx context.Context, issuer, clientID string) (*oidc.IDTokenVerifier, error) {
	provider, err := oidc.NewProvider(ctx, issuer)
	if err != nil {
		return nil, fmt.Errorf("oidc discovery (%s): %w", issuer, err)
	}
	// We validate access tokens by issuer + signature + expiry. The issuer is
	// per-application (…/application/o/<app>/), so only this app's tokens carry
	// it — the audience check is redundant and Authentik's access-token `aud`
	// differs from the client_id, so skip it. (clientID kept for reference.)
	_ = clientID
	return provider.Verifier(&oidc.Config{SkipClientIDCheck: true}), nil
}

type ctxKey string

const (
	claimsKey ctxKey = "oidc-claims"
	userIDKey ctxKey = "user-id"
)

// DevUserID is the fixed local user used when AUTH_DISABLED is set (dev). The
// server seeds a matching users row at startup (see db.BootstrapOwner) so
// owner_user_id foreign keys resolve.
var DevUserID = uuid.MustParse("00000000-0000-0000-0000-000000000001")

// DevUserSub is the OIDC subject of the local dev user.
const DevUserSub = "dev-user"

// authMiddleware validates the Bearer JWT on every request and resolves it to a
// user row (upserted by `sub`), stashing the user id in context. When the server
// has no verifier (AUTH_DISABLED), it acts as the fixed local dev user.
func (s *Server) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.verifier == nil {
			ctx := context.WithValue(r.Context(), userIDKey, DevUserID)
			next.ServeHTTP(w, r.WithContext(ctx))
			return
		}
		raw := bearerToken(r)
		if raw == "" {
			writeError(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		tok, err := s.verifier.Verify(r.Context(), raw)
		if err != nil {
			s.log.Warn("token verification failed", "err", err)
			writeError(w, http.StatusUnauthorized, "invalid token")
			return
		}
		var claims map[string]any
		_ = tok.Claims(&claims)

		sub := stringClaim(claims, "sub")
		if sub == "" {
			writeError(w, http.StatusUnauthorized, "token has no subject")
			return
		}
		user, err := s.q.UpsertUser(r.Context(), sqlc.UpsertUserParams{
			OidcSub: sub,
			Email:   optText(stringClaim(claims, "email")),
			Name:    optText(displayName(claims)),
		})
		if err != nil {
			s.log.Error("upsert user", "err", err)
			writeError(w, http.StatusInternalServerError, "failed to resolve user")
			return
		}

		ctx := context.WithValue(r.Context(), userIDKey, user.ID)
		ctx = context.WithValue(ctx, claimsKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// currentUserID returns the authenticated user's id from context, or uuid.Nil
// if the request never passed through authMiddleware (shouldn't happen on /api).
func currentUserID(ctx context.Context) uuid.UUID {
	if v, ok := ctx.Value(userIDKey).(uuid.UUID); ok {
		return v
	}
	return uuid.Nil
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if h == "" {
		return ""
	}
	const prefix = "Bearer "
	if len(h) > len(prefix) && strings.EqualFold(h[:len(prefix)], prefix) {
		return strings.TrimSpace(h[len(prefix):])
	}
	return ""
}

func stringClaim(claims map[string]any, key string) string {
	if v, ok := claims[key].(string); ok {
		return strings.TrimSpace(v)
	}
	return ""
}

// displayName picks a human name from the usual OIDC claims, falling back to the
// preferred username (Authentik populates that even when `name` is empty).
func displayName(claims map[string]any) string {
	if n := stringClaim(claims, "name"); n != "" {
		return n
	}
	return stringClaim(claims, "preferred_username")
}

func optText(s string) pgtype.Text {
	if s == "" {
		return pgtype.Text{}
	}
	return pgtype.Text{String: s, Valid: true}
}
