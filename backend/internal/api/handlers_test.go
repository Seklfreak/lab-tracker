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
	"github.com/winkler/lab-tracker/backend/internal/db/sqlc"
	"github.com/winkler/lab-tracker/backend/internal/llm"
	"github.com/winkler/lab-tracker/backend/internal/llmtest"
	"github.com/winkler/lab-tracker/backend/internal/sqlctest"
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
		ListProfilesFn: func(context.Context) ([]sqlc.Profile, error) {
			return []sqlc.Profile{{ID: uuid.New(), Name: "Sebastian"}}, nil
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
	if len(got) != 1 || got[0].Name != "Sebastian" {
		t.Errorf("body = %+v", got)
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
		GetProfileFn: func(_ context.Context, id uuid.UUID) (sqlc.Profile, error) {
			return sqlc.Profile{ID: id, Name: "Test"}, nil
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
		GetProfileFn: func(_ context.Context, id uuid.UUID) (sqlc.Profile, error) { return sqlc.Profile{ID: id}, nil },
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
		GetProfileFn: func(context.Context, uuid.UUID) (sqlc.Profile, error) {
			return sqlc.Profile{}, pgx.ErrNoRows
		},
	}
	rec := do(t, router(q, nil), http.MethodGet, "/api/profiles/"+uuid.New().String()+"/results", "")
	if rec.Code != http.StatusNotFound {
		t.Errorf("want 404 for unknown profile, got %d", rec.Code)
	}
}

func TestAddFavorite(t *testing.T) {
	var added sqlc.AddFavoriteParams
	q := &sqlctest.FakeQuerier{
		GetProfileFn: func(_ context.Context, id uuid.UUID) (sqlc.Profile, error) { return sqlc.Profile{ID: id}, nil },
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
	q := &sqlctest.FakeQuerier{
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

func TestUpdateResultBadID(t *testing.T) {
	rec := do(t, router(&sqlctest.FakeQuerier{}, nil), http.MethodPost, "/api/results/not-a-uuid", `{"analyteId":"x"}`)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("want 400 for bad id, got %d", rec.Code)
	}
}

func TestGetAnalysis(t *testing.T) {
	gen := time.Date(2026, 1, 10, 0, 0, 0, 0, time.UTC)
	q := &sqlctest.FakeQuerier{
		GetProfileFn: func(_ context.Context, id uuid.UUID) (sqlc.Profile, error) { return sqlc.Profile{ID: id}, nil },
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
