// Command mcp serves lab-tracker data over MCP (Streamable HTTP) for use as a
// claude.ai connector. It reuses the app's sqlc queries and LLM extractor and
// connects directly to the lab-tracker Postgres. Auth is handled in front of it
// (Cloudflare Access); this process has none.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/Seklfreak/lab-tracker/backend/internal/db"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
	"github.com/Seklfreak/lab-tracker/backend/internal/llm"
)

func main() {
	log := slog.New(slog.NewTextHandler(os.Stdout, nil))

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Error("missing DATABASE_URL")
		os.Exit(1)
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	// Optional: only generate_analysis needs it.
	extractor := llm.NewExtractor(os.Getenv("ANTHROPIC_API_KEY"))

	ctx := context.Background()
	pool, err := db.Connect(ctx, dbURL)
	if err != nil {
		log.Error("db connect", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	q := sqlc.New(pool)

	srv := newMCPServer(q, extractor, log)

	// claude.ai's broker holds session IDs; stateless avoids "session expired".
	var mcpHandler http.Handler = mcp.NewStreamableHTTPHandler(
		func(*http.Request) *mcp.Server { return srv },
		&mcp.StreamableHTTPOptions{Stateless: true},
	)

	// Per-request identity from Cloudflare Access. Access is the OAuth server at
	// the edge (claude.ai logs the user in via Authentik) and injects a signed
	// Cf-Access-Jwt-Assertion; we validate it and scope every tool to the
	// resolved user. Unset team domain = unscoped (local dev), logged loudly.
	if team := strings.TrimSpace(os.Getenv("CF_ACCESS_TEAM_DOMAIN")); team != "" {
		aud := strings.TrimSpace(os.Getenv("CF_ACCESS_AUD"))
		verifier := newCFAccessVerifier(ctx, team, aud)
		mcpHandler = cfAccessIdentity(verifier, q, log)(mcpHandler)
		log.Info("cloudflare access identity enabled", "team", team, "audPinned", aud != "")
	} else {
		log.Warn("CF_ACCESS_TEAM_DOMAIN not set — connector exposes ALL profiles (unscoped)")
	}

	mux := http.NewServeMux()
	mux.Handle("/mcp", mcpHandler)
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})

	log.Info("mcp listening", "port", port)
	httpServer := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}
	if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Error("server", "err", err)
		os.Exit(1)
	}
}
