package api

import (
	"net/http"
	"time"
)

// MeDTO is the current authenticated user, including whether they're a super-user.
type MeDTO struct {
	UserID  string  `json:"userId"`
	Email   *string `json:"email"`
	Name    *string `json:"name"`
	IsAdmin bool    `json:"isAdmin"`
}

// getMe returns the current user and their admin status (used by the SPA to gate
// the admin area).
func (s *Server) getMe(w http.ResponseWriter, r *http.Request) {
	uid := currentUserID(r.Context())
	me := MeDTO{UserID: uid.String(), IsAdmin: isAdmin(r.Context())}
	if u, err := s.q.GetUser(r.Context(), uid); err == nil {
		me.Email = textToPtr(u.Email)
		me.Name = textToPtr(u.Name)
	}
	writeJSON(w, http.StatusOK, me)
}

// AdminUserDTO is one user row in the admin area, with profile counts.
type AdminUserDTO struct {
	ID          string  `json:"id"`
	Email       *string `json:"email"`
	Name        *string `json:"name"`
	OidcSub     string  `json:"oidcSub"`
	CreatedAt   string  `json:"createdAt"`
	LastSeenAt  string  `json:"lastSeenAt"`
	OwnedCount  int     `json:"ownedCount"`
	SharedCount int     `json:"sharedCount"`
}

// listAllUsers returns every user with profile counts. Super-user only.
func (s *Server) listAllUsers(w http.ResponseWriter, r *http.Request) {
	if !isAdmin(r.Context()) {
		writeError(w, http.StatusForbidden, "admin access required")
		return
	}
	rows, err := s.q.ListUsersWithProfileCounts(r.Context())
	if err != nil {
		s.log.Error("list users", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to list users")
		return
	}
	out := make([]AdminUserDTO, 0, len(rows))
	for _, u := range rows {
		dto := AdminUserDTO{
			ID:          u.ID.String(),
			Email:       textToPtr(u.Email),
			Name:        textToPtr(u.Name),
			OidcSub:     u.OidcSub,
			OwnedCount:  int(u.OwnedCount),
			SharedCount: int(u.SharedCount),
		}
		if u.CreatedAt.Valid {
			dto.CreatedAt = u.CreatedAt.Time.UTC().Format(time.RFC3339)
		}
		if u.LastSeenAt.Valid {
			dto.LastSeenAt = u.LastSeenAt.Time.UTC().Format(time.RFC3339)
		}
		out = append(out, dto)
	}
	writeJSON(w, http.StatusOK, out)
}
