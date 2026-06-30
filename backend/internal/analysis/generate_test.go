package analysis

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
	"github.com/Seklfreak/lab-tracker/backend/internal/llmtest"
	"github.com/Seklfreak/lab-tracker/backend/internal/sqlctest"
)

func TestGenerate(t *testing.T) {
	ex := llmtest.MockExtractor(t, "  ## What this measures\nLooks fine.  ")

	var upserted sqlc.UpsertAnalysisParams
	q := &sqlctest.FakeQuerier{
		GetProfileFn: func(context.Context, uuid.UUID) (sqlc.Profile, error) {
			return sqlc.Profile{Name: "X"}, nil
		},
		GetAnalyteFn: func(context.Context, uuid.UUID) (sqlc.Analyte, error) {
			return sqlc.Analyte{Name: "Glucose"}, nil
		},
		ListResultsForProfileAnalyteFn: func(context.Context, sqlc.ListResultsForProfileAnalyteParams) ([]sqlc.ListResultsForProfileAnalyteRow, error) {
			return []sqlc.ListResultsForProfileAnalyteRow{
				{AnalyteName: "Glucose", ValueNumeric: pgtype.Float8{Float64: 95, Valid: true}, ObservedDate: pgtype.Date{Time: time.Now(), Valid: true}},
				{AnalyteName: "Glucose", ValueNumeric: pgtype.Float8{Float64: 99, Valid: true}, ObservedDate: pgtype.Date{Time: time.Now(), Valid: true}},
			}, nil
		},
		ListLatestResultsForProfileFn: func(context.Context, uuid.UUID) ([]sqlc.ListLatestResultsForProfileRow, error) {
			return nil, nil
		},
		ListBodyMeasurementsFn: func(context.Context, uuid.UUID) ([]sqlc.BodyMeasurement, error) {
			return nil, nil
		},
		UpsertAnalysisFn: func(_ context.Context, p sqlc.UpsertAnalysisParams) error {
			upserted = p
			return nil
		},
	}

	content, count, err := Generate(context.Background(), q, ex, uuid.New(), uuid.New())
	if err != nil {
		t.Fatal(err)
	}
	if content != "## What this measures\nLooks fine." {
		t.Errorf("content not trimmed/returned: %q", content)
	}
	if count != 2 {
		t.Errorf("count = %d, want 2", count)
	}
	if upserted.Content != content || upserted.ResultCount != 2 {
		t.Errorf("stored params = %+v", upserted)
	}
}

func TestGenerateNoResults(t *testing.T) {
	ex := llmtest.MockExtractor(t, "should not be called")
	q := &sqlctest.FakeQuerier{
		GetProfileFn: func(context.Context, uuid.UUID) (sqlc.Profile, error) { return sqlc.Profile{}, nil },
		GetAnalyteFn: func(context.Context, uuid.UUID) (sqlc.Analyte, error) { return sqlc.Analyte{}, nil },
		ListResultsForProfileAnalyteFn: func(context.Context, sqlc.ListResultsForProfileAnalyteParams) ([]sqlc.ListResultsForProfileAnalyteRow, error) {
			return nil, nil
		},
	}
	if _, _, err := Generate(context.Background(), q, ex, uuid.New(), uuid.New()); !errors.Is(err, ErrNoResults) {
		t.Errorf("want ErrNoResults, got %v", err)
	}
}
