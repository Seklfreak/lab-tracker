package api

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
	"github.com/Seklfreak/lab-tracker/backend/internal/sqlctest"
)

func deviceReadingBody(profileID uuid.UUID) string {
	return `{"externalId":"curo-l7:abc","profileId":"` + profileID.String() + `",
		"takenAt":"2025-03-14T08:30:00-04:00","device":"CURO L7",
		"results":[{"analyte":"Total Cholesterol","value":195,"unit":"mg/dL"},
		           {"analyte":"Triglycerides","value":110,"unit":"mg/dL"},
		           {"analyte":"HDL","value":55,"unit":"mg/dL"}]}`
}

func mineProfile(context.Context, sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
	return sqlc.Profile{ID: uuid.New()}, nil
}

func noDeviceReports(context.Context, sqlc.ListDeviceReportsByExternalIDForUserParams) ([]sqlc.ListDeviceReportsByExternalIDForUserRow, error) {
	return nil, nil
}

func TestImportDeviceReading_Creates(t *testing.T) {
	pid := uuid.New()
	analytes := map[string]uuid.UUID{"Total Cholesterol": uuid.New(), "Triglycerides": uuid.New()}
	hdl := uuid.New()
	var report sqlc.CreateDeviceReportParams
	var results []sqlc.CreateResultParams
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(_ context.Context, arg sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{ID: arg.ID}, nil
		},
		ListDeviceReportsByExternalIDForUserFn: noDeviceReports,
		CreateDeviceReportFn: func(_ context.Context, arg sqlc.CreateDeviceReportParams) (sqlc.LabReport, error) {
			report = arg
			return sqlc.LabReport{ID: uuid.New(), ProfileID: arg.ProfileID}, nil
		},
		GetAnalyteByNameFn: func(_ context.Context, name string) (sqlc.Analyte, error) {
			if id, ok := analytes[name]; ok {
				return sqlc.Analyte{ID: id}, nil
			}
			return sqlc.Analyte{}, pgx.ErrNoRows
		},
		GetAliasByRawNameFn: func(_ context.Context, name string) (sqlc.Analyte, error) {
			if name == "HDL" {
				return sqlc.Analyte{ID: hdl}, nil
			}
			return sqlc.Analyte{}, pgx.ErrNoRows
		},
		CreateResultFn: func(_ context.Context, arg sqlc.CreateResultParams) (sqlc.LabResult, error) {
			results = append(results, arg)
			return sqlc.LabResult{}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodPost, "/api/device-readings", deviceReadingBody(pid))
	if rec.Code != http.StatusCreated {
		t.Fatalf("want 201, got %d: %s", rec.Code, rec.Body)
	}
	var resp deviceReadingResp
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Status != "imported" || resp.ProfileID != pid {
		t.Errorf("resp %+v", resp)
	}
	if report.ProfileID != pid || report.ExternalID.String != "curo-l7:abc" || report.SourceLab.String != "CURO L7" {
		t.Errorf("report params %+v", report)
	}
	// The date comes from the reading's own offset, not UTC.
	if got := report.CollectedDate.Time.Format("2006-01-02"); got != "2025-03-14" {
		t.Errorf("collected date %s", got)
	}
	if len(results) != 3 {
		t.Fatalf("want 3 results, got %d", len(results))
	}
	if results[2].AnalyteID != hdl || results[0].ValueNumeric.Float64 != 195 || results[0].ValueText.String != "195" {
		t.Errorf("results %+v", results)
	}
	if results[0].Note.String != "CURO L7 reading at 08:30" {
		t.Errorf("note %q", results[0].Note.String)
	}
}

// Re-importing a reading the user already has is a no-op.
func TestImportDeviceReading_ExistsIsIdempotent(t *testing.T) {
	existing := uuid.New()
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: mineProfile,
		ListDeviceReportsByExternalIDForUserFn: func(context.Context, sqlc.ListDeviceReportsByExternalIDForUserParams) ([]sqlc.ListDeviceReportsByExternalIDForUserRow, error) {
			return []sqlc.ListDeviceReportsByExternalIDForUserRow{{ID: existing, ProfileID: uuid.New()}}, nil
		},
		CreateDeviceReportFn: func(context.Context, sqlc.CreateDeviceReportParams) (sqlc.LabReport, error) {
			t.Fatal("must not create a duplicate report")
			return sqlc.LabReport{}, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodPost, "/api/device-readings", deviceReadingBody(uuid.New()))
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	var resp deviceReadingResp
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Status != "exists" || resp.ReportID != existing {
		t.Errorf("resp %+v", resp)
	}
}

