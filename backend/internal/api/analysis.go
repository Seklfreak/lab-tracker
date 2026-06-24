package api

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/winkler/lab-tracker/backend/internal/db/sqlc"
)

type AnalysisDTO struct {
	Content      string `json:"content"`
	GeneratedAt  string `json:"generatedAt"`
	BasedOnCount int    `json:"basedOnCount"`
	CurrentCount int    `json:"currentCount"`
	Stale        bool   `json:"stale"`
}

// getAnalysis returns the stored analysis for an analyte (or null), with a
// staleness flag when new results exist since it was generated.
func (s *Server) getAnalysis(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	analyteID, ok := parseUUID(chi.URLParam(r, "analyteId"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid analyteId")
		return
	}
	current, err := s.q.CountResultsForProfileAnalyte(r.Context(), sqlc.CountResultsForProfileAnalyteParams{
		ProfileID: p.ID, AnalyteID: analyteID,
	})
	if err != nil {
		s.log.Error("count results", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load analysis")
		return
	}
	stored, err := s.q.GetAnalysis(r.Context(), sqlc.GetAnalysisParams{ProfileID: p.ID, AnalyteID: analyteID})
	if errors.Is(err, pgx.ErrNoRows) {
		writeJSON(w, http.StatusOK, map[string]any{"analysis": nil})
		return
	}
	if err != nil {
		s.log.Error("get analysis", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load analysis")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"analysis": toAnalysisDTO(stored, int(current))})
}

// analyzeAnalyte generates (or regenerates) the analysis via the LLM and stores it.
func (s *Server) analyzeAnalyte(w http.ResponseWriter, r *http.Request) {
	p, ok := s.requireProfile(w, r)
	if !ok {
		return
	}
	analyteID, ok := parseUUID(chi.URLParam(r, "analyteId"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid analyteId")
		return
	}
	analyte, err := s.q.GetAnalyte(r.Context(), analyteID)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "analyte not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load analyte")
		return
	}
	series, err := s.q.ListResultsForProfileAnalyte(r.Context(), sqlc.ListResultsForProfileAnalyteParams{
		ProfileID: p.ID, AnalyteID: analyteID,
	})
	if err != nil {
		s.log.Error("list results for analysis", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load results")
		return
	}
	if len(series) == 0 {
		writeError(w, http.StatusBadRequest, "no results to analyze")
		return
	}
	others, err := s.q.ListLatestResultsForProfile(r.Context(), p.ID)
	if err != nil {
		s.log.Error("list latest for analysis", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to load context")
		return
	}

	prompt := buildAnalysisPrompt(p, analyte, series, others)
	content, err := s.extractor.Complete(r.Context(), prompt, 2000)
	if err != nil {
		s.log.Error("analyze", "err", err)
		writeError(w, http.StatusBadGateway, "analysis failed")
		return
	}
	content = strings.TrimSpace(content)

	if err := s.q.UpsertAnalysis(r.Context(), sqlc.UpsertAnalysisParams{
		ProfileID:   p.ID,
		AnalyteID:   analyteID,
		Content:     content,
		ResultCount: int32(len(series)),
	}); err != nil {
		s.log.Error("store analysis", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to store analysis")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"analysis": AnalysisDTO{
		Content:      content,
		GeneratedAt:  time.Now().UTC().Format(time.RFC3339),
		BasedOnCount: len(series),
		CurrentCount: len(series),
		Stale:        false,
	}})
}

func toAnalysisDTO(a sqlc.AnalyteAnalysis, current int) AnalysisDTO {
	gen := ""
	if a.GeneratedAt.Valid {
		gen = a.GeneratedAt.Time.UTC().Format(time.RFC3339)
	}
	return AnalysisDTO{
		Content:      a.Content,
		GeneratedAt:  gen,
		BasedOnCount: int(a.ResultCount),
		CurrentCount: current,
		Stale:        current > int(a.ResultCount),
	}
}

const analysisInstructions = `You are a knowledgeable lab assistant helping a layperson understand THEIR OWN lab results. This is educational, not medical advice or diagnosis.

%s

Write the analysis in markdown with these sections (use ## headings):
## What this measures
Plain-language explanation of what %s is and why it matters.
## Your trend
Describe how the values changed over time using the specific dates/values above; note whether they're within the reference range and any meaningful shifts.
## Related results
Only if relevant, connect this to other results listed (e.g. same panel, or clinically related markers). Omit this section entirely if nothing is relevant.
## Takeaways
A brief, non-alarmist summary; general lifestyle context only if clearly appropriate.

Keep it concise (~200-350 words), specific, and free of hedging filler. Do not diagnose or prescribe. End with one italic line reminding the reader to discuss results with their healthcare provider.`

func buildAnalysisPrompt(p sqlc.Profile, a sqlc.Analyte, series []sqlc.ListResultsForProfileAnalyteRow, others []sqlc.ListLatestResultsForProfileRow) string {
	var b strings.Builder
	fmt.Fprintf(&b, "Analyte: %s", a.Name)
	if a.DefaultUnit.Valid && a.DefaultUnit.String != "" {
		fmt.Fprintf(&b, " (%s)", a.DefaultUnit.String)
	}
	if a.Category.Valid && a.Category.String != "" {
		fmt.Fprintf(&b, ", category: %s", a.Category.String)
	}
	b.WriteString("\n")
	if age := ageYears(p.DateOfBirth); age > 0 {
		fmt.Fprintf(&b, "Patient age: %d years.\n", age)
	}

	b.WriteString("\nReadings over time (oldest first):\n")
	for _, r := range series {
		fmt.Fprintf(&b, "- %s: %s%s (reference %s)\n",
			dateStr(r.ObservedDate),
			resultValue(r.ValueText, r.ValueNumeric),
			unitSuffix(r.Unit),
			refRange(r.ReferenceLow, r.ReferenceHigh, r.ReferenceText))
		if r.Note.Valid && strings.TrimSpace(r.Note.String) != "" {
			fmt.Fprintf(&b, "  note: %s\n", strings.TrimSpace(r.Note.String))
		}
	}

	// Other latest results for correlation context (exclude this analyte).
	var ctx strings.Builder
	for _, o := range others {
		if o.AnalyteID == a.ID {
			continue
		}
		fmt.Fprintf(&ctx, "- %s: %s%s (%s)\n",
			o.AnalyteName,
			resultValue(o.ValueText, o.ValueNumeric),
			unitSuffix(o.Unit),
			dateStr(o.ObservedDate))
	}
	if ctx.Len() > 0 {
		b.WriteString("\nOther recent results for this person (latest per analyte), for context:\n")
		b.WriteString(ctx.String())
	}

	return fmt.Sprintf(analysisInstructions, b.String(), a.Name)
}

func resultValue(vt pgtype.Text, vn pgtype.Float8) string {
	if vt.Valid && strings.TrimSpace(vt.String) != "" {
		return strings.TrimSpace(vt.String)
	}
	if vn.Valid {
		return strconv.FormatFloat(vn.Float64, 'g', -1, 64)
	}
	return "?"
}

func unitSuffix(u pgtype.Text) string {
	if u.Valid && strings.TrimSpace(u.String) != "" {
		return " " + strings.TrimSpace(u.String)
	}
	return ""
}

func refRange(low, high pgtype.Float8, text pgtype.Text) string {
	if text.Valid && strings.TrimSpace(text.String) != "" {
		return strings.TrimSpace(text.String)
	}
	switch {
	case low.Valid && high.Valid:
		return fmt.Sprintf("%g-%g", low.Float64, high.Float64)
	case high.Valid:
		return fmt.Sprintf("<%g", high.Float64)
	case low.Valid:
		return fmt.Sprintf(">%g", low.Float64)
	default:
		return "n/a"
	}
}

func dateStr(d pgtype.Date) string {
	if !d.Valid {
		return "unknown date"
	}
	return d.Time.Format(dateLayout)
}

func ageYears(dob pgtype.Date) int {
	if !dob.Valid {
		return 0
	}
	now := time.Now()
	years := now.Year() - dob.Time.Year()
	if now.YearDay() < dob.Time.YearDay() {
		years--
	}
	return years
}
