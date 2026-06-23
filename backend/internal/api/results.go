package api

import (
	"net/http"

	"github.com/winkler/lab-tracker/backend/internal/db/sqlc"
)

// listResults returns all results for a profile, or just one analyte's trend
// when ?analyte_id= is supplied.
func (s *Server) listResults(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}

	if raw := r.URL.Query().Get("analyte_id"); raw != "" {
		analyteID, ok := parseUUID(raw)
		if !ok {
			writeError(w, http.StatusBadRequest, "invalid analyte_id")
			return
		}
		rows, err := s.q.ListResultsForProfileAnalyte(r.Context(), sqlc.ListResultsForProfileAnalyteParams{
			ProfileID: p.ID,
			AnalyteID: analyteID,
		})
		if err != nil {
			s.log.Error("list results for analyte", "err", err)
			writeError(w, http.StatusInternalServerError, "failed to list results")
			return
		}
		out := make([]ResultDTO, 0, len(rows))
		for _, row := range rows {
			out = append(out, toResultDTOFromAnalyte(row))
		}
		writeJSON(w, http.StatusOK, out)
		return
	}

	// Default: latest value per analyte (for the dashboard).
	if r.URL.Query().Get("all") == "true" {
		rows, err := s.q.ListResultsForProfile(r.Context(), p.ID)
		if err != nil {
			s.log.Error("list all results", "err", err)
			writeError(w, http.StatusInternalServerError, "failed to list results")
			return
		}
		out := make([]ResultDTO, 0, len(rows))
		for _, row := range rows {
			out = append(out, toResultDTO(row))
		}
		writeJSON(w, http.StatusOK, out)
		return
	}

	rows, err := s.q.ListLatestResultsForProfile(r.Context(), p.ID)
	if err != nil {
		s.log.Error("list latest results", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to list results")
		return
	}
	out := make([]ResultDTO, 0, len(rows))
	for _, row := range rows {
		out = append(out, toResultDTOFromLatest(row))
	}
	writeJSON(w, http.StatusOK, out)
}
