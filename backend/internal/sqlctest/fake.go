// Package sqlctest provides a fake sqlc.Querier for tests. It embeds the
// interface, so only the methods a test needs are set; any unset method panics
// if called (a clear signal the test exercised an unexpected query).
package sqlctest

import (
	"context"

	"github.com/google/uuid"
	"github.com/winkler/lab-tracker/backend/internal/db/sqlc"
)

type FakeQuerier struct {
	sqlc.Querier // embedded; unset methods panic on call

	GetProfileFn                     func(context.Context, uuid.UUID) (sqlc.Profile, error)
	GetAnalyteFn                     func(context.Context, uuid.UUID) (sqlc.Analyte, error)
	ListProfilesFn                   func(context.Context) ([]sqlc.Profile, error)
	ListAnalytesFn                   func(context.Context) ([]sqlc.Analyte, error)
	ListAnalytesWithDataForProfileFn func(context.Context, uuid.UUID) ([]sqlc.Analyte, error)
	ListResultsForProfileAnalyteFn   func(context.Context, sqlc.ListResultsForProfileAnalyteParams) ([]sqlc.ListResultsForProfileAnalyteRow, error)
	ListLatestResultsForProfileFn    func(context.Context, uuid.UUID) ([]sqlc.ListLatestResultsForProfileRow, error)
	ResultStatsForProfileAnalyteFn   func(context.Context, sqlc.ResultStatsForProfileAnalyteParams) (sqlc.ResultStatsForProfileAnalyteRow, error)
	GetAnalysisFn                    func(context.Context, sqlc.GetAnalysisParams) (sqlc.AnalyteAnalysis, error)
	UpsertAnalysisFn                 func(context.Context, sqlc.UpsertAnalysisParams) error
}

func (f *FakeQuerier) GetProfile(ctx context.Context, id uuid.UUID) (sqlc.Profile, error) {
	return f.GetProfileFn(ctx, id)
}

func (f *FakeQuerier) GetAnalyte(ctx context.Context, id uuid.UUID) (sqlc.Analyte, error) {
	return f.GetAnalyteFn(ctx, id)
}

func (f *FakeQuerier) ListProfiles(ctx context.Context) ([]sqlc.Profile, error) {
	return f.ListProfilesFn(ctx)
}

func (f *FakeQuerier) ListAnalytes(ctx context.Context) ([]sqlc.Analyte, error) {
	return f.ListAnalytesFn(ctx)
}

func (f *FakeQuerier) ListAnalytesWithDataForProfile(ctx context.Context, profileID uuid.UUID) ([]sqlc.Analyte, error) {
	return f.ListAnalytesWithDataForProfileFn(ctx, profileID)
}

func (f *FakeQuerier) ListResultsForProfileAnalyte(ctx context.Context, arg sqlc.ListResultsForProfileAnalyteParams) ([]sqlc.ListResultsForProfileAnalyteRow, error) {
	return f.ListResultsForProfileAnalyteFn(ctx, arg)
}

func (f *FakeQuerier) ListLatestResultsForProfile(ctx context.Context, profileID uuid.UUID) ([]sqlc.ListLatestResultsForProfileRow, error) {
	return f.ListLatestResultsForProfileFn(ctx, profileID)
}

func (f *FakeQuerier) ResultStatsForProfileAnalyte(ctx context.Context, arg sqlc.ResultStatsForProfileAnalyteParams) (sqlc.ResultStatsForProfileAnalyteRow, error) {
	return f.ResultStatsForProfileAnalyteFn(ctx, arg)
}

func (f *FakeQuerier) GetAnalysis(ctx context.Context, arg sqlc.GetAnalysisParams) (sqlc.AnalyteAnalysis, error) {
	return f.GetAnalysisFn(ctx, arg)
}

func (f *FakeQuerier) UpsertAnalysis(ctx context.Context, arg sqlc.UpsertAnalysisParams) error {
	return f.UpsertAnalysisFn(ctx, arg)
}
