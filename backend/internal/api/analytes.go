package api

import (
	"net/http"
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
