package api

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
	"github.com/Seklfreak/lab-tracker/backend/internal/llm"
	"github.com/Seklfreak/lab-tracker/backend/internal/llmtest"
	"github.com/Seklfreak/lab-tracker/backend/internal/sqlctest"
)

// router builds the real chi router over a fake Querier (auth disabled: verifier nil).
func router(q sqlc.Querier, ex *llm.Extractor) http.Handler {
	s := &Server{q: q, extractor: ex, log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	return s.Router(nil)
}

func do(t *testing.T, h http.Handler, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, path, r)
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestListProfiles(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		ListProfilesForUserFn: func(context.Context, *uuid.UUID) ([]sqlc.Profile, error) {
			return []sqlc.Profile{{ID: uuid.New(), Name: "Alice"}}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodGet, "/api/profiles", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var got []ProfileDTO
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Name != "Alice" {
		t.Errorf("body = %+v", got)
	}
}

func TestAPIResponsesAreNoStore(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		ListProfilesForUserFn: func(context.Context, *uuid.UUID) ([]sqlc.Profile, error) {
			return nil, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodGet, "/api/profiles", "")
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control = %q, want no-store", got)
	}
}

func TestCreateProfile(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		CreateProfileFn: func(_ context.Context, arg sqlc.CreateProfileParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: uuid.New(), Name: arg.Name}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodPost, "/api/profiles", `{"name":"Kid"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d", rec.Code)
	}
	var got ProfileDTO
	_ = json.Unmarshal(rec.Body.Bytes(), &got)
	if got.Name != "Kid" {
		t.Errorf("name = %q", got.Name)
	}
}

func TestCreateProfileMissingName(t *testing.T) {
	rec := do(t, router(&sqlctest.FakeQuerier{}, nil), http.MethodPost, "/api/profiles", `{}`)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("want 400 for missing name, got %d", rec.Code)
	}
}

func TestListLatestResults(t *testing.T) {
	pid := uuid.New()
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(_ context.Context, arg sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: arg.ID, Name: "Test"}, nil
		},
		// Default /results path is the dashboard "latest per analyte" view.
		ListLatestResultsForProfileFn: func(context.Context, uuid.UUID) ([]sqlc.ListLatestResultsForProfileRow, error) {
			return []sqlc.ListLatestResultsForProfileRow{{
				AnalyteID:    uuid.New(),
				AnalyteName:  "Glucose",
				ValueNumeric: pgtype.Float8{Float64: 95, Valid: true},
				ObservedDate: pgtype.Date{Time: time.Now(), Valid: true},
				ResultCount:  2,
			}}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodGet, "/api/profiles/"+pid.String()+"/results", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var got []ResultDTO
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].AnalyteName != "Glucose" {
		t.Errorf("results = %+v", got)
	}
}

func TestListAllResults(t *testing.T) {
	pid := uuid.New()
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(_ context.Context, arg sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: arg.ID}, nil
		},
		ListResultsForProfileFn: func(context.Context, uuid.UUID) ([]sqlc.ListResultsForProfileRow, error) {
			return []sqlc.ListResultsForProfileRow{
				{AnalyteName: "Glucose", ValueNumeric: pgtype.Float8{Float64: 95, Valid: true}, ObservedDate: pgtype.Date{Time: time.Now(), Valid: true}},
				{AnalyteName: "Glucose", ValueNumeric: pgtype.Float8{Float64: 99, Valid: true}, ObservedDate: pgtype.Date{Time: time.Now(), Valid: true}},
			}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodGet, "/api/profiles/"+pid.String()+"/results?all=true", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var got []ResultDTO
	_ = json.Unmarshal(rec.Body.Bytes(), &got)
	if len(got) != 2 {
		t.Errorf("want 2 results, got %d", len(got))
	}
}

func TestRequireProfileNotFound(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(context.Context, sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{}, pgx.ErrNoRows
		},
	}
	rec := do(t, router(q, nil), http.MethodGet, "/api/profiles/"+uuid.New().String()+"/results", "")
	if rec.Code != http.StatusNotFound {
		t.Errorf("want 404 for unknown profile, got %d", rec.Code)
	}
}

func TestAddBodyMeasurement(t *testing.T) {
	pid := uuid.New()
	var added sqlc.AddBodyMeasurementParams
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(context.Context, sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: pid}, nil
		},
		AddBodyMeasurementFn: func(_ context.Context, arg sqlc.AddBodyMeasurementParams) (sqlc.BodyMeasurement, error) {
			added = arg
			return sqlc.BodyMeasurement{ID: uuid.New(), Kind: arg.Kind, Value: arg.Value, MeasuredOn: arg.MeasuredOn}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodPost, "/api/profiles/"+pid.String()+"/body",
		`{"kind":"weight","value":72.5,"measuredOn":"2026-06-30"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d", rec.Code)
	}
	if added.Kind != "weight" || added.Value != 72.5 {
		t.Errorf("added = %+v", added)
	}
}

func TestAddBodyMeasurementBadKind(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(context.Context, sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: uuid.New()}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodPost, "/api/profiles/"+uuid.New().String()+"/body",
		`{"kind":"bmi","value":5}`)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("want 400 for bad kind, got %d", rec.Code)
	}
}

