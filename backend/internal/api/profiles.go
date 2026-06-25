package api

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
)

func (s *Server) listProfiles(w http.ResponseWriter, r *http.Request) {
	rows, err := s.q.ListProfiles(r.Context())
	if err != nil {
		s.log.Error("list profiles", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to list profiles")
		return
	}
	out := make([]ProfileDTO, 0, len(rows))
	for _, p := range rows {
		out = append(out, toProfileDTO(p))
	}
	writeJSON(w, http.StatusOK, out)
}

type createProfileReq struct {
	Name        string  `json:"name"`
	DateOfBirth *string `json:"dateOfBirth"`
}

func (s *Server) createProfile(w http.ResponseWriter, r *http.Request) {
	var req createProfileReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	p, err := s.q.CreateProfile(r.Context(), sqlc.CreateProfileParams{
		Name:        req.Name,
		DateOfBirth: ptrToDate(req.DateOfBirth),
	})
	if err != nil {
		s.log.Error("create profile", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to create profile")
		return
	}
	writeJSON(w, http.StatusCreated, toProfileDTO(p))
}

func (s *Server) deleteProfile(w http.ResponseWriter, r *http.Request) {
	id, ok := parseUUID(chi.URLParam(r, "id"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}
	if err := s.q.DeleteProfile(r.Context(), id); err != nil {
		s.log.Error("delete profile", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to delete profile")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// requireProfile loads a profile or writes a 404, returning ok=false on miss.
func (s *Server) requireProfile(w http.ResponseWriter, r *http.Request) (sqlc.Profile, bool) {
	id, ok := parseUUID(chi.URLParam(r, "id"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid id")
		return sqlc.Profile{}, false
	}
	p, err := s.q.GetProfile(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "profile not found")
		return sqlc.Profile{}, false
	}
	if err != nil {
		s.log.Error("get profile", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load profile")
		return sqlc.Profile{}, false
	}
	return p, true
}
