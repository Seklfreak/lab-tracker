// Package analysis builds and stores the LLM analysis for an analyte's history.
// Shared by the HTTP API and the MCP server so the prompt + generation logic
// has a single source of truth.
package analysis

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
	"github.com/Seklfreak/lab-tracker/backend/internal/llm"
)

const dateLayout = "2006-01-02"

// ErrNoResults is returned by Generate when the analyte has no results yet.
var ErrNoResults = errors.New("no results to analyze")

// Generate runs the LLM analysis for a profile's analyte and stores it.
// Returns the markdown content and the number of results it was based on.
func Generate(ctx context.Context, q sqlc.Querier, ex *llm.Extractor, profileID, analyteID uuid.UUID) (string, int, error) {
	profile, err := q.GetProfile(ctx, profileID)
	if err != nil {
		return "", 0, err
	}
	analyte, err := q.GetAnalyte(ctx, analyteID)
	if err != nil {
		return "", 0, err
	}
	series, err := q.ListResultsForProfileAnalyte(ctx, sqlc.ListResultsForProfileAnalyteParams{
		ProfileID: profileID, AnalyteID: analyteID,
	})
	if err != nil {
		return "", 0, err
	}
	if len(series) == 0 {
		return "", 0, ErrNoResults
	}
	others, err := q.ListLatestResultsForProfile(ctx, profileID)
	if err != nil {
		return "", 0, err
	}

	content, err := ex.Complete(ctx, buildAnalysisPrompt(profile, analyte, series, others), 2000)
	if err != nil {
		return "", 0, err
	}
	content = strings.TrimSpace(content)

	if err := q.UpsertAnalysis(ctx, sqlc.UpsertAnalysisParams{
		ProfileID:   profileID,
		AnalyteID:   analyteID,
		Content:     content,
		ResultCount: int32(len(series)),
	}); err != nil {
		return "", 0, err
	}
	return content, len(series), nil
}

// GeneratePanel produces a one-shot, whole-panel summary across a profile's latest
// results (all analytes). Generated on demand; not stored server-side. Returns the
// markdown content and the number of analytes summarized.
func GeneratePanel(ctx context.Context, q sqlc.Querier, ex *llm.Extractor, profileID uuid.UUID) (string, int, error) {
	profile, err := q.GetProfile(ctx, profileID)
	if err != nil {
		return "", 0, err
	}
	latest, err := q.ListLatestResultsForProfile(ctx, profileID)
	if err != nil {
		return "", 0, err
	}
	if len(latest) == 0 {
		return "", 0, ErrNoResults
	}
	content, err := ex.Complete(ctx, buildPanelPrompt(profile, latest), 2000)
	if err != nil {
		return "", 0, err
	}
	return strings.TrimSpace(content), len(latest), nil
}

// IsStale reports whether a stored analysis is out of date: either the result
// count changed (add/delete) or a result was edited after it was generated.
func IsStale(stored sqlc.AnalyteAnalysis, stats sqlc.ResultStatsForProfileAnalyteRow) bool {
	if int(stats.Count) != int(stored.ResultCount) {
		return true
	}
	return stats.LastChanged.Valid && stored.GeneratedAt.Valid &&
		stats.LastChanged.Time.After(stored.GeneratedAt.Time)
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

const panelInstructions = `You are a knowledgeable lab assistant helping a layperson understand THEIR OWN latest lab panel. This is educational, not medical advice or diagnosis.

%s

Write a concise markdown summary with these sections (use ## headings):
## Overview
One or two sentences on the overall picture.
## Needs attention
Bullet the values outside their reference range (or otherwise notable), each with the value, its reference, and a brief plain-language note on what it may indicate. Omit this section entirely if everything is within range.
## Looking good
Briefly summarize the in-range / reassuring results (group them; don't list every single one).
## Suggested follow-ups
Optional and non-alarmist: what to keep an eye on or raise with a provider. Omit if nothing stands out.

Keep it concise (~200-350 words), specific to the values above, and free of hedging filler. Do not diagnose or prescribe. End with one italic line reminding the reader to discuss results with their healthcare provider.`

func buildPanelPrompt(p sqlc.Profile, latest []sqlc.ListLatestResultsForProfileRow) string {
	var b strings.Builder
	if age := ageYears(p.DateOfBirth); age > 0 {
		fmt.Fprintf(&b, "Patient age: %d years.\n", age)
	}
	b.WriteString("\nLatest result per analyte (value, reference range, date):\n")
	for _, r := range latest {
		fmt.Fprintf(&b, "- %s: %s%s (reference %s, %s)\n",
			r.AnalyteName,
			resultValue(r.ValueText, r.ValueNumeric),
			unitSuffix(r.Unit),
			refRange(r.ReferenceLow, r.ReferenceHigh, r.ReferenceText),
			dateStr(r.ObservedDate))
	}
	return fmt.Sprintf(panelInstructions, b.String())
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
