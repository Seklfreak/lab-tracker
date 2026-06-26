package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strconv"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/Seklfreak/lab-tracker/backend/internal/analysis"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
	"github.com/Seklfreak/lab-tracker/backend/internal/llm"
)

type deps struct {
	q         sqlc.Querier
	extractor *llm.Extractor
	log       *slog.Logger
}

func newMCPServer(q sqlc.Querier, extractor *llm.Extractor, log *slog.Logger) *mcp.Server {
	d := &deps{q: q, extractor: extractor, log: log}
	s := mcp.NewServer(&mcp.Implementation{Name: "lab-tracker", Version: "0.1.0"}, nil)

	mcp.AddTool(s, &mcp.Tool{
		Name:        "list_profiles",
		Description: "List all lab profiles (people). Returns their ids, names, and dates of birth. Start here to get a profileId for the other tools.",
	}, d.listProfiles)

	mcp.AddTool(s, &mcp.Tool{
		Name:        "list_latest_results",
		Description: "For a profile, list the most recent reading of every analyte (the dashboard view): value, unit, reference range, date, how many readings exist, and whether it's a favorite.",
	}, d.listLatestResults)

	mcp.AddTool(s, &mcp.Tool{
		Name:        "get_analyte_trend",
		Description: "All readings over time for one analyte in a profile, oldest first — use this to analyze a trend. Needs profileId and analyteId (from search_analytes or list_latest_results).",
	}, d.getAnalyteTrend)

	mcp.AddTool(s, &mcp.Tool{
		Name:        "search_analytes",
		Description: "Find analytes by name (case-insensitive substring) to resolve a name to an analyteId. Optionally scope to a profileId to only return analytes that have data for that profile.",
	}, d.searchAnalytes)

	mcp.AddTool(s, &mcp.Tool{
		Name:        "get_analysis",
		Description: "Get the stored AI analysis for a profile's analyte, if one exists, including when it was generated and whether it's stale (results changed since).",
	}, d.getAnalysis)

	mcp.AddTool(s, &mcp.Tool{
		Name:        "generate_analysis",
		Description: "Generate (and store) a fresh AI analysis of a profile's analyte trend. This calls an LLM and incurs a small API cost. Returns the markdown analysis.",
	}, d.generateAnalysis)

	return s
}

// ---- inputs / outputs ----

type emptyIn struct{}

type profileOut struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	DateOfBirth *string `json:"dateOfBirth,omitempty"`
}

type listProfilesOut struct {
	Profiles []profileOut `json:"profiles"`
}

type profileIn struct {
	ProfileID string `json:"profileId" jsonschema:"the profile's UUID (from list_profiles)"`
}

type analyteRefIn struct {
	ProfileID string `json:"profileId" jsonschema:"the profile's UUID"`
	AnalyteID string `json:"analyteId" jsonschema:"the analyte's UUID"`
}

type resultOut struct {
	AnalyteID string  `json:"analyteId,omitempty"`
	Analyte   string  `json:"analyte,omitempty"`
	Value     string  `json:"value"`
	Unit      *string `json:"unit,omitempty"`
	Reference *string `json:"reference,omitempty"`
	Date      *string `json:"date,omitempty"`
	Count     *int    `json:"count,omitempty"`
	Favorite  *bool   `json:"favorite,omitempty"`
}

type listLatestOut struct {
	Results []resultOut `json:"results"`
}

type trendOut struct {
	Analyte string      `json:"analyte"`
	Unit    *string     `json:"unit,omitempty"`
	Results []resultOut `json:"results"`
}

type searchIn struct {
	ProfileID string `json:"profileId,omitempty" jsonschema:"optional: only analytes with data for this profile"`
	Query     string `json:"query" jsonschema:"case-insensitive substring to match against analyte names"`
}

type analyteOut struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Category  *string  `json:"category,omitempty"`
	Specimens []string `json:"specimens,omitempty"`
}

type searchOut struct {
	Analytes []analyteOut `json:"analytes"`
}

type analysisOut struct {
	Found        bool   `json:"found"`
	Content      string `json:"content,omitempty"`
	GeneratedAt  string `json:"generatedAt,omitempty"`
	Stale        bool   `json:"stale,omitempty"`
	BasedOnCount int    `json:"basedOnCount,omitempty"`
}

// ---- handlers ----

// requireProfileAccess enforces the caller's user scope: when a user identity is
// present on the request (Cloudflare Access), the profile must be owned by or
// shared with that user. A no-op when unscoped (dev / no identity).
func (d *deps) requireProfileAccess(ctx context.Context, pid uuid.UUID) error {
	uid := userIDFromContext(ctx)
	if uid == nil {
		return nil
	}
	if _, err := d.q.GetProfileForUser(ctx, sqlc.GetProfileForUserParams{ID: pid, UserID: uid}); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return fmt.Errorf("profile not found")
		}
		return err
	}
	return nil
}