// A user must not reach another user's body data: an inaccessible profile 404s.
func TestBodyMeasurementsIsolation(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(context.Context, sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{}, pgx.ErrNoRows
		},
	}
	rec := do(t, router(q, nil), http.MethodPost, "/api/profiles/"+uuid.New().String()+"/body",
		`{"kind":"weight","value":70}`)
	if rec.Code != http.StatusNotFound {
		t.Errorf("want 404 for inaccessible profile, got %d", rec.Code)
	}
}

func TestUpdateProfile(t *testing.T) {
	pid := uuid.New()
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(context.Context, sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: pid, Name: "Old"}, nil
		},
		UpdateProfileFn: func(_ context.Context, arg sqlc.UpdateProfileParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: arg.ID, Name: arg.Name, DateOfBirth: arg.DateOfBirth}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodPatch, "/api/profiles/"+pid.String(),
		`{"name":"New","dateOfBirth":"1990-04-12"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var got ProfileDTO
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Name != "New" || got.DateOfBirth == nil || *got.DateOfBirth != "1990-04-12" {
		t.Errorf("body = %+v", got)
	}
}

func TestAddFavorite(t *testing.T) {
	var added sqlc.AddFavoriteParams
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(_ context.Context, arg sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: arg.ID}, nil
		},
		AddFavoriteFn: func(_ context.Context, arg sqlc.AddFavoriteParams) error {
			added = arg
			return nil
		},
	}
	aid := uuid.New()
	rec := do(t, router(q, nil), http.MethodPost, "/api/profiles/"+uuid.New().String()+"/favorites", `{"analyteId":"`+aid.String()+`"}`)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d", rec.Code)
	}
	if added.AnalyteID != aid {
		t.Errorf("favorite analyte = %v, want %v", added.AnalyteID, aid)
	}
}

func TestUpdateResult(t *testing.T) {
	var updated sqlc.UpdateResultParams
	pid := uuid.New()
	q := &sqlctest.FakeQuerier{
		GetResultFn: func(_ context.Context, id uuid.UUID) (sqlc.LabResult, error) {
			return sqlc.LabResult{ID: id, ProfileID: pid}, nil
		},
		GetProfileForUserFn: func(_ context.Context, arg sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: arg.ID}, nil
		},
		UpdateResultFn: func(_ context.Context, arg sqlc.UpdateResultParams) error {
			updated = arg
			return nil
		},
	}
	rid := uuid.New()
	aid := uuid.New()
	body := `{"analyteId":"` + aid.String() + `","observedDate":"2025-09-26","valueText":"99"}`
	rec := do(t, router(q, nil), http.MethodPost, "/api/results/"+rid.String(), body)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d", rec.Code)
	}
	if updated.ID != rid || updated.AnalyteID != aid {
		t.Errorf("update params = %+v", updated)
	}
}

// --- admin area ---

func TestGetMe_DevIsAdmin(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		GetUserFn: func(_ context.Context, id uuid.UUID) (sqlc.User, error) {
			return sqlc.User{ID: id, Email: pgtype.Text{String: "me@x.com", Valid: true}}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodGet, "/api/me", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var got MeDTO
	_ = json.Unmarshal(rec.Body.Bytes(), &got)
	if !got.IsAdmin {
		t.Errorf("dev user should be admin, got %+v", got)
	}
}

func TestListAllUsers(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		ListUsersWithProfileCountsFn: func(context.Context) ([]sqlc.ListUsersWithProfileCountsRow, error) {
			return []sqlc.ListUsersWithProfileCountsRow{
				{ID: uuid.New(), Email: pgtype.Text{String: "a@b.com", Valid: true}, OwnedCount: 2, SharedCount: 1},
			}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodGet, "/api/admin/users", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var got []AdminUserDTO
	_ = json.Unmarshal(rec.Body.Bytes(), &got)
	if len(got) != 1 || got[0].OwnedCount != 2 || got[0].SharedCount != 1 {
		t.Errorf("users = %+v", got)
	}
}

// A non-admin is rejected before any query runs.
func TestListAllUsers_Forbidden(t *testing.T) {
	s := &Server{
		q:   &sqlctest.FakeQuerier{},
		log: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}
	req := httptest.NewRequest(http.MethodGet, "/api/admin/users", nil)
	req = req.WithContext(context.WithValue(req.Context(), isAdminKey, false))
	rec := httptest.NewRecorder()
	s.listAllUsers(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("non-admin: want 403, got %d", rec.Code)
	}
}

func TestUpdateResultBadID(t *testing.T) {
	rec := do(t, router(&sqlctest.FakeQuerier{}, nil), http.MethodPost, "/api/results/not-a-uuid", `{"analyteId":"x"}`)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("want 400 for bad id, got %d", rec.Code)
	}
}

// --- per-user isolation ---

// A profile the current user neither owns nor shares is invisible: requests
// scoped to it 404 (and don't leak existence), and writes never reach the DB.
func TestProfileIsolation_DeniesForeignProfile(t *testing.T) {
	notMine := func(context.Context, sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
		return sqlc.Profile{}, pgx.ErrNoRows // owned-or-shared check finds nothing
	}
	q := &sqlctest.FakeQuerier{GetProfileForUserFn: notMine}
	pid := uuid.New().String()

	cases := []struct{ method, path string }{
		{http.MethodGet, "/api/profiles/" + pid + "/results"},
		{http.MethodGet, "/api/profiles/" + pid + "/reports"},
		{http.MethodGet, "/api/profiles/" + pid + "/members"},
		{http.MethodGet, "/api/profiles/" + pid + "/analytes/" + uuid.New().String() + "/analysis"},
	}
	for _, c := range cases {
		rec := do(t, router(q, nil), c.method, c.path, "")
		if rec.Code != http.StatusNotFound {
			t.Errorf("%s %s: want 404, got %d", c.method, c.path, rec.Code)
		}
	}
}

// Editing a result belonging to another user's profile is blocked before the
// UpdateResult/DeleteResult query runs.
func TestResultIsolation_DeniesForeignResult(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		GetResultFn: func(_ context.Context, id uuid.UUID) (sqlc.LabResult, error) {
			return sqlc.LabResult{ID: id, ProfileID: uuid.New()}, nil
		},
		GetProfileForUserFn: func(context.Context, sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{}, pgx.ErrNoRows // not owned or shared
		},
		UpdateResultFn: func(context.Context, sqlc.UpdateResultParams) error {
			t.Fatal("UpdateResult must not run for an inaccessible result")
			return nil
		},
		DeleteResultFn: func(context.Context, uuid.UUID) error {
			t.Fatal("DeleteResult must not run for an inaccessible result")
			return nil
		},
	}
	rid := uuid.New().String()
	body := `{"analyteId":"` + uuid.New().String() + `","observedDate":"2025-09-26"}`
	if rec := do(t, router(q, nil), http.MethodPost, "/api/results/"+rid, body); rec.Code != http.StatusNotFound {
		t.Errorf("update foreign result: want 404, got %d", rec.Code)
	}
	if rec := do(t, router(q, nil), http.MethodDelete, "/api/results/"+rid, ""); rec.Code != http.StatusNotFound {
		t.Errorf("delete foreign result: want 404, got %d", rec.Code)
	}
}

// Only the owner can delete a profile; a shared editor gets 403.
func TestDeleteProfile_OwnerOnly(t *testing.T) {
	sharedProfile := func(_ context.Context, arg sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
		other := uuid.New() // owner is someone else
		return sqlc.Profile{ID: arg.ID, OwnerUserID: &other}, nil
	}
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: sharedProfile,
		DeleteProfileFn:     func(context.Context, uuid.UUID) error { t.Fatal("must not delete"); return nil },
	}
	rec := do(t, router(q, nil), http.MethodDelete, "/api/profiles/"+uuid.New().String(), "")
	if rec.Code != http.StatusForbidden {
		t.Errorf("non-owner delete: want 403, got %d", rec.Code)
	}
}

// Sharing requires the target to have signed in already (a users row exists).
func TestAddMember_UnknownEmail(t *testing.T) {
	me := DevUserID
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(_ context.Context, arg sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: arg.ID, OwnerUserID: &me}, nil // I own it
		},
		GetUserByEmailFn: func(context.Context, string) (sqlc.User, error) {
			return sqlc.User{}, pgx.ErrNoRows
		},
	}
	body := `{"email":"nobody@example.com"}`
	rec := do(t, router(q, nil), http.MethodPost, "/api/profiles/"+uuid.New().String()+"/members", body)
	if rec.Code != http.StatusNotFound {
		t.Errorf("share with unknown email: want 404, got %d", rec.Code)
	}
}

// The owner can share a profile with an existing user.
func TestAddMember_Success(t *testing.T) {
	me := DevUserID
	target := uuid.New()
	var added sqlc.AddProfileMemberParams
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(_ context.Context, arg sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: arg.ID, OwnerUserID: &me}, nil
		},
		GetUserByEmailFn: func(context.Context, string) (sqlc.User, error) {
			return sqlc.User{ID: target, Email: pgtype.Text{String: "friend@example.com", Valid: true}}, nil
		},
		AddProfileMemberFn: func(_ context.Context, arg sqlc.AddProfileMemberParams) error {
			added = arg
			return nil
		},
	}
	body := `{"email":"friend@example.com"}`
	rec := do(t, router(q, nil), http.MethodPost, "/api/profiles/"+uuid.New().String()+"/members", body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, body=%s", rec.Code, rec.Body.String())
	}
	if added.UserID != target || added.Role != "editor" {
		t.Errorf("added member = %+v", added)
	}
}

func TestGetAnalysis(t *testing.T) {
	gen := time.Date(2026, 1, 10, 0, 0, 0, 0, time.UTC)
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(_ context.Context, arg sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: arg.ID}, nil
		},
		ResultStatsForProfileAnalyteFn: func(context.Context, sqlc.ResultStatsForProfileAnalyteParams) (sqlc.ResultStatsForProfileAnalyteRow, error) {
			return sqlc.ResultStatsForProfileAnalyteRow{Count: 2, LastChanged: pgtype.Timestamptz{Time: gen.Add(-time.Hour), Valid: true}}, nil
		},
		GetAnalysisFn: func(context.Context, sqlc.GetAnalysisParams) (sqlc.AnalyteAnalysis, error) {
			return sqlc.AnalyteAnalysis{Content: "stored", ResultCount: 2, GeneratedAt: pgtype.Timestamptz{Time: gen, Valid: true}}, nil
		},
	}
	path := "/api/profiles/" + uuid.New().String() + "/analytes/" + uuid.New().String() + "/analysis"
	rec := do(t, router(q, nil), http.MethodGet, path, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var got struct {
		Analysis *AnalysisDTO `json:"analysis"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Analysis == nil || got.Analysis.Content != "stored" || got.Analysis.Stale {
		t.Errorf("analysis = %+v", got.Analysis)
	}
}

