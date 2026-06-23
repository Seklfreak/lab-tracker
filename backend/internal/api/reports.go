package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/winkler/lab-tracker/backend/internal/db/sqlc"
	"github.com/winkler/lab-tracker/backend/internal/llm"
)

const maxUploadBytes = 25 << 20 // 25 MiB

func (s *Server) uploadReport(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxUploadBytes)
	if err := r.ParseMultipartForm(maxUploadBytes); err != nil {
		writeError(w, http.StatusBadRequest, "could not parse upload (max 25MB)")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "missing 'file' field")
		return
	}
	defer file.Close()

	data, err := io.ReadAll(file)
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not read upload")
		return
	}

	objectKey := fmt.Sprintf("%s/%s.pdf", p.ID, uuid.New())
	if err := s.store.PutPDF(r.Context(), objectKey, data); err != nil {
		s.log.Error("store pdf", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to store PDF")
		return
	}

	report, err := s.q.CreateReport(r.Context(), sqlc.CreateReportParams{
		ProfileID:        p.ID,
		PdfObjectKey:     objectKey,
		OriginalFilename: ptrToText(&header.Filename),
	})
	if err != nil {
		s.log.Error("create report", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to create report")
		return
	}

	// Parse asynchronously; the frontend polls GET /reports/{id} for status.
	go s.parseReport(report.ID, data)

	writeJSON(w, http.StatusAccepted, toReportDTO(report))
}

// parseReport runs PDF extraction in the background and updates the report row.
func (s *Server) parseReport(reportID uuid.UUID, pdf []byte) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()

	extracted, err := s.extractor.Extract(ctx, pdf)
	if err != nil {
		s.log.Error("extract pdf", "report", reportID, "err", err)
		_ = s.q.SetReportError(ctx, sqlc.SetReportErrorParams{
			ID:         reportID,
			ParseError: ptrToText(strPtr(err.Error())),
		})
		return
	}

	draft := s.enrichDraft(ctx, extracted)
	draftJSON, err := json.Marshal(draft)
	if err != nil {
		s.log.Error("marshal draft", "report", reportID, "err", err)
		_ = s.q.SetReportError(ctx, sqlc.SetReportErrorParams{
			ID:         reportID,
			ParseError: ptrToText(strPtr("failed to serialize extraction")),
		})
		return
	}

	if err := s.q.SetReportParsed(ctx, sqlc.SetReportParsedParams{
		ID:            reportID,
		ParsedDraft:   draftJSON,
		SourceLab:     ptrToText(extracted.LabName),
		CollectedDate: ptrToDate(extracted.CollectedDate),
		ReportedDate:  ptrToDate(extracted.ReportedDate),
	}); err != nil {
		s.log.Error("set report parsed", "report", reportID, "err", err)
	}
}

func (s *Server) getReport(w http.ResponseWriter, r *http.Request) {
	report, ok := s.requireReport(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, toReportDTO(report))
}

