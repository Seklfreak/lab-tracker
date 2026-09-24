package api

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
	"github.com/Seklfreak/lab-tracker/backend/internal/sqlctest"
)

func doWithToken(t *testing.T, h http.Handler, method, path, body, token string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// A valid token acts as its owner, even though the router has no OIDC verifier.
func TestAPIToken_AuthenticatesAsOwner(t *testing.T) {
	owner := uuid.New()
	const token = "lt_example-token"
	var gotUser *uuid.UUID
	q := &sqlctest.FakeQuerier{
		GetActiveAPITokenByHashFn: func(_ context.Context, h []byte) (sqlc.GetActiveAPITokenByHashRow, error) {
			if !bytes.Equal(h, hashAPIToken(token)) {
				t.Errorf("looked up wrong hash")
			}
			return sqlc.GetActiveAPITokenByHashRow{TokenID: uuid.New(), ID: owner}, nil
		},
		TouchAPITokenFn: func(context.Context, uuid.UUID) error { return nil },
		ListProfilesForUserFn: func(_ context.Context, uid *uuid.UUID) ([]sqlc.Profile, error) {
			gotUser = uid
			return nil, nil
		},
	}
	rec := doWithToken(t, router(q, nil), http.MethodGet, "/api/profiles", "", token)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if gotUser == nil || *gotUser != owner {
		t.Errorf("profiles listed for %v, want token owner %v", gotUser, owner)
	}
}

func TestAPIToken_UnknownOrRevoked(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		GetActiveAPITokenByHashFn: func(context.Context, []byte) (sqlc.GetActiveAPITokenByHashRow, error) {
			return sqlc.GetActiveAPITokenByHashRow{}, pgx.ErrNoRows
		},
	}
	if rec := doWithToken(t, router(q, nil), http.MethodGet, "/api/profiles", "", "lt_nope"); rec.Code != http.StatusUnauthorized {
		t.Errorf("want 401, got %d", rec.Code)
	}
}

// Token requests never get admin rights, whatever the owner's email.
func TestAPIToken_NeverAdmin(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		GetActiveAPITokenByHashFn: func(context.Context, []byte) (sqlc.GetActiveAPITokenByHashRow, error) {
			return sqlc.GetActiveAPITokenByHashRow{TokenID: uuid.New(), ID: uuid.New()}, nil
		},
		TouchAPITokenFn: func(context.Context, uuid.UUID) error { return nil },
	}
	if rec := doWithToken(t, router(q, nil), http.MethodGet, "/api/admin/users", "", "lt_x"); rec.Code != http.StatusForbidden {
		t.Errorf("want 403, got %d", rec.Code)
	}
}

func TestCreateToken_ReturnsPlaintextOnce(t *testing.T) {
	var stored sqlc.CreateAPITokenParams
	q := &sqlctest.FakeQuerier{
		CreateAPITokenFn: func(_ context.Context, arg sqlc.CreateAPITokenParams) (sqlc.ApiToken, error) {
			stored = arg
			return sqlc.ApiToken{ID: uuid.New(), Name: arg.Name, TokenPrefix: arg.TokenPrefix}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodPost, "/api/tokens", `{"name":" curo-l7 "}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("want 201, got %d: %s", rec.Code, rec.Body)
	}
	var got createdTokenDTO
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(got.Token, apiTokenPrefix) || len(got.Token) < 40 {
		t.Errorf("unexpected token %q", got.Token)
	}
	if !bytes.Equal(stored.TokenHash, hashAPIToken(got.Token)) {
		t.Error("stored hash doesn't match the returned token")
	}
	if stored.UserID != DevUserID || stored.Name != "curo-l7" || stored.TokenPrefix != got.Token[:11] {
		t.Errorf("stored %+v", stored)
	}
}

// A leaked token must not be able to mint more tokens.
func TestCreateToken_ForbiddenViaToken(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		GetActiveAPITokenByHashFn: func(context.Context, []byte) (sqlc.GetActiveAPITokenByHashRow, error) {
			return sqlc.GetActiveAPITokenByHashRow{TokenID: uuid.New(), ID: uuid.New()}, nil
		},
		TouchAPITokenFn: func(context.Context, uuid.UUID) error { return nil },
	}
	if rec := doWithToken(t, router(q, nil), http.MethodPost, "/api/tokens", `{"name":"x"}`, "lt_x"); rec.Code != http.StatusForbidden {
		t.Errorf("want 403, got %d", rec.Code)
	}
}

// Revoking is scoped to the current user; someone else's token 404s.
func TestRevokeToken_Isolation(t *testing.T) {
	var got sqlc.RevokeAPITokenParams
	q := &sqlctest.FakeQuerier{
		RevokeAPITokenFn: func(_ context.Context, arg sqlc.RevokeAPITokenParams) (int64, error) {
			got = arg
			return 0, nil // not this user's token
		},
	}
	id := uuid.New()
	if rec := do(t, router(q, nil), http.MethodDelete, "/api/tokens/"+id.String(), ""); rec.Code != http.StatusNotFound {
		t.Errorf("want 404, got %d", rec.Code)
	}
	if got.ID != id || got.UserID != DevUserID {
		t.Errorf("revoke params %+v", got)
	}
}