func TestAnalyzeAnalyte(t *testing.T) {
	ex := llmtest.MockExtractor(t, "FRESH ANALYSIS")
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(_ context.Context, arg sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: arg.ID}, nil
		},
		// analysis.Generate loads the profile (name/DOB) for the LLM prompt.
		GetProfileFn: func(_ context.Context, id uuid.UUID) (sqlc.Profile, error) { return sqlc.Profile{ID: id}, nil },
		GetAnalyteFn: func(context.Context, uuid.UUID) (sqlc.Analyte, error) { return sqlc.Analyte{Name: "Glucose"}, nil },
		ListResultsForProfileAnalyteFn: func(context.Context, sqlc.ListResultsForProfileAnalyteParams) ([]sqlc.ListResultsForProfileAnalyteRow, error) {
			return []sqlc.ListResultsForProfileAnalyteRow{
				{AnalyteName: "Glucose", ValueNumeric: pgtype.Float8{Float64: 95, Valid: true}, ObservedDate: pgtype.Date{Time: time.Now(), Valid: true}},
			}, nil
		},
		ListLatestResultsForProfileFn: func(context.Context, uuid.UUID) ([]sqlc.ListLatestResultsForProfileRow, error) { return nil, nil },
		UpsertAnalysisFn:              func(context.Context, sqlc.UpsertAnalysisParams) error { return nil },
	}
	path := "/api/profiles/" + uuid.New().String() + "/analytes/" + uuid.New().String() + "/analysis"
	rec := do(t, router(q, ex), http.MethodPost, path, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body=%s", rec.Code, rec.Body.String())
	}
	var got struct {
		Analysis AnalysisDTO `json:"analysis"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Analysis.Content != "FRESH ANALYSIS" || got.Analysis.BasedOnCount != 1 {
		t.Errorf("analysis = %+v", got.Analysis)
	}
}
