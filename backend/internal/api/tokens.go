package api

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
)

// Personal access tokens let scripts and device importers call the API without
// an OIDC session. Format: "lt_" + 32 random bytes (base64url). Only the
// SHA-256 is stored.
const (
	apiTokenPrefix    = "lt_"
	apiTokenShownPart = 8 // characters kept in token_prefix, after "lt_"
)

func isAPIToken(raw string) bool { return strings.HasPrefix(raw, apiTokenPrefix) }

func hashAPIToken(raw string) []byte {
	sum := sha256.Sum256([]byte(raw))
	return sum[:]
}

func newAPIToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return apiTokenPrefix + base64.RawURLEncoding.EncodeToString(b), nil
}

// serveWithAPIToken authenticates a request carrying a personal access token.
// Token requests are never admin, whatever the owner's email.
func (s *Server) serveWithAPIToken(w http.ResponseWriter, r *http.Request, raw string, next http.Handler) {
	row, err := s.q.GetActiveAPITokenByHash(r.Context(), hashAPIToken(raw))
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusUnauthorized, "invalid token")
		return
	}
	if err != nil {
		s.log.Error("look up api token", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to resolve token")
		return
	}
	if err := s.q.TouchAPIToken(r.Context(), row.TokenID); err != nil {
		s.log.Warn("touch api token", "err", err)
	}
	ctx := context.WithValue(r.Context(), userIDKey, row.ID)
	ctx = context.WithValue(ctx, emailKey, row.Email.String)
	ctx = context.WithValue(ctx, isAdminKey, false)
	ctx = context.WithValue(ctx, viaTokenKey, true)
	next.ServeHTTP(w, r.WithContext(ctx))
}

func viaAPIToken(ctx context.Context) bool {
	v, _ := ctx.Value(viaTokenKey).(bool)
	return v
}

type APITokenDTO struct {
	ID         uuid.UUID  `json:"id"`
	Name       string     `json:"name"`
	Prefix     string     `json:"prefix"`
	CreatedAt  time.Time  `json:"createdAt"`
	LastUsedAt *time.Time `json:"lastUsedAt"`
}

func toAPITokenDTO(t sqlc.ApiToken) APITokenDTO {
	dto := APITokenDTO{ID: t.ID, Name: t.Name, Prefix: t.TokenPrefix, CreatedAt: t.CreatedAt.Time}
	if t.LastUsedAt.Valid {
		lu := t.LastUsedAt.Time
		dto.LastUsedAt = &lu
	}
	return dto
}

func (s *Server) listTokens(w http.ResponseWriter, r *http.Request) {
	rows, err := s.q.ListAPITokensForUser(r.Context(), currentUserID(r.Context()))
	if err != nil {
		s.log.Error("list api tokens", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to list tokens")
		return
	}
	out := make([]APITokenDTO, 0, len(rows))
	for _, t := range rows {
		out = append(out, toAPITokenDTO(t))
	}
	writeJSON(w, http.StatusOK, out)
}

type createTokenReq struct {
	Name string `json:"name"`
}

type createdTokenDTO struct {
	APITokenDTO
	// Token is the plaintext, returned only here.
	Token string `json:"token"`
}

func (s *Server) createToken(w http.ResponseWriter, r *http.Request) {
	// A leaked token must not be able to mint more tokens.
	if viaAPIToken(r.Context()) {
		writeError(w, http.StatusForbidden, "tokens can only be created from a signed-in session")
		return
	}
	var req createTokenReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	raw, err := newAPIToken()
	if err != nil {
		s.log.Error("generate api token", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to create token")
		return
	}
	t, err := s.q.CreateAPIToken(r.Context(), sqlc.CreateAPITokenParams{
		UserID:      currentUserID(r.Context()),
		Name:        strings.TrimSpace(req.Name),
		TokenHash:   hashAPIToken(raw),
		TokenPrefix: raw[:len(apiTokenPrefix)+apiTokenShownPart],
	})
	if err != nil {
		s.log.Error("create api token", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to create token")
		return
	}
	writeJSON(w, http.StatusCreated, createdTokenDTO{APITokenDTO: toAPITokenDTO(t), Token: raw})
}

func (s *Server) revokeToken(w http.ResponseWriter, r *http.Request) {
	id, ok := parseUUID(chi.URLParam(r, "id"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}
	n, err := s.q.RevokeAPIToken(r.Context(), sqlc.RevokeAPITokenParams{ID: id, UserID: currentUserID(r.Context())})
	if err != nil {
		s.log.Error("revoke api token", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to revoke token")
		return
	}
	if n == 0 {
		// Unknown, already revoked, or someone else's: all look the same.
		writeError(w, http.StatusNotFound, "token not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
