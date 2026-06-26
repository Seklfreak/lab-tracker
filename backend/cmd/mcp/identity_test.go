package main

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
	"github.com/Seklfreak/lab-tracker/backend/internal/sqlctest"
)

func discardLog() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func TestUserIDFromContext(t *testing.T) {
	if got := userIDFromContext(context.Background()); got != nil {
		t.Errorf("empty context: want nil, got %v", got)
	}
	id := uuid.New()
	ctx := context.WithValue(context.Background(), userIDKey, id)
	got := userIDFromContext(ctx)
	if got == nil || *got != id {
		t.Errorf("want %v, got %v", id, got)
	}
}

// A request without the Cloudflare Access identity header is rejected before any
// token verification or DB lookup (so a nil verifier/querier is never touched).
func TestCFAccessIdentity_MissingHeader(t *testing.T) {
	mw := cfAccessIdentity(nil, &sqlctest.FakeQuerier{}, discardLog())
	next := http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		t.Fatal("handler must not run without identity")
	})
	rec := httptest.NewRecorder()
	mw(next).ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/mcp", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("want 401, got %d", rec.Code)
	}
}