func (d *deps) listProfiles(ctx context.Context, _ *mcp.CallToolRequest, _ emptyIn) (*mcp.CallToolResult, listProfilesOut, error) {
	var rows []sqlc.Profile
	var err error
	if uid := userIDFromContext(ctx); uid != nil {
		rows, err = d.q.ListProfilesForUser(ctx, uid)
	} else {
		rows, err = d.q.ListProfiles(ctx)
	}
	if err != nil {
		return nil, listProfilesOut{}, err
	}
	out := listProfilesOut{Profiles: make([]profileOut, 0, len(rows))}
	for _, p := range rows {
		out.Profiles = append(out.Profiles, profileOut{
			ID: p.ID.String(), Name: p.Name, DateOfBirth: dateToPtr(p.DateOfBirth),
		})
	}
	return nil, out, nil
}

func (d *deps) listLatestResults(ctx context.Context, _ *mcp.CallToolRequest, in profileIn) (*mcp.CallToolResult, listLatestOut, error) {
	pid, err := uuid.Parse(strings.TrimSpace(in.ProfileID))
	if err != nil {
		return nil, listLatestOut{}, fmt.Errorf("invalid profileId: %w", err)
	}
	if err := d.requireProfileAccess(ctx, pid); err != nil {
		return nil, listLatestOut{}, err
	}
	rows, err := d.q.ListLatestResultsForProfile(ctx, pid)
	if err != nil {
		return nil, listLatestOut{}, err
	}
	out := listLatestOut{Results: make([]resultOut, 0, len(rows))}
	for _, r := range rows {
		count := int(r.ResultCount)
		fav := r.IsFavorite
		out.Results = append(out.Results, resultOut{
			AnalyteID: r.AnalyteID.String(),
			Analyte:   r.AnalyteName,
			Value:     valueStr(r.ValueText, r.ValueNumeric),
			Unit:      textToPtr(r.Unit),
			Reference: refStr(r.ReferenceLow, r.ReferenceHigh, r.ReferenceText),
			Date:      dateToPtr(r.ObservedDate),
			Count:     &count,
			Favorite:  &fav,
		})
	}
	return nil, out, nil
}

func (d *deps) getAnalyteTrend(ctx context.Context, _ *mcp.CallToolRequest, in analyteRefIn) (*mcp.CallToolResult, trendOut, error) {
	pid, err := uuid.Parse(strings.TrimSpace(in.ProfileID))
	if err != nil {
		return nil, trendOut{}, fmt.Errorf("invalid profileId: %w", err)
	}
	aid, err := uuid.Parse(strings.TrimSpace(in.AnalyteID))
	if err != nil {
		return nil, trendOut{}, fmt.Errorf("invalid analyteId: %w", err)
	}
	if err := d.requireProfileAccess(ctx, pid); err != nil {
		return nil, trendOut{}, err
	}
	rows, err := d.q.ListResultsForProfileAnalyte(ctx, sqlc.ListResultsForProfileAnalyteParams{ProfileID: pid, AnalyteID: aid})
	if err != nil {
		return nil, trendOut{}, err
	}
	out := trendOut{Results: make([]resultOut, 0, len(rows))}
	for _, r := range rows {
		if out.Analyte == "" {
			out.Analyte = r.AnalyteName
		}
		if out.Unit == nil {
			out.Unit = textToPtr(r.Unit)
		}
		out.Results = append(out.Results, resultOut{
			Value:     valueStr(r.ValueText, r.ValueNumeric),
			Unit:      textToPtr(r.Unit),
			Reference: refStr(r.ReferenceLow, r.ReferenceHigh, r.ReferenceText),
			Date:      dateToPtr(r.ObservedDate),
		})
	}
	return nil, out, nil
}

func (d *deps) searchAnalytes(ctx context.Context, _ *mcp.CallToolRequest, in searchIn) (*mcp.CallToolResult, searchOut, error) {
	var rows []sqlc.Analyte
	var err error
	if strings.TrimSpace(in.ProfileID) != "" {
		pid, perr := uuid.Parse(strings.TrimSpace(in.ProfileID))
		if perr != nil {
			return nil, searchOut{}, fmt.Errorf("invalid profileId: %w", perr)
		}
		if aerr := d.requireProfileAccess(ctx, pid); aerr != nil {
			return nil, searchOut{}, aerr
		}
		rows, err = d.q.ListAnalytesWithDataForProfile(ctx, pid)
	} else {
		rows, err = d.q.ListAnalytes(ctx)
	}
	if err != nil {
		return nil, searchOut{}, err
	}
	q := strings.ToLower(strings.TrimSpace(in.Query))
	out := searchOut{Analytes: make([]analyteOut, 0)}
	for _, a := range rows {
		if q != "" && !strings.Contains(strings.ToLower(a.Name), q) {
			continue
		}
		out.Analytes = append(out.Analytes, analyteOut{
			ID: a.ID.String(), Name: a.Name, Category: textToPtr(a.Category), Specimens: a.Specimens,
		})
	}
	return nil, out, nil
}

