package api

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
)

// MemberDTO is one person with access to a profile. The owner is included with
// isOwner=true and role "owner"; shared users have role "editor".
type MemberDTO struct {
	UserID  string  `json:"userId"`
	Email   *string `json:"email"`
	Name    *string `json:"name"`
	Role    string  `json:"role"`
	IsOwner bool    `json:"isOwner"`
}

// listMembers returns everyone who can access a profile (owner first, then
// shared editors). Any user with access may view the member list.
func (s *Server) listMembers(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}

	out := make([]MemberDTO, 0, 4)
	if p.OwnerUserID != nil {
		if owner, err := s.q.GetUser(r.Context(), *p.OwnerUserID); err == nil {
			out = append(out, MemberDTO{
				UserID:  owner.ID.String(),
				Email:   textToPtr(owner.Email),
				Name:    textToPtr(owner.Name),
				Role:    "owner",
				IsOwner: true,
			})
		} else if !errors.Is(err, pgx.ErrNoRows) {
			s.log.Error("get owner", "err", err)
			writeError(w, http.StatusInternalServerError, "failed to load members")
			return
		}
	}

	members, err := s.q.ListProfileMembers(r.Context(), p.ID)
	if err != nil {
		s.log.Error("list members", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load members")
		return
	}
	for _, m := range members {
		out = append(out, MemberDTO{
			UserID: m.UserID.String(),
			Email:  textToPtr(m.Email),
			Name:   textToPtr(m.Name),
			Role:   m.Role,
		})
	}
	writeJSON(w, http.StatusOK, out)
}

type addMemberReq struct {
	Email string `json:"email"`
}

// addMember shares a profile with another user (owner only). The target must
// have signed in at least once, so we can resolve their email to a user row.
func (s *Server) addMember(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireOwner(w, r)
	if !ok {
		return
	}
	var req addMemberReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Email == "" {
		writeError(w, http.StatusBadRequest, "email is required")
		return
	}

	target, err := s.q.GetUserByEmail(r.Context(), req.Email)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "no user with that email has signed in yet — they must log in once before you can share with them")
		return
	}
	if err != nil {
		s.log.Error("lookup user by email", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to share profile")
		return
	}
	if p.OwnerUserID != nil && target.ID == *p.OwnerUserID {
		writeError(w, http.StatusBadRequest, "that user already owns this profile")
		return
	}

	if err := s.q.AddProfileMember(r.Context(), sqlc.AddProfileMemberParams{
		ProfileID: p.ID,
		UserID:    target.ID,
		Role:      "editor",
	}); err != nil {
		s.log.Error("add member", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to share profile")
		return
	}
	writeJSON(w, http.StatusCreated, MemberDTO{
		UserID: target.ID.String(),
		Email:  textToPtr(target.Email),
		Name:   textToPtr(target.Name),
		Role:   "editor",
	})
}

// removeMember revokes a user's shared access (owner only).
func (s *Server) removeMember(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireOwner(w, r)
	if !ok {
		return
	}
	userID, ok := parseUUID(chi.URLParam(r, "userId"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid userId")
		return
	}
	if err := s.q.RemoveProfileMember(r.Context(), sqlc.RemoveProfileMemberParams{
		ProfileID: p.ID,
		UserID:    userID,
	}); err != nil {
		s.log.Error("remove member", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to remove member")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// requireOwner loads the profile and confirms the current user owns it (403 if
// they only have shared access), for member-management endpoints.
func (s *Server) requireOwner(w http.ResponseWriter, r *http.Request) (sqlc.Profile, bool) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return sqlc.Profile{}, false
	}
	if !isOwner(p, currentUserID(r.Context())) {
		writeError(w, http.StatusForbidden, "only the owner can manage sharing")
		return sqlc.Profile{}, false
	}
	return p, true
}
