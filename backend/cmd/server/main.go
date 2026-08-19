package main

import (
	"context"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/Seklfreak/lab-tracker/backend/internal/api"
	"github.com/Seklfreak/lab-tracker/backend/internal/config"
	"github.com/Seklfreak/lab-tracker/backend/internal/db"
	"github.com/Seklfreak/lab-tracker/backend/internal/llm"
	"github.com/Seklfreak/lab-tracker/backend/internal/obs"
	"github.com/Seklfreak/lab-tracker/backend/internal/storage"
	"github.com/anthropics/anthropic-sdk-go/option"
	"github.com/coreos/go-oidc/v3/oidc"
	sentryhttpclient "github.com/getsentry/sentry-go/httpclient"
)

// version is the release version, injected at build time via
// -ldflags "-X main.version=...". "dev" for local builds.
var version = "dev"

func main() {
	// Sentry first (SENTRY_DSN unset = disabled, the local default) so the
	// logger below forwards error records as events. Only API request
	// transactions are traced; health checks and static paths are dropped.
	flush, sentryErr := obs.Init("lab-tracker@"+version, func(name string) bool {
		return strings.Contains(name, "/api/")
	})
	defer flush()
	log := obs.NewLogger()
	if sentryErr != nil {
		log.Error("sentry init", "err", sentryErr)
		os.Exit(1)
	}
	log.Info("starting", "version", version)
	api.BuildVersion = version

	cfg, err := config.Load()
	if err != nil {
		log.Error("config", "err", err)
		os.Exit(1)
	}

	log.Info("running migrations")
	if err := db.Migrate(cfg.DatabaseURL); err != nil {
		log.Error("migrate", "err", err)
		os.Exit(1)
	}

	ctx := context.Background()
	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Error("db connect", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	// In dev (AUTH_DISABLED) seed the fixed local user and own any owner-less
	// profiles to it, so the dev user sees its data. In prod every profile gets
	// an owner at creation; the one-time migration of legacy profiles is done.
	if cfg.AuthDisabled {
		devID := api.DevUserID
		if err := db.BootstrapOwner(ctx, pool, api.DevUserSub, &devID); err != nil {
			log.Error("bootstrap dev owner", "err", err)
			os.Exit(1)
		}
	}

	store, err := storage.New(ctx, cfg.MinioEndpoint, cfg.MinioAccessKey, cfg.MinioSecretKey, cfg.MinioBucket, cfg.MinioUseSSL)
	if err != nil {
		log.Error("storage", "err", err)
		os.Exit(1)
	}

	// Extraction calls become http.client spans on the request transaction.
	extractor := llm.NewExtractor(cfg.AnthropicKey, option.WithHTTPClient(&http.Client{
		Transport: sentryhttpclient.NewSentryRoundTripper(nil),
	}))

	var verifier *oidc.IDTokenVerifier
	if cfg.AuthDisabled {
		log.Warn("AUTH_DISABLED set — API is unauthenticated")
	} else {
		verifier, err = api.NewVerifier(ctx, cfg.OIDCIssuer, cfg.OIDCClientID)
		if err != nil {
			log.Error("oidc verifier", "err", err)
			os.Exit(1)
		}
		log.Info("oidc auth enabled", "issuer", cfg.OIDCIssuer)
	}

	srv := api.NewServer(pool, store, extractor, log, verifier, cfg.AdminEmails)
	handler := srv.Router(cfg.CORSOrigins)

	httpServer := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}

	log.Info("listening", "port", cfg.Port)
	if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Error("server", "err", err)
		os.Exit(1)
	}
}