func (s *Server) listReports(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	rows, err := s.q.ListReportsForProfile(r.Context(), p.ID)
	if err != nil {
		s.log.Error("list reports", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to list reports")
		return
	}
	out := make([]ReportDTO, 0, len(rows))
	for _, row := range rows {
		out = append(out, toReportDTO(row))
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) getReportPDF(w http.ResponseWriter, r *http.Request) {
	report, ok := s.requireReport(w, r)
	if !ok {
		return
	}
	obj, err := s.store.GetPDF(r.Context(), report.PdfObjectKey)
	if err != nil {
		s.log.Error("get pdf", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load PDF")
		return
	}
	defer obj.Close()

	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Disposition", "inline")
	if _, err := io.Copy(w, obj); err != nil {
		s.log.Error("stream pdf", "err", err)
	}
}

func (s *Server) deleteReport(w http.ResponseWriter, r *http.Request) {
	report, ok := s.requireReport(w, r)
	if !ok {
		return
	}
	// Best-effort PDF removal; proceed with the DB delete regardless.
	if err := s.store.DeletePDF(r.Context(), report.PdfObjectKey); err != nil {
		s.log.Warn("delete pdf object", "report", report.ID, "err", err)
	}
	if err := s.q.DeleteReport(r.Context(), report.ID); err != nil {
		s.log.Error("delete report", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to delete report")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// reparseReport re-runs extraction on a report's stored PDF (e.g. to retry a
// failed parse or re-do a discarded one).
func (s *Server) reparseReport(w http.ResponseWriter, r *http.Request) {
	report, ok := s.requireReport(w, r)
	if !ok {
		return
	}
	obj, err := s.store.GetPDF(r.Context(), report.PdfObjectKey)
	if err != nil {
		s.log.Error("get pdf for reparse", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load PDF")
		return
	}
	defer obj.Close()
	data, err := io.ReadAll(obj)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to read PDF")
		return
	}
	if err := s.q.SetReportParsing(r.Context(), report.ID); err != nil {
		s.log.Error("set report parsing", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to reparse")
		return
	}
	go s.parseReport(report.ID, data)

	updated, err := s.q.GetReport(r.Context(), report.ID)
	if err != nil {
		writeJSON(w, http.StatusAccepted, map[string]string{"status": "parsing"})
		return
	}
	writeJSON(w, http.StatusAccepted, toReportDTO(updated))
}

type confirmResult struct {
	AnalyteID      *string  `json:"analyteId"`
	NewAnalyteName *string  `json:"newAnalyteName"`
	NewAnalyteUnit *string  `json:"newAnalyteUnit"`
	RawTestName    string   `json:"rawTestName"`
	ValueText      *string  `json:"valueText"`
	ValueNumeric   *float64 `json:"valueNumeric"`
	Unit           *string  `json:"unit"`
	ReferenceLow   *float64 `json:"referenceLow"`
	ReferenceHigh  *float64 `json:"referenceHigh"`
	ReferenceText  *string  `json:"referenceText"`
	Note           *string  `json:"note"`
	ObservedDate   *string  `json:"observedDate"`
	LearnAlias     bool     `json:"learnAlias"`
}

type confirmReq struct {
	SourceLab     *string         `json:"sourceLab"`
	CollectedDate *string         `json:"collectedDate"`
	ReportedDate  *string         `json:"reportedDate"`
	Results       []confirmResult `json:"results"`
}

func (s *Server) confirmReport(w http.ResponseWriter, r *http.Request) {
	report, ok := s.requireReport(w, r)
	if !ok {
		return
	}

	var req confirmReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if len(req.Results) == 0 {
		writeError(w, http.StatusBadRequest, "no results to save")
		return
	}

	ctx := r.Context()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		s.log.Error("begin tx", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to save")
		return
	}
	defer tx.Rollback(ctx)
	qtx := s.q.WithTx(tx)

	// Re-confirming replaces any previously saved results for this report.
	if err := qtx.DeleteResultsForReport(ctx, report.ID); err != nil {
		s.log.Error("delete prior results", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to save")
		return
	}

	for i, res := range req.Results {
		analyteID, err := s.resolveAnalyte(ctx, qtx, res)
		if err != nil {
			writeError(w, http.StatusBadRequest, fmt.Sprintf("result %d: %s", i+1, err.Error()))
			return
		}

		if res.LearnAlias && res.RawTestName != "" {
			if err := qtx.UpsertAlias(ctx, sqlc.UpsertAliasParams{
				AnalyteID: analyteID,
				RawName:   res.RawTestName,
			}); err != nil {
				s.log.Error("upsert alias", "err", err)
				writeError(w, http.StatusInternalServerError, "failed to save alias")
				return
			}
		}

		observed := res.ObservedDate
		if observed == nil || *observed == "" {
			observed = req.CollectedDate
		}
		obsDate := ptrToDate(observed)
		if !obsDate.Valid {
			writeError(w, http.StatusBadRequest, fmt.Sprintf("result %d: an observed date is required", i+1))
			return
		}

		if _, err := qtx.CreateResult(ctx, sqlc.CreateResultParams{
			ReportID:      report.ID,
			ProfileID:     report.ProfileID,
			AnalyteID:     analyteID,
			RawTestName:   res.RawTestName,
			ValueText:     ptrToText(res.ValueText),
			ValueNumeric:  ptrToFloat8(res.ValueNumeric),
			Unit:          ptrToText(res.Unit),
			ReferenceLow:  ptrToFloat8(res.ReferenceLow),
			ReferenceHigh: ptrToFloat8(res.ReferenceHigh),
			ReferenceText: ptrToText(res.ReferenceText),
			Note:          ptrToText(res.Note),
			ObservedDate:  obsDate,
		}); err != nil {
			s.log.Error("create result", "err", err)
			writeError(w, http.StatusInternalServerError, "failed to save result")
			return
		}
	}

	if err := qtx.SetReportSaved(ctx, sqlc.SetReportSavedParams{
		ID:            report.ID,
		SourceLab:     ptrToText(req.SourceLab),
		CollectedDate: ptrToDate(req.CollectedDate),
		ReportedDate:  ptrToDate(req.ReportedDate),
	}); err != nil {
		s.log.Error("set report saved", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to save")
		return
	}

	if err := tx.Commit(ctx); err != nil {
		s.log.Error("commit", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to save")
		return
	}

	updated, err := s.q.GetReport(ctx, report.ID)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]string{"status": "saved"})
		return
	}
	writeJSON(w, http.StatusOK, toReportDTO(updated))
}

// resolveAnalyte returns the analyte id for a confirm-result row, creating a
// new analyte when newAnalyteName is supplied without an existing id.
func (s *Server) resolveAnalyte(ctx context.Context, qtx *sqlc.Queries, res confirmResult) (uuid.UUID, error) {
	if res.AnalyteID != nil && *res.AnalyteID != "" {
		id, err := uuid.Parse(*res.AnalyteID)
		if err != nil {
			return uuid.Nil, fmt.Errorf("invalid analyteId")
		}
		return id, nil
	}
	if res.NewAnalyteName != nil && *res.NewAnalyteName != "" {
		name := *res.NewAnalyteName
		if existing, err := qtx.GetAnalyteByName(ctx, name); err == nil {
			return existing.ID, nil
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return uuid.Nil, fmt.Errorf("lookup analyte: %w", err)
		}
		created, err := qtx.CreateAnalyte(ctx, sqlc.CreateAnalyteParams{
			Name:        name,
			DefaultUnit: ptrToText(res.NewAnalyteUnit),
			Category:    ptrToText(nil),
		})
		if err != nil {
			return uuid.Nil, fmt.Errorf("create analyte: %w", err)
		}
		return created.ID, nil
	}
	return uuid.Nil, fmt.Errorf("analyteId or newAnalyteName is required")
}

func (s *Server) requireReport(w http.ResponseWriter, r *http.Request) (sqlc.LabReport, bool) {
	id, ok := parseUUID(chi.URLParam(r, "id"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid id")
		return sqlc.LabReport{}, false
	}
	report, err := s.q.GetReport(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "report not found")
		return sqlc.LabReport{}, false
	}
	if err != nil {
		s.log.Error("get report", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load report")
		return sqlc.LabReport{}, false
	}
	return report, true
}

func strPtr(s string) *string { return &s }

// enrichDraft converts a raw extraction into the review-ready draft, resolving
// each parsed test name to a canonical analyte via the alias table when possible.
func (s *Server) enrichDraft(ctx context.Context, ex *llm.ExtractedReport) DraftDTO {
	draft := DraftDTO{
		LabName:       ex.LabName,
		CollectedDate: ex.CollectedDate,
		ReportedDate:  ex.ReportedDate,
		Results:       make([]DraftResultDTO, 0, len(ex.Results)),
	}
	for _, r := range ex.Results {
		row := DraftResultDTO{
			TestName:       r.TestName,
			Value:          r.Value,
			ValueNumeric:   r.ValueNumeric,
			Unit:           r.Unit,
			ReferenceRange: r.ReferenceRange,
			ReferenceLow:   r.ReferenceLow,
			ReferenceHigh:  r.ReferenceHigh,
			Specimen:       r.Specimen,
			Note:           r.Note,
		}
		wantUrine := r.Specimen != nil && strings.EqualFold(strings.TrimSpace(*r.Specimen), "urine")
		row.SuggestedAnalyteID, row.SuggestedAnalyteName = s.suggestAnalyte(ctx, r.TestName, wantUrine)
		draft.Results = append(draft.Results, row)
	}

	// Second pass: for rows with no exact match, ask the model to map them to an
	// existing analyte (conservative — same-specimen synonyms only). These
	// suggestions are flagged so the user verifies them.
	var inputs []llm.MatchInput
	for _, row := range draft.Results {
		if row.SuggestedAnalyteID == nil {
			spec := ""
			if row.Specimen != nil {
				spec = *row.Specimen
			}
			inputs = append(inputs, llm.MatchInput{TestName: row.TestName, Specimen: spec})
		}
	}
	if len(inputs) > 0 {
		if matches := s.semanticMatch(ctx, inputs); len(matches) > 0 {
			for i := range draft.Results {
				if draft.Results[i].SuggestedAnalyteID != nil {
					continue
				}
				if a, ok := matches[draft.Results[i].TestName]; ok {
					id := a.ID.String()
					name := a.Name
					draft.Results[i].SuggestedAnalyteID = &id
					draft.Results[i].SuggestedAnalyteName = &name
					draft.Results[i].SuggestedByAI = true
				}
			}
		}
	}
	return draft
}

// semanticMatch maps unmatched test names to existing analytes via the LLM,
// validating the model's answers against the live catalog. Best-effort: returns
// an empty map on any failure (rows just stay unmatched).
func (s *Server) semanticMatch(ctx context.Context, inputs []llm.MatchInput) map[string]sqlc.Analyte {
	catalog, err := s.q.ListAnalytes(ctx)
	if err != nil {
		s.log.Error("list analytes for semantic match", "err", err)
		return nil
	}
	opts := make([]llm.AnalyteOption, 0, len(catalog))
	byName := make(map[string]sqlc.Analyte, len(catalog))
	for _, a := range catalog {
		cat := ""
		if a.Category.Valid {
			cat = a.Category.String
		}
		opts = append(opts, llm.AnalyteOption{Name: a.Name, Specimens: a.Specimens, Category: cat})
		byName[strings.ToLower(strings.TrimSpace(a.Name))] = a
	}
	raw, err := s.extractor.MatchAnalytes(ctx, inputs, opts)
	if err != nil {
		s.log.Warn("semantic analyte match", "err", err)
		return nil
	}
	out := make(map[string]sqlc.Analyte, len(raw))
	for testName, analyteName := range raw {
		if a, ok := byName[strings.ToLower(strings.TrimSpace(analyteName))]; ok {
			out[testName] = a
		}
	}
	return out
}

// suggestAnalyte resolves a parsed test name to a canonical analyte. It prefers
// a specimen-specific match (so urine "Glucose" → Urine Glucose, serum
// "Glucose" → Glucose), then falls back to a specimen-agnostic match so
// specimen-neutral tests (e.g. a urogenital CT/NG NAAT reported on urine) still
// map to their single canonical analyte. Returns (nil, nil) if nothing matches.
func (s *Server) suggestAnalyte(ctx context.Context, testName string, wantUrine bool) (*string, *string) {
	ptrs := func(a sqlc.Analyte) (*string, *string) {
		id := a.ID.String()
		name := a.Name
		return &id, &name
	}
	if a, err := s.q.MatchAliasBySpecimen(ctx, sqlc.MatchAliasBySpecimenParams{RawName: testName, WantUrine: wantUrine}); err == nil {
		return ptrs(a)
	}
	if a, err := s.q.MatchAnalyteBySpecimen(ctx, sqlc.MatchAnalyteBySpecimenParams{Name: testName, WantUrine: wantUrine}); err == nil {
		return ptrs(a)
	}
	if a, err := s.q.GetAliasByRawName(ctx, testName); err == nil {
		return ptrs(a)
	}
	if a, err := s.q.GetAnalyteByName(ctx, testName); err == nil {
		return ptrs(a)
	}
	return nil, nil
}
