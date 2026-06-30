package api

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
)

type updateProfileReq struct {
	Name        string  `json:"name"`
	DateOfBirth *string `json:"dateOfBirth"`
}

// updateProfile edits a profile's name + birthdate. Sends the full desired
// state (the edit form has both fields).
func (s *Server) updateProfile(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	var req updateProfileReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	uid := currentUserID(r.Context())
	updated, err := s.q.UpdateProfile(r.Context(), sqlc.UpdateProfileParams{
		ID:          p.ID,
		Name:        req.Name,
		DateOfBirth: ptrToDate(req.DateOfBirth),
	})
	if err != nil {
		s.log.Error("update profile", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to update profile")
		return
	}
	writeJSON(w, http.StatusOK, toProfileDTO(updated, uid))
}

func (s *Server) listBody(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	rows, err := s.q.ListBodyMeasurements(r.Context(), p.ID)
	if err != nil {
		s.log.Error("list body measurements", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to list measurements")
		return
	}
	out := make([]BodyMeasurementDTO, 0, len(rows))
	for _, m := range rows {
		out = append(out, toBodyMeasurementDTO(m))
	}
	writeJSON(w, http.StatusOK, out)
}

type addBodyReq struct {
	Kind       string  `json:"kind"`
	Value      float64 `json:"value"`
	MeasuredOn *string `json:"measuredOn"`
}

func (s *Server) addBody(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	var req addBodyReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.Kind != "weight" && req.Kind != "height" {
		writeError(w, http.StatusBadRequest, "kind must be weight or height")
		return
	}
	if req.Value <= 0 {
		writeError(w, http.StatusBadRequest, "value must be positive")
		return
	}
	measured := ptrToDate(req.MeasuredOn)
	if !measured.Valid {
		measured = pgtype.Date{Time: time.Now(), Valid: true}
	}
	m, err := s.q.AddBodyMeasurement(r.Context(), sqlc.AddBodyMeasurementParams{
		ProfileID:  p.ID,
		Kind:       req.Kind,
		Value:      req.Value,
		MeasuredOn: measured,
	})
	if err != nil {
		s.log.Error("add body measurement", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to add measurement")
		return
	}
	writeJSON(w, http.StatusCreated, toBodyMeasurementDTO(m))
}

func (s *Server) deleteBody(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	mid, ok := parseUUID(chi.URLParam(r, "measurementId"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}
	if err := s.q.DeleteBodyMeasurement(r.Context(), sqlc.DeleteBodyMeasurementParams{ID: mid, ProfileID: p.ID}); err != nil {
		s.log.Error("delete body measurement", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to delete measurement")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
