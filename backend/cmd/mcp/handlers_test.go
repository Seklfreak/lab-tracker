package main

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/winkler/lab-tracker/backend/internal/db/sqlc"
	"github.com/winkler/lab-tracker/backend/internal/sqlctest"
)

// connect wires a client to a server backed by the given fake Querier.
func connect(t *testing.T, q sqlc.Querier) *mcp.ClientSession {
	t.Helper()
	srv := newMCPServer(q, nil, slog.New(slog.NewTextHandler(io.Discard, nil)))
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
				{ID: uuid.New(), Name: "Sebastian"},
				{ID: uuid.New(), Name: "Wife"},
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
	if len(out.Profiles) != 2 || out.Profiles[0].Name != "Sebastian" {
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
