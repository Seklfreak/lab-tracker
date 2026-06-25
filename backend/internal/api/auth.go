package api

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
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

const claimsKey ctxKey = "oidc-claims"

// authMiddleware validates the Bearer JWT on every request. When the server has
// no verifier (AUTH_DISABLED), it passes through unchanged.
func (s *Server) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.verifier == nil {
			next.ServeHTTP(w, r)
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
		ctx := context.WithValue(r.Context(), claimsKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
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
