package api

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
)

type updateResultReq struct {
	AnalyteID     string   `json:"analyteId"`
	ValueText     *string  `json:"valueText"`
	ValueNumeric  *float64 `json:"valueNumeric"`
	Unit          *string  `json:"unit"`
	ReferenceLow  *float64 `json:"referenceLow"`
	ReferenceHigh *float64 `json:"referenceHigh"`
	ReferenceText *string  `json:"referenceText"`
	Note          *string  `json:"note"`
	ObservedDate  *string  `json:"observedDate"`
}

func (s *Server) updateResult(w http.ResponseWriter, r *http.Request) {
	id, ok := parseUUID(chi.URLParam(r, "id"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}
	if !s.requireResultAccess(w, r, id) {
		return
	}
	var req updateResultReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	analyteID, ok := parseUUID(req.AnalyteID)
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid analyteId")
		return
	}
	obs := ptrToDate(req.ObservedDate)
	if !obs.Valid {
		writeError(w, http.StatusBadRequest, "an observed date is required")
		return
	}
	if err := s.q.UpdateResult(r.Context(), sqlc.UpdateResultParams{
		ID:            id,
		AnalyteID:     analyteID,
		ValueText:     ptrToText(req.ValueText),
		ValueNumeric:  ptrToFloat8(req.ValueNumeric),
		Unit:          ptrToText(req.Unit),
		ReferenceLow:  ptrToFloat8(req.ReferenceLow),
		ReferenceHigh: ptrToFloat8(req.ReferenceHigh),
		ReferenceText: ptrToText(req.ReferenceText),
		Note:          ptrToText(req.Note),
		ObservedDate:  obs,
	}); err != nil {
		s.log.Error("update result", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to update result")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) deleteResult(w http.ResponseWriter, r *http.Request) {
	id, ok := parseUUID(chi.URLParam(r, "id"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}
	if !s.requireResultAccess(w, r, id) {
		return
	}
	if err := s.q.DeleteResult(r.Context(), id); err != nil {
		s.log.Error("delete result", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to delete result")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// requireResultAccess verifies the current user may access the profile that owns
// the given result. Writes a 404 and returns false otherwise.
func (s *Server) requireResultAccess(w http.ResponseWriter, r *http.Request, id uuid.UUID) bool {
	res, err := s.q.GetResult(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "result not found")
		return false
	}
	if err != nil {
		s.log.Error("get result", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load result")
		return false
	}
	if !s.canAccessProfile(r, res.ProfileID) {
		writeError(w, http.StatusNotFound, "result not found")
		return false
	}
	return true
}

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
