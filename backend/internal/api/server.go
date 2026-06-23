package api

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/winkler/lab-tracker/backend/internal/db/sqlc"
	"github.com/winkler/lab-tracker/backend/internal/llm"
	"github.com/winkler/lab-tracker/backend/internal/storage"
)

type Server struct {
	pool      *pgxpool.Pool
	q         *sqlc.Queries
	store     *storage.Store
	extractor *llm.Extractor
	log       *slog.Logger
}

func NewServer(pool *pgxpool.Pool, store *storage.Store, extractor *llm.Extractor, log *slog.Logger) *Server {
	return &Server{
		pool:      pool,
		q:         sqlc.New(pool),
		store:     store,
		extractor: extractor,
		log:       log,
	}
}

func (s *Server) Router(corsOrigins []string) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(120 * time.Second))
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   corsOrigins,
		AllowedMethods:   []string{"GET", "POST", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Content-Type"},
		AllowCredentials: false,
		MaxAge:           300,
	}))

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	r.Route("/api", func(r chi.Router) {
		r.Get("/profiles", s.listProfiles)
		r.Post("/profiles", s.createProfile)
		r.Delete("/profiles/{id}", s.deleteProfile)

		r.Post("/profiles/{id}/reports", s.uploadReport)
		r.Get("/profiles/{id}/reports", s.listReports)
		r.Get("/profiles/{id}/results", s.listResults)
		r.Get("/profiles/{id}/analytes", s.listProfileAnalytes)
		r.Post("/profiles/{id}/favorites", s.addFavorite)
		r.Delete("/profiles/{id}/favorites/{analyteId}", s.removeFavorite)

		r.Get("/reports/{id}", s.getReport)
		r.Post("/reports/{id}/confirm", s.confirmReport)
		r.Get("/reports/{id}/pdf", s.getReportPDF)

		r.Get("/analytes", s.listAnalytes)
	})

	return r
}
