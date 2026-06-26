package config

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// Config holds all runtime configuration, loaded from the environment.
type Config struct {
	DatabaseURL    string
	AnthropicKey   string
	MinioEndpoint  string
	MinioAccessKey string
	MinioSecretKey string
	MinioBucket    string
	MinioUseSSL    bool
	Port           string
	CORSOrigins    []string

	// OIDC auth. When AuthDisabled is true (dev), the API skips token checks.
	// Otherwise OIDCIssuer + OIDCClientID are required to validate Bearer JWTs.
	OIDCIssuer   string
	OIDCClientID string
	AuthDisabled bool

	// AdminOIDCSub is the OIDC subject of the admin user that existing,
	// owner-less profiles are migrated to on startup. Set this the first time
	// multi-user is rolled out onto a DB with pre-existing profiles.
	AdminOIDCSub string
}

// Load reads configuration from the environment. If a .env file exists in the
// working directory (or its parent), it is loaded first without overriding
// variables already present in the environment.
func Load() (*Config, error) {
	loadDotEnv(".env")
	loadDotEnv("../.env")

	cfg := &Config{
		DatabaseURL:    os.Getenv("DATABASE_URL"),
		AnthropicKey:   os.Getenv("ANTHROPIC_API_KEY"),
		MinioEndpoint:  os.Getenv("MINIO_ENDPOINT"),
		MinioAccessKey: os.Getenv("MINIO_ACCESS_KEY"),
		MinioSecretKey: os.Getenv("MINIO_SECRET_KEY"),
		MinioBucket:    getenvDefault("MINIO_BUCKET", "lab-results"),
		MinioUseSSL:    os.Getenv("MINIO_USE_SSL") == "true",
		Port:           getenvDefault("PORT", "8080"),
		CORSOrigins:    splitCSV(getenvDefault("CORS_ORIGINS", "http://localhost:5173")),
		OIDCIssuer:     os.Getenv("OIDC_ISSUER"),
		OIDCClientID:   os.Getenv("OIDC_CLIENT_ID"),
		AuthDisabled:   os.Getenv("AUTH_DISABLED") == "true",
		AdminOIDCSub:   os.Getenv("ADMIN_OIDC_SUB"),
	}

	var missing []string
	if cfg.DatabaseURL == "" {
		missing = append(missing, "DATABASE_URL")
	}
	if cfg.AnthropicKey == "" {
		missing = append(missing, "ANTHROPIC_API_KEY")
	}
	if cfg.MinioEndpoint == "" {
		missing = append(missing, "MINIO_ENDPOINT")
	}
	if !cfg.AuthDisabled {
		if cfg.OIDCIssuer == "" {
			missing = append(missing, "OIDC_ISSUER (or set AUTH_DISABLED=true)")
		}
		if cfg.OIDCClientID == "" {
			missing = append(missing, "OIDC_CLIENT_ID (or set AUTH_DISABLED=true)")
		}
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("missing required env vars: %s", strings.Join(missing, ", "))
	}
	return cfg, nil
}

func getenvDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func splitCSV(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// loadDotEnv parses a simple KEY=value .env file. Lines starting with # are
// ignored. Existing environment variables are not overridden.
func loadDotEnv(path string) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, val, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		val = strings.Trim(strings.TrimSpace(val), `"'`)
		if _, exists := os.LookupEnv(key); !exists {
			_ = os.Setenv(key, val)
		}
	}
}
