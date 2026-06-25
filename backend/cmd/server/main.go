package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/Seklfreak/lab-tracker/backend/internal/api"
	"github.com/Seklfreak/lab-tracker/backend/internal/config"
	"github.com/Seklfreak/lab-tracker/backend/internal/db"
	"github.com/Seklfreak/lab-tracker/backend/internal/llm"
	"github.com/Seklfreak/lab-tracker/backend/internal/storage"
)

func main() {
	log := slog.New(slog.NewTextHandler(os.Stdout, nil))

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

	store, err := storage.New(ctx, cfg.MinioEndpoint, cfg.MinioAccessKey, cfg.MinioSecretKey, cfg.MinioBucket, cfg.MinioUseSSL)
	if err != nil {
		log.Error("storage", "err", err)
		os.Exit(1)
	}

	extractor := llm.NewExtractor(cfg.AnthropicKey)

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

	srv := api.NewServer(pool, store, extractor, log, verifier)
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
