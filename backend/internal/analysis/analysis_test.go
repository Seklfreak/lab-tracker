package analysis

import (
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/winkler/lab-tracker/backend/internal/db/sqlc"
)

func ts(tm time.Time) pgtype.Timestamptz { return pgtype.Timestamptz{Time: tm, Valid: true} }

func TestIsStale(t *testing.T) {
	gen := time.Date(2026, 1, 10, 12, 0, 0, 0, time.UTC)
	stored := sqlc.AnalyteAnalysis{ResultCount: 2, GeneratedAt: ts(gen)}

	cases := []struct {
		name  string
		stats sqlc.ResultStatsForProfileAnalyteRow
		want  bool
	}{
		{"unchanged", sqlc.ResultStatsForProfileAnalyteRow{Count: 2, LastChanged: ts(gen.Add(-time.Hour))}, false},
		{"count grew (added)", sqlc.ResultStatsForProfileAnalyteRow{Count: 3, LastChanged: ts(gen.Add(-time.Hour))}, true},
		{"count shrank (deleted)", sqlc.ResultStatsForProfileAnalyteRow{Count: 1, LastChanged: ts(gen.Add(-time.Hour))}, true},
		{"edited after generation", sqlc.ResultStatsForProfileAnalyteRow{Count: 2, LastChanged: ts(gen.Add(time.Hour))}, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := IsStale(stored, c.stats); got != c.want {
				t.Errorf("IsStale = %v, want %v", got, c.want)
			}
		})
	}
}

func TestBuildAnalysisPrompt(t *testing.T) {
	a := sqlc.Analyte{
		Name:        "Glucose",
		DefaultUnit: pgtype.Text{String: "mg/dL", Valid: true},
		Category:    pgtype.Text{String: "Metabolic", Valid: true},
	}
	series := []sqlc.ListResultsForProfileAnalyteRow{{
		AnalyteName:   "Glucose",
		ValueNumeric:  pgtype.Float8{Float64: 95, Valid: true},
		Unit:          pgtype.Text{String: "mg/dL", Valid: true},
		ReferenceLow:  pgtype.Float8{Float64: 70, Valid: true},
		ReferenceHigh: pgtype.Float8{Float64: 99, Valid: true},
		ObservedDate:  pgtype.Date{Time: time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC), Valid: true},
	}}

	prompt := buildAnalysisPrompt(sqlc.Profile{Name: "X"}, a, series, nil)

	for _, want := range []string{
		"Glucose", "mg/dL", "95", "70-99", "2026-01-02",
		"## What this measures", "## Your trend",
	} {
		if !strings.Contains(prompt, want) {
			t.Errorf("prompt missing %q\n---\n%s", want, prompt)
		}
	}
}
