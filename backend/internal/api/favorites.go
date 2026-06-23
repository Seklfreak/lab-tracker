package api

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/winkler/lab-tracker/backend/internal/db/sqlc"
)

type favoriteReq struct {
	AnalyteID string `json:"analyteId"`
}

func (s *Server) addFavorite(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	var req favoriteReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	analyteID, ok := parseUUID(req.AnalyteID)
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid analyteId")
		return
	}
	if err := s.q.AddFavorite(r.Context(), sqlc.AddFavoriteParams{ProfileID: p.ID, AnalyteID: analyteID}); err != nil {
		s.log.Error("add favorite", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to add favorite")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) removeFavorite(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	analyteID, ok := parseUUID(chi.URLParam(r, "analyteId"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid analyteId")
		return
	}
	if err := s.q.RemoveFavorite(r.Context(), sqlc.RemoveFavoriteParams{ProfileID: p.ID, AnalyteID: analyteID}); err != nil {
		s.log.Error("remove favorite", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to remove favorite")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
