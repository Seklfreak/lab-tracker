package main

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
	"github.com/Seklfreak/lab-tracker/backend/internal/llm"
	"github.com/Seklfreak/lab-tracker/backend/internal/llmtest"
	"github.com/Seklfreak/lab-tracker/backend/internal/sqlctest"
)

// connect wires a client to a server backed by the given fake Querier.
func connect(t *testing.T, q sqlc.Querier) *mcp.ClientSession {
	return connectLLM(t, q, nil)
}

// connectLLM is like connect but with an injected extractor (for generate_analysis).
func connectLLM(t *testing.T, q sqlc.Querier, ex *llm.Extractor) *mcp.ClientSession {
	t.Helper()
	srv := newMCPServer(q, ex, slog.New(slog.NewTextHandler(io.Discard, nil)), nil)
	ct, st := mcp.NewInMemoryTransports()
	ctx := context.Background()
	ss, err := srv.Connect(ctx, st, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ss.Close() })
	cs, err := mcp.NewClient(&mcp.Implementation{Name: "t", Version: "0"}, nil).Connect(ctx, ct, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { cs.Close() })
	return cs
}

func reJSON(t *testing.T, v, dst any) {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(b, dst); err != nil {
		t.Fatal(err)
	}
}

func TestListProfilesHandler(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		ListProfilesFn: func(context.Context) ([]sqlc.Profile, error) {
			return []sqlc.Profile{
				{ID: uuid.New(), Name: "Alice"},
				{ID: uuid.New(), Name: "Bob"},
			}, nil
		},
	}
	res, err := connect(t, q).CallTool(context.Background(), &mcp.CallToolParams{
		Name: "list_profiles", Arguments: map[string]any{},
	})
	if err != nil {
		t.Fatal(err)
	}
	if res.IsError {
		t.Fatalf("tool error: %v", res.Content)
	}
	var out listProfilesOut
	reJSON(t, res.StructuredContent, &out)
	if len(out.Profiles) != 2 || out.Profiles[0].Name != "Alice" {
		t.Errorf("profiles = %+v", out.Profiles)
	}
}

func TestGetAnalyteTrendHandler(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		ListResultsForProfileAnalyteFn: func(context.Context, sqlc.ListResultsForProfileAnalyteParams) ([]sqlc.ListResultsForProfileAnalyteRow, error) {
			return []sqlc.ListResultsForProfileAnalyteRow{
				{
					AnalyteName:   "Glucose",
					ValueNumeric:  pgtype.Float8{Float64: 95, Valid: true},
					Unit:          pgtype.Text{String: "mg/dL", Valid: true},
					ReferenceLow:  pgtype.Float8{Float64: 70, Valid: true},
					ReferenceHigh: pgtype.Float8{Float64: 99, Valid: true},
					ObservedDate:  pgtype.Date{Time: time.Date(2025, 6, 1, 0, 0, 0, 0, time.UTC), Valid: true},
				},
				{
					AnalyteName:  "Glucose",
					ValueText:    pgtype.Text{String: "<5", Valid: true},
					ObservedDate: pgtype.Date{Time: time.Date(2025, 7, 1, 0, 0, 0, 0, time.UTC), Valid: true},
				},
			}, nil
		},
	}
	res, err := connect(t, q).CallTool(context.Background(), &mcp.CallToolParams{
		Name:      "get_analyte_trend",
		Arguments: map[string]any{"profileId": uuid.New().String(), "analyteId": uuid.New().String()},
	})
	if err != nil {
		t.Fatal(err)
	}
	if res.IsError {
		t.Fatalf("tool error: %v", res.Content)
	}
	var out trendOut
	reJSON(t, res.StructuredContent, &out)
	if out.Analyte != "Glucose" || len(out.Results) != 2 {
		t.Fatalf("trend = %+v", out)
	}
	if out.Results[0].Value != "95" || out.Results[1].Value != "<5" {
		t.Errorf("values = %+v", out.Results)
	}
}

func TestGetAnalyteTrendBadID(t *testing.T) {
	// Invalid UUID should fail before any query (fake has no Fn set).
	res, err := connect(t, &sqlctest.FakeQuerier{}).CallTool(context.Background(), &mcp.CallToolParams{
		Name:      "get_analyte_trend",
		Arguments: map[string]any{"profileId": "not-a-uuid", "analyteId": "x"},
	})
	if err == nil && (res == nil || !res.IsError) {
		t.Error("expected an error for an invalid profileId")
	}
}

func TestListLatestResultsHandler(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		ListLatestResultsForProfileFn: func(context.Context, uuid.UUID) ([]sqlc.ListLatestResultsForProfileRow, error) {
			return []sqlc.ListLatestResultsForProfileRow{{
				AnalyteID:    uuid.New(),
				AnalyteName:  "Glucose",
				ValueNumeric: pgtype.Float8{Float64: 95, Valid: true},
				Unit:         pgtype.Text{String: "mg/dL", Valid: true},
				ObservedDate: pgtype.Date{Time: time.Now(), Valid: true},
				ResultCount:  3,
				IsFavorite:   true,
			}}, nil
		},
	}
	res, err := connect(t, q).CallTool(context.Background(), &mcp.CallToolParams{
		Name: "list_latest_results", Arguments: map[string]any{"profileId": uuid.New().String()},
	})
	if err != nil {
		t.Fatal(err)
	}
	if res.IsError {
		t.Fatalf("tool error: %v", res.Content)
	}
	var out listLatestOut
	reJSON(t, res.StructuredContent, &out)
	if len(out.Results) != 1 || out.Results[0].Analyte != "Glucose" {
		t.Fatalf("results = %+v", out.Results)
	}
	r := out.Results[0]
	if r.Value != "95" || r.Count == nil || *r.Count != 3 || r.Favorite == nil || !*r.Favorite {
		t.Errorf("mapping = %+v", r)
	}
}

