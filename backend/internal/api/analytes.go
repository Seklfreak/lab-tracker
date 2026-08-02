package api

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func (s *Server) listAnalytes(w http.ResponseWriter, r *http.Request) {
	rows, err := s.q.ListAnalytes(r.Context())
	if err != nil {
		s.log.Error("list analytes", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to list analytes")
		return
	}
	out := make([]AnalyteDTO, 0, len(rows))
	for _, a := range rows {
		out = append(out, toAnalyteDTO(a))
	}
	writeJSON(w, http.StatusOK, out)
}

type mergeAnalytesReq struct {
	TargetID  string   `json:"targetId"`  // the analyte to keep
	SourceIDs []string `json:"sourceIds"` // duplicate analytes folded into the target
}

// mergeAnalytes folds one or more duplicate analytes into a kept one: all results,
// aliases, favorites, and analyses move to the target, the sources' names become
// aliases (so future uploads map to the target), and the sources are deleted.
//
// Analytes are a GLOBAL catalog shared by every profile, so this affects all users
// and is irreversible — hence super-user only.
func (s *Server) mergeAnalytes(w http.ResponseWriter, r *http.Request) {
	if !isAdmin(r.Context()) {
		writeError(w, http.StatusForbidden, "admin access required")
		return
	}
	var req mergeAnalytesReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	target, err := uuid.Parse(req.TargetID)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid targetId")
		return
	}
	if len(req.SourceIDs) == 0 {
		writeError(w, http.StatusBadRequest, "sourceIds is required")
		return
	}
	sources := make([]uuid.UUID, 0, len(req.SourceIDs))
	for _, raw := range req.SourceIDs {
		id, err := uuid.Parse(raw)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid sourceId")
			return
		}
		if id == target {
			writeError(w, http.StatusBadRequest, "the target cannot also be a source")
			return
		}
		sources = append(sources, id)
	}

	ctx := r.Context()
	if _, err := s.q.GetAnalyte(ctx, target); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "target analyte not found")
			return
		}
		s.log.Error("merge: load target", "err", err)
		writeError(w, http.StatusInternalServerError, "merge failed")
		return
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		s.log.Error("merge: begin tx", "err", err)
		writeError(w, http.StatusInternalServerError, "merge failed")
		return
	}
	defer tx.Rollback(ctx)
	qtx := sqlc.New(tx)

	// Order matters: free lab_results (RESTRICT) and repoint/keep aliases before
	// deleting the sources; remaining favorites/analyses cascade on delete.
	if err := qtx.RepointResultsToAnalyte(ctx, sqlc.RepointResultsToAnalyteParams{Target: target, Sources: sources}); err != nil {
		s.log.Error("merge: repoint results", "err", err)
		writeError(w, http.StatusInternalServerError, "merge failed")
		return
	}
	if err := qtx.RepointAliasesToAnalyte(ctx, sqlc.RepointAliasesToAnalyteParams{Target: target, Sources: sources}); err != nil {
		s.log.Error("merge: repoint aliases", "err", err)
		writeError(w, http.StatusInternalServerError, "merge failed")
		return
	}
	if err := qtx.AddAnalyteNamesAsAliases(ctx, sqlc.AddAnalyteNamesAsAliasesParams{Target: target, Sources: sources}); err != nil {
		s.log.Error("merge: add name aliases", "err", err)
		writeError(w, http.StatusInternalServerError, "merge failed")
		return
	}
	if err := qtx.MigrateFavoritesToAnalyte(ctx, sqlc.MigrateFavoritesToAnalyteParams{Target: target, Sources: sources}); err != nil {
		s.log.Error("merge: migrate favorites", "err", err)
		writeError(w, http.StatusInternalServerError, "merge failed")
		return
	}
	if err := qtx.DeleteAnalytes(ctx, sources); err != nil {
		s.log.Error("merge: delete sources", "err", err)
		writeError(w, http.StatusInternalServerError, "merge failed")
		return
	}
	if err := tx.Commit(ctx); err != nil {
		s.log.Error("merge: commit", "err", err)
		writeError(w, http.StatusInternalServerError, "merge failed")
		return
	}

	merged, err := s.q.GetAnalyte(ctx, target)
	if err != nil {
		s.log.Error("merge: reload target", "err", err)
		writeError(w, http.StatusInternalServerError, "merge succeeded but reload failed")
		return
	}
	writeJSON(w, http.StatusOK, toAnalyteDTO(merged))
}

func (s *Server) listProfileAnalytes(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	rows, err := s.q.ListAnalytesWithDataForProfile(r.Context(), p.ID)
	if err != nil {
		s.log.Error("list profile analytes", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to list analytes")
		return
	}
	out := make([]AnalyteDTO, 0, len(rows))
	for _, a := range rows {
		out = append(out, toAnalyteDTO(a))
	}
	writeJSON(w, http.StatusOK, out)
}
