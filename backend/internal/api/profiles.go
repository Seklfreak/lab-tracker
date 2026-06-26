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

func (s *Server) listProfiles(w http.ResponseWriter, r *http.Request) {
	uid := currentUserID(r.Context())
	rows, err := s.q.ListProfilesForUser(r.Context(), &uid)
	if err != nil {
		s.log.Error("list profiles", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to list profiles")
		return
	}
	out := make([]ProfileDTO, 0, len(rows))
	for _, p := range rows {
		out = append(out, toProfileDTO(p, uid))
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
	uid := currentUserID(r.Context())
	p, err := s.q.CreateProfile(r.Context(), sqlc.CreateProfileParams{
		Name:        req.Name,
		DateOfBirth: ptrToDate(req.DateOfBirth),
		OwnerUserID: &uid,
	})
	if err != nil {
		s.log.Error("create profile", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to create profile")
		return
	}
	writeJSON(w, http.StatusCreated, toProfileDTO(p, uid))
}

func (s *Server) deleteProfile(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	if !isOwner(p, currentUserID(r.Context())) {
		writeError(w, http.StatusForbidden, "only the owner can delete this profile")
		return
	}
	if err := s.q.DeleteProfile(r.Context(), p.ID); err != nil {
		s.log.Error("delete profile", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to delete profile")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// requireProfile loads a profile the current user may access (owned or shared),
// or writes a 404/400 and returns ok=false. Inaccessible profiles 404 so their
// existence isn't leaked.
func (s *Server) requireProfile(w http.ResponseWriter, r *http.Request) (sqlc.Profile, bool) {
	id, ok := parseUUID(chi.URLParam(r, "id"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid id")
		return sqlc.Profile{}, false
	}
	return s.profileForUser(w, r, id)
}

// profileForUser loads a specific profile id scoped to the current user.
func (s *Server) profileForUser(w http.ResponseWriter, r *http.Request, id uuid.UUID) (sqlc.Profile, bool) {
	uid := currentUserID(r.Context())
	p, err := s.q.GetProfileForUser(r.Context(), sqlc.GetProfileForUserParams{ID: id, UserID: &uid})
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

// canAccessProfile reports whether the current user may access the given profile
// (owned or shared). Used to guard endpoints keyed on report/result ids that
// don't carry the profile in the URL. Denies on any error.
func (s *Server) canAccessProfile(r *http.Request, profileID uuid.UUID) bool {
	uid := currentUserID(r.Context())
	_, err := s.q.GetProfileForUser(r.Context(), sqlc.GetProfileForUserParams{ID: profileID, UserID: &uid})
	return err == nil
}

// isOwner reports whether uid owns the profile.
func isOwner(p sqlc.Profile, uid uuid.UUID) bool {
	return p.OwnerUserID != nil && *p.OwnerUserID == uid
}