func TestSearchAnalytesHandler(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		ListAnalytesFn: func(context.Context) ([]sqlc.Analyte, error) {
			return []sqlc.Analyte{
				{ID: uuid.New(), Name: "Glucose"},
				{ID: uuid.New(), Name: "Sodium"},
				{ID: uuid.New(), Name: "Urine Glucose"},
			}, nil
		},
	}
	res, err := connect(t, q).CallTool(context.Background(), &mcp.CallToolParams{
		Name: "search_analytes", Arguments: map[string]any{"query": "glucose"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if res.IsError {
		t.Fatalf("tool error: %v", res.Content)
	}
	var out searchOut
	reJSON(t, res.StructuredContent, &out)
	if len(out.Analytes) != 2 {
		t.Fatalf("want 2 glucose matches, got %+v", out.Analytes)
	}
}

func TestGetAnalysisHandler(t *testing.T) {
	gen := time.Date(2026, 1, 10, 0, 0, 0, 0, time.UTC)
	q := &sqlctest.FakeQuerier{
		ResultStatsForProfileAnalyteFn: func(context.Context, sqlc.ResultStatsForProfileAnalyteParams) (sqlc.ResultStatsForProfileAnalyteRow, error) {
			return sqlc.ResultStatsForProfileAnalyteRow{Count: 2, LastChanged: pgtype.Timestamptz{Time: gen.Add(-time.Hour), Valid: true}}, nil
		},
		GetAnalysisFn: func(context.Context, sqlc.GetAnalysisParams) (sqlc.AnalyteAnalysis, error) {
			return sqlc.AnalyteAnalysis{Content: "stored analysis", ResultCount: 2, GeneratedAt: pgtype.Timestamptz{Time: gen, Valid: true}}, nil
		},
	}
	args := map[string]any{"profileId": uuid.New().String(), "analyteId": uuid.New().String()}
	res, err := connect(t, q).CallTool(context.Background(), &mcp.CallToolParams{Name: "get_analysis", Arguments: args})
	if err != nil {
		t.Fatal(err)
	}
	var out analysisOut
	reJSON(t, res.StructuredContent, &out)
	if !out.Found || out.Content != "stored analysis" || out.Stale {
		t.Errorf("analysis = %+v", out)
	}
}

func TestGetAnalysisHandlerNone(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		ResultStatsForProfileAnalyteFn: func(context.Context, sqlc.ResultStatsForProfileAnalyteParams) (sqlc.ResultStatsForProfileAnalyteRow, error) {
			return sqlc.ResultStatsForProfileAnalyteRow{Count: 0}, nil
		},
		GetAnalysisFn: func(context.Context, sqlc.GetAnalysisParams) (sqlc.AnalyteAnalysis, error) {
			return sqlc.AnalyteAnalysis{}, pgx.ErrNoRows
		},
	}
	args := map[string]any{"profileId": uuid.New().String(), "analyteId": uuid.New().String()}
	res, err := connect(t, q).CallTool(context.Background(), &mcp.CallToolParams{Name: "get_analysis", Arguments: args})
	if err != nil {
		t.Fatal(err)
	}
	var out analysisOut
	reJSON(t, res.StructuredContent, &out)
	if out.Found {
		t.Errorf("expected Found=false when no analysis stored, got %+v", out)
	}
}

func TestGenerateAnalysisHandler(t *testing.T) {
	ex := llmtest.MockExtractor(t, "GENERATED ANALYSIS")
	q := &sqlctest.FakeQuerier{
		GetProfileFn: func(context.Context, uuid.UUID) (sqlc.Profile, error) { return sqlc.Profile{Name: "X"}, nil },
		GetAnalyteFn: func(context.Context, uuid.UUID) (sqlc.Analyte, error) { return sqlc.Analyte{Name: "Glucose"}, nil },
		ListResultsForProfileAnalyteFn: func(context.Context, sqlc.ListResultsForProfileAnalyteParams) ([]sqlc.ListResultsForProfileAnalyteRow, error) {
			return []sqlc.ListResultsForProfileAnalyteRow{
				{AnalyteName: "Glucose", ValueNumeric: pgtype.Float8{Float64: 95, Valid: true}, ObservedDate: pgtype.Date{Time: time.Now(), Valid: true}},
			}, nil
		},
		ListLatestResultsForProfileFn: func(context.Context, uuid.UUID) ([]sqlc.ListLatestResultsForProfileRow, error) { return nil, nil },
		UpsertAnalysisFn:              func(context.Context, sqlc.UpsertAnalysisParams) error { return nil },
	}
	args := map[string]any{"profileId": uuid.New().String(), "analyteId": uuid.New().String()}
	res, err := connectLLM(t, q, ex).CallTool(context.Background(), &mcp.CallToolParams{Name: "generate_analysis", Arguments: args})
	if err != nil {
		t.Fatal(err)
	}
	if res.IsError {
		t.Fatalf("tool error: %v", res.Content)
	}
	var out analysisOut
	reJSON(t, res.StructuredContent, &out)
	if out.Content != "GENERATED ANALYSIS" || out.BasedOnCount != 1 {
		t.Errorf("generate output = %+v", out)
	}
}