func (d *deps) getAnalysis(ctx context.Context, _ *mcp.CallToolRequest, in analyteRefIn) (*mcp.CallToolResult, analysisOut, error) {
	pid, err := uuid.Parse(strings.TrimSpace(in.ProfileID))
	if err != nil {
		return nil, analysisOut{}, fmt.Errorf("invalid profileId: %w", err)
	}
	aid, err := uuid.Parse(strings.TrimSpace(in.AnalyteID))
	if err != nil {
		return nil, analysisOut{}, fmt.Errorf("invalid analyteId: %w", err)
	}
	if err := d.requireProfileAccess(ctx, pid); err != nil {
		return nil, analysisOut{}, err
	}
	stats, err := d.q.ResultStatsForProfileAnalyte(ctx, sqlc.ResultStatsForProfileAnalyteParams{ProfileID: pid, AnalyteID: aid})
	if err != nil {
		return nil, analysisOut{}, err
	}
	stored, err := d.q.GetAnalysis(ctx, sqlc.GetAnalysisParams{ProfileID: pid, AnalyteID: aid})
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, analysisOut{Found: false}, nil
	}
	if err != nil {
		return nil, analysisOut{}, err
	}
	gen := ""
	if stored.GeneratedAt.Valid {
		gen = stored.GeneratedAt.Time.UTC().Format("2006-01-02T15:04:05Z07:00")
	}
	return nil, analysisOut{
		Found:        true,
		Content:      stored.Content,
		GeneratedAt:  gen,
		Stale:        analysis.IsStale(stored, stats),
		BasedOnCount: int(stored.ResultCount),
	}, nil
}

func (d *deps) generateAnalysis(ctx context.Context, _ *mcp.CallToolRequest, in analyteRefIn) (*mcp.CallToolResult, analysisOut, error) {
	pid, err := uuid.Parse(strings.TrimSpace(in.ProfileID))
	if err != nil {
		return nil, analysisOut{}, fmt.Errorf("invalid profileId: %w", err)
	}
	aid, err := uuid.Parse(strings.TrimSpace(in.AnalyteID))
	if err != nil {
		return nil, analysisOut{}, fmt.Errorf("invalid analyteId: %w", err)
	}
	if err := d.requireProfileAccess(ctx, pid); err != nil {
		return nil, analysisOut{}, err
	}
	content, count, err := analysis.Generate(ctx, d.q, d.extractor, pid, aid)
	switch {
	case errors.Is(err, analysis.ErrNoResults):
		return nil, analysisOut{}, fmt.Errorf("no results to analyze for this analyte")
	case errors.Is(err, pgx.ErrNoRows):
		return nil, analysisOut{}, fmt.Errorf("profile or analyte not found")
	case err != nil:
		return nil, analysisOut{}, err
	}
	return nil, analysisOut{Found: true, Content: content, BasedOnCount: count}, nil
}

// ---- helpers ----

func valueStr(vt pgtype.Text, vn pgtype.Float8) string {
	if vt.Valid && strings.TrimSpace(vt.String) != "" {
		return strings.TrimSpace(vt.String)
	}
	if vn.Valid {
		return strconv.FormatFloat(vn.Float64, 'g', -1, 64)
	}
	return ""
}

func refStr(low, high pgtype.Float8, text pgtype.Text) *string {
	if text.Valid && strings.TrimSpace(text.String) != "" {
		s := strings.TrimSpace(text.String)
		return &s
	}
	var s string
	switch {
	case low.Valid && high.Valid:
		s = fmt.Sprintf("%g-%g", low.Float64, high.Float64)
	case high.Valid:
		s = fmt.Sprintf("<%g", high.Float64)
	case low.Valid:
		s = fmt.Sprintf(">%g", low.Float64)
	default:
		return nil
	}
	return &s
}

func textToPtr(t pgtype.Text) *string {
	if !t.Valid || strings.TrimSpace(t.String) == "" {
		return nil
	}
	s := t.String
	return &s
}

func dateToPtr(d pgtype.Date) *string {
	if !d.Valid {
		return nil
	}
	s := d.Time.Format("2006-01-02")
	return &s
}
