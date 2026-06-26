package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
)

type ctxKey string

const userIDKey ctxKey = "lab-tracker-user-id"

// userIDFromContext returns the authenticated user's id, or nil when the request
// carried no identity (dev / unscoped mode → tools see all profiles).
func userIDFromContext(ctx context.Context) *uuid.UUID {
	if v, ok := ctx.Value(userIDKey).(uuid.UUID); ok {
		u := v
		return &u
	}
	return nil
}

// newCFAccessVerifier builds an OIDC verifier for Cloudflare Access identity
// JWTs (the Cf-Access-Jwt-Assertion header), validated against the team's
// signing certs. The issuer is the team domain; aud, when set, pins the Access
// application's audience tag (recommended — otherwise any of the team's Access
// apps would be accepted).
func newCFAccessVerifier(ctx context.Context, teamDomain, aud string) *oidc.IDTokenVerifier {
	teamDomain = strings.TrimRight(teamDomain, "/")
	keySet := oidc.NewRemoteKeySet(ctx, teamDomain+"/cdn-cgi/access/certs")
	cfg := &oidc.Config{}
	if aud != "" {
		cfg.ClientID = aud
	} else {
		cfg.SkipClientIDCheck = true
	}
	return oidc.NewVerifier(teamDomain, keySet, cfg)
}

// cfAccessIdentity validates the Cloudflare Access identity JWT on each request,
// resolves the authenticated email to a lab-tracker user, and stores that user's
// id in context for the MCP tools to scope on. Cloudflare Access (the OAuth
// authorization server at the edge) injects this header after the user logs in
// via Authentik, so the connector identifies the real caller — no hardcoded user.
func cfAccessIdentity(verifier *oidc.IDTokenVerifier, q sqlc.Querier, log *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			raw := r.Header.Get("Cf-Access-Jwt-Assertion")
			if raw == "" {
				writeJSONError(w, http.StatusUnauthorized, "missing Cloudflare Access identity")
				return
			}
			tok, err := verifier.Verify(r.Context(), raw)
			if err != nil {
				log.Warn("cf access token verification failed", "err", err)
				writeJSONError(w, http.StatusUnauthorized, "invalid Cloudflare Access token")
				return
			}
			var claims struct {
				Email string `json:"email"`
			}
			_ = tok.Claims(&claims)
			email := strings.TrimSpace(claims.Email)
			if email == "" {
				writeJSONError(w, http.StatusForbidden, "Cloudflare Access token has no email")
				return
			}
			user, err := q.GetUserByEmail(r.Context(), email)
			if errors.Is(err, pgx.ErrNoRows) {
				log.Warn("no lab-tracker user for cf access email", "email", email)
				writeJSONError(w, http.StatusForbidden, "no lab-tracker account for "+email+" — sign into the web app first")
				return
			}
			if err != nil {
				log.Error("lookup user by email", "err", err)
				writeJSONError(w, http.StatusInternalServerError, "user lookup failed")
				return
			}
			ctx := context.WithValue(r.Context(), userIDKey, user.ID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func writeJSONError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write([]byte(`{"error":` + strconvQuote(msg) + `}`))
}

// strconvQuote is a tiny JSON-string quoter (avoids importing encoding/json here
// for one line).
func strconvQuote(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range s {
		switch r {
		case '"', '\\':
			b.WriteByte('\\')
			b.WriteRune(r)
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte('"')
	return b.String()
}