// Importing onto a profile the user can't access 404s before anything is written.
func TestImportDeviceReading_ForeignProfile(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn: func(context.Context, sqlc.GetProfileForUserParams) (sqlc.Profile, error) {
			return sqlc.Profile{}, pgx.ErrNoRows
		},
		CreateDeviceReportFn: func(context.Context, sqlc.CreateDeviceReportParams) (sqlc.LabReport, error) {
			t.Fatal("must not write to an inaccessible profile")
			return sqlc.LabReport{}, nil
		},
	}
	if rec := do(t, router(q, nil), http.MethodPost, "/api/device-readings", deviceReadingBody(uuid.New())); rec.Code != http.StatusNotFound {
		t.Errorf("want 404, got %d", rec.Code)
	}
}

func TestImportDeviceReading_UnknownAnalyte(t *testing.T) {
	q := &sqlctest.FakeQuerier{
		GetProfileForUserFn:                    mineProfile,
		ListDeviceReportsByExternalIDForUserFn: noDeviceReports,
		CreateDeviceReportFn: func(context.Context, sqlc.CreateDeviceReportParams) (sqlc.LabReport, error) {
			return sqlc.LabReport{ID: uuid.New()}, nil
		},
		GetAnalyteByNameFn:  func(context.Context, string) (sqlc.Analyte, error) { return sqlc.Analyte{}, pgx.ErrNoRows },
		GetAliasByRawNameFn: func(context.Context, string) (sqlc.Analyte, error) { return sqlc.Analyte{}, pgx.ErrNoRows },
	}
	if rec := do(t, router(q, nil), http.MethodPost, "/api/device-readings", deviceReadingBody(uuid.New())); rec.Code != http.StatusBadRequest {
		t.Errorf("want 400, got %d", rec.Code)
	}
}

func TestImportDeviceReading_Validation(t *testing.T) {
	pid := uuid.New().String()
	cases := map[string]string{
		"no external id": `{"profileId":"` + pid + `","takenAt":"2025-03-14T08:30:00Z","results":[{"analyte":"HDL","value":1}]}`,
		"bad time":       `{"externalId":"x","profileId":"` + pid + `","takenAt":"2025-03-14","results":[{"analyte":"HDL","value":1}]}`,
		"no results":     `{"externalId":"x","profileId":"` + pid + `","takenAt":"2025-03-14T08:30:00Z","results":[]}`,
		"bad profile":    `{"externalId":"x","profileId":"nope","takenAt":"2025-03-14T08:30:00Z","results":[{"analyte":"HDL","value":1}]}`,
	}
	for name, body := range cases {
		if rec := do(t, router(&sqlctest.FakeQuerier{}, nil), http.MethodPost, "/api/device-readings", body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s: want 400, got %d", name, rec.Code)
		}
	}
}

// The lookup only ever asks about the current user's profiles.
func TestLookupDeviceReadings_ScopedToUser(t *testing.T) {
	var got sqlc.ListDeviceReportsByExternalIDForUserParams
	q := &sqlctest.FakeQuerier{
		ListDeviceReportsByExternalIDForUserFn: func(_ context.Context, arg sqlc.ListDeviceReportsByExternalIDForUserParams) ([]sqlc.ListDeviceReportsByExternalIDForUserRow, error) {
			got = arg
			return nil, nil
		},
	}
	rec := do(t, router(q, nil), http.MethodPost, "/api/device-readings/lookup", `{"externalIds":["a","b"]}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", rec.Code)
	}
	if got.UserID == nil || *got.UserID != DevUserID || len(got.ExternalIds) != 2 {
		t.Errorf("params %+v", got)
	}
	if body := rec.Body.String(); body != "{\"imported\":[]}\n" {
		t.Errorf("body %q", body)
	}
}
