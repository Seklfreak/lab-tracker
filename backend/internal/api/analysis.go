package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/Seklfreak/lab-tracker/backend/internal/analysis"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
)

type AnalysisDTO struct {
	Content      string `json:"content"`
	GeneratedAt  string `json:"generatedAt"`
	BasedOnCount int    `json:"basedOnCount"`
	CurrentCount int    `json:"currentCount"`
	Stale        bool   `json:"stale"`
}

// getAnalysis returns the stored analysis for an analyte (or null), with a
// staleness flag when new results exist since it was generated.
func (s *Server) getAnalysis(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	analyteID, ok := parseUUID(chi.URLParam(r, "analyteId"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid analyteId")
		return
	}
	stats, err := s.q.ResultStatsForProfileAnalyte(r.Context(), sqlc.ResultStatsForProfileAnalyteParams{
		ProfileID: p.ID, AnalyteID: analyteID,
	})
	if err != nil {
		s.log.Error("result stats", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load analysis")
		return
	}
	stored, err := s.q.GetAnalysis(r.Context(), sqlc.GetAnalysisParams{ProfileID: p.ID, AnalyteID: analyteID})
	if errors.Is(err, pgx.ErrNoRows) {
		writeJSON(w, http.StatusOK, map[string]any{"analysis": nil})
		return
	}
	if err != nil {
		s.log.Error("get analysis", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load analysis")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"analysis": toAnalysisDTO(stored, int(stats.Count), analysis.IsStale(stored, stats)),
	})
}

// analyzeAnalyte generates (or regenerates) the analysis via the LLM and stores it.
func (s *Server) analyzeAnalyte(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	analyteID, ok := parseUUID(chi.URLParam(r, "analyteId"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid analyteId")
		return
	}
	content, count, err := analysis.Generate(r.Context(), s.q, s.extractor, p.ID, analyteID)
	switch {
	case errors.Is(err, analysis.ErrNoResults):
		writeError(w, http.StatusBadRequest, "no results to analyze")
		return
	case errors.Is(err, pgx.ErrNoRows):
		writeError(w, http.StatusNotFound, "analyte not found")
		return
	case err != nil:
		s.log.Error("analyze", "err", err)
		writeError(w, http.StatusBadGateway, "analysis failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"analysis": AnalysisDTO{
		Content:      content,
		GeneratedAt:  time.Now().UTC().Format(time.RFC3339),
		BasedOnCount: count,
		CurrentCount: count,
		Stale:        false,
	}})
}

func toAnalysisDTO(a sqlc.AnalyteAnalysis, current int, stale bool) AnalysisDTO {
	gen := ""
	if a.GeneratedAt.Valid {
		gen = a.GeneratedAt.Time.UTC().Format(time.RFC3339)
	}
	return AnalysisDTO{
		Content:      a.Content,
		GeneratedAt:  gen,
		BasedOnCount: int(a.ResultCount),
		CurrentCount: current,
		Stale:        stale,
	}
}
