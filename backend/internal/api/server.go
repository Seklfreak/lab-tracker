package api

import (
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
	"github.com/Seklfreak/lab-tracker/backend/internal/llm"
	"github.com/Seklfreak/lab-tracker/backend/internal/storage"
)

type Server struct {
	pool        *pgxpool.Pool
	q           sqlc.Querier
	store       *storage.Store
	extractor   *llm.Extractor
	log         *slog.Logger
	verifier    *oidc.IDTokenVerifier // nil when AUTH_DISABLED
	adminEmails map[string]bool       // lowercased; super-user allowlist
}

func NewServer(pool *pgxpool.Pool, store *storage.Store, extractor *llm.Extractor, log *slog.Logger, verifier *oidc.IDTokenVerifier, adminEmails []string) *Server {
	admins := make(map[string]bool, len(adminEmails))
	for _, e := range adminEmails {
		admins[strings.ToLower(strings.TrimSpace(e))] = true
	}
	return &Server{
		pool:        pool,
		q:           sqlc.New(pool),
		store:       store,
		extractor:   extractor,
		log:         log,
		verifier:    verifier,
		adminEmails: admins,
	}
}

func (s *Server) Router(corsOrigins []string) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	// RealIP is deprecated for spoofing reasons when directly exposed; here the
	// app only ever sits behind trusted proxies (Traefik + Cloudflare) that set
	// the forwarded headers, and the IP is used for request logging only.
	r.Use(middleware.RealIP) //nolint:staticcheck // trusted-proxy-only; logging
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(120 * time.Second))
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   corsOrigins,
		AllowedMethods:   []string{"GET", "POST", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Content-Type", "Authorization"},
		AllowCredentials: false,
		MaxAge:           300,
	}))

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	r.Route("/api", func(r chi.Router) {
		r.Use(s.authMiddleware)

		r.Get("/me", s.getMe)
		r.Get("/admin/users", s.listAllUsers)

		r.Get("/profiles", s.listProfiles)
		r.Post("/profiles", s.createProfile)
		r.Delete("/profiles/{id}", s.deleteProfile)

		r.Get("/profiles/{id}/members", s.listMembers)
		r.Post("/profiles/{id}/members", s.addMember)
		r.Delete("/profiles/{id}/members/{userId}", s.removeMember)

		r.Post("/profiles/{id}/reports", s.uploadReport)
		r.Get("/profiles/{id}/reports", s.listReports)
		r.Get("/profiles/{id}/results", s.listResults)
		r.Get("/profiles/{id}/analytes", s.listProfileAnalytes)
		r.Post("/profiles/{id}/favorites", s.addFavorite)
		r.Delete("/profiles/{id}/favorites/{analyteId}", s.removeFavorite)
		r.Get("/profiles/{id}/analytes/{analyteId}/analysis", s.getAnalysis)
		r.Post("/profiles/{id}/analytes/{analyteId}/analysis", s.analyzeAnalyte)
		r.Post("/profiles/{id}/summary", s.generatePanelSummary)

		r.Get("/reports/{id}", s.getReport)
		r.Post("/reports/{id}/confirm", s.confirmReport)
		r.Post("/reports/{id}/reparse", s.reparseReport)
		r.Delete("/reports/{id}", s.deleteReport)
		r.Get("/reports/{id}/pdf", s.getReportPDF)

		r.Post("/results/{id}", s.updateResult)
		r.Delete("/results/{id}", s.deleteResult)

		r.Get("/analytes", s.listAnalytes)
	})

	return r
}
