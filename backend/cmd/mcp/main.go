// Command mcp serves lab-tracker data over MCP (Streamable HTTP) for use as a
// claude.ai connector. It reuses the app's sqlc queries and LLM extractor and
// connects directly to the lab-tracker Postgres. Auth is handled in front of it
// (Cloudflare Access); this process has none.
package main

import (
	"context"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/Seklfreak/lab-tracker/backend/internal/db"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
	"github.com/Seklfreak/lab-tracker/backend/internal/llm"
	"github.com/Seklfreak/lab-tracker/backend/internal/obs"
	"github.com/anthropics/anthropic-sdk-go/option"
	sentryhttp "github.com/getsentry/sentry-go/http"
	sentryhttpclient "github.com/getsentry/sentry-go/httpclient"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// version is the release version, injected at build time via
// -ldflags "-X main.version=...". "dev" for local builds. Reported in the MCP
// server's Implementation handshake.
var version = "dev"

func main() {
	// Sentry first (SENTRY_DSN unset = disabled, the local default) so the
	// logger below forwards error records as events. Only /mcp request
	// transactions are traced; /health probes are dropped.
	flush, sentryErr := obs.Init("lab-tracker@"+version, func(name string) bool {
		return strings.Contains(name, "/mcp")
	})
	defer flush()
	log := obs.NewLogger()
	if sentryErr != nil {
		log.Error("sentry init", "err", sentryErr)
		os.Exit(1)
	}
	log.Info("starting", "version", version)

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
	// Analysis-generation calls become http.client spans on the /mcp
	// request transaction.
	extractor := llm.NewExtractor(os.Getenv("ANTHROPIC_API_KEY"), option.WithHTTPClient(&http.Client{
		Transport: sentryhttpclient.NewSentryRoundTripper(nil),
	}))

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
	// The middleware captures handler panics and opens the /mcp request
	// transactions the sampler keeps.
	sentryMW := sentryhttp.New(sentryhttp.Options{Repanic: true})
	httpServer := &http.Server{
		Addr:              ":" + port,
		Handler:           sentryMW.Handle(mux),
		ReadHeaderTimeout: 10 * time.Second,
	}
	if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Error("server", "err", err)
		os.Exit(1)
	}
}
