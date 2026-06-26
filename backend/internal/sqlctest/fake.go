// Package sqlctest provides a fake sqlc.Querier for tests. It embeds the
// interface, so only the methods a test needs are set; any unset method panics
// if called (a clear signal the test exercised an unexpected query).
package sqlctest

import (
	"context"

	"github.com/google/uuid"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
)

type FakeQuerier struct {
	sqlc.Querier // embedded; unset methods panic on call

	GetProfileFn                     func(context.Context, uuid.UUID) (sqlc.Profile, error)
	GetProfileForUserFn              func(context.Context, sqlc.GetProfileForUserParams) (sqlc.Profile, error)
	GetResultFn                      func(context.Context, uuid.UUID) (sqlc.LabResult, error)
	GetAnalyteFn                     func(context.Context, uuid.UUID) (sqlc.Analyte, error)
	ListProfilesFn                   func(context.Context) ([]sqlc.Profile, error)
	ListProfilesForUserFn            func(context.Context, *uuid.UUID) ([]sqlc.Profile, error)
	ListAnalytesFn                   func(context.Context) ([]sqlc.Analyte, error)
	ListAnalytesWithDataForProfileFn func(context.Context, uuid.UUID) ([]sqlc.Analyte, error)
	ListResultsForProfileAnalyteFn   func(context.Context, sqlc.ListResultsForProfileAnalyteParams) ([]sqlc.ListResultsForProfileAnalyteRow, error)
	ListLatestResultsForProfileFn    func(context.Context, uuid.UUID) ([]sqlc.ListLatestResultsForProfileRow, error)
	ResultStatsForProfileAnalyteFn   func(context.Context, sqlc.ResultStatsForProfileAnalyteParams) (sqlc.ResultStatsForProfileAnalyteRow, error)
	GetAnalysisFn                    func(context.Context, sqlc.GetAnalysisParams) (sqlc.AnalyteAnalysis, error)
	UpsertAnalysisFn                 func(context.Context, sqlc.UpsertAnalysisParams) error
	CreateProfileFn                  func(context.Context, sqlc.CreateProfileParams) (sqlc.Profile, error)
	ListResultsForProfileFn          func(context.Context, uuid.UUID) ([]sqlc.ListResultsForProfileRow, error)
	UpdateResultFn                   func(context.Context, sqlc.UpdateResultParams) error
	AddFavoriteFn                    func(context.Context, sqlc.AddFavoriteParams) error
	RemoveFavoriteFn                 func(context.Context, sqlc.RemoveFavoriteParams) error
	UpsertUserFn                     func(context.Context, sqlc.UpsertUserParams) (sqlc.User, error)
	GetUserFn                        func(context.Context, uuid.UUID) (sqlc.User, error)
	GetUserByEmailFn                 func(context.Context, string) (sqlc.User, error)
	ListProfileMembersFn             func(context.Context, uuid.UUID) ([]sqlc.ListProfileMembersRow, error)
	AddProfileMemberFn               func(context.Context, sqlc.AddProfileMemberParams) error
	RemoveProfileMemberFn            func(context.Context, sqlc.RemoveProfileMemberParams) error
	DeleteProfileFn                  func(context.Context, uuid.UUID) error
	DeleteResultFn                   func(context.Context, uuid.UUID) error
}

func (f *FakeQuerier) DeleteProfile(ctx context.Context, id uuid.UUID) error {
	return f.DeleteProfileFn(ctx, id)
}

func (f *FakeQuerier) DeleteResult(ctx context.Context, id uuid.UUID) error {
	return f.DeleteResultFn(ctx, id)
}

func (f *FakeQuerier) GetProfileForUser(ctx context.Context, arg sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
	return f.GetProfileForUserFn(ctx, arg)
}

func (f *FakeQuerier) ListProfilesForUser(ctx context.Context, userID *uuid.UUID) ([]sqlc.Profile, error) {
	return f.ListProfilesForUserFn(ctx, userID)
}

func (f *FakeQuerier) GetResult(ctx context.Context, id uuid.UUID) (sqlc.LabResult, error) {
	return f.GetResultFn(ctx, id)
}

func (f *FakeQuerier) UpsertUser(ctx context.Context, arg sqlc.UpsertUserParams) (sqlc.User, error) {
	return f.UpsertUserFn(ctx, arg)
}

func (f *FakeQuerier) GetUser(ctx context.Context, id uuid.UUID) (sqlc.User, error) {
	return f.GetUserFn(ctx, id)
}

func (f *FakeQuerier) GetUserByEmail(ctx context.Context, lower string) (sqlc.User, error) {
	return f.GetUserByEmailFn(ctx, lower)
}

func (f *FakeQuerier) ListProfileMembers(ctx context.Context, profileID uuid.UUID) ([]sqlc.ListProfileMembersRow, error) {
	return f.ListProfileMembersFn(ctx, profileID)
}

func (f *FakeQuerier) AddProfileMember(ctx context.Context, arg sqlc.AddProfileMemberParams) error {
	return f.AddProfileMemberFn(ctx, arg)
}

func (f *FakeQuerier) RemoveProfileMember(ctx context.Context, arg sqlc.RemoveProfileMemberParams) error {
	return f.RemoveProfileMemberFn(ctx, arg)
}

func (f *FakeQuerier) CreateProfile(ctx context.Context, arg sqlc.CreateProfileParams) (sqlc.Profile, error) {
	return f.CreateProfileFn(ctx, arg)
}

func (f *FakeQuerier) ListResultsForProfile(ctx context.Context, profileID uuid.UUID) ([]sqlc.ListResultsForProfileRow, error) {
	return f.ListResultsForProfileFn(ctx, profileID)
}

func (f *FakeQuerier) UpdateResult(ctx context.Context, arg sqlc.UpdateResultParams) error {
	return f.UpdateResultFn(ctx, arg)
}

func (f *FakeQuerier) AddFavorite(ctx context.Context, arg sqlc.AddFavoriteParams) error {
	return f.AddFavoriteFn(ctx, arg)
}

func (f *FakeQuerier) RemoveFavorite(ctx context.Context, arg sqlc.RemoveFavoriteParams) error {
	return f.RemoveFavoriteFn(ctx, arg)
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
