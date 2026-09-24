package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/Seklfreak/lab-tracker/backend/internal/db/sqlc"
)

// Device readings are results from a home device (e.g. a fingerstick lipid
// meter). Each reading becomes one PDF-less, already-saved report whose
// external_id is the device's stable record id, so re-running an importer
// never creates duplicates.

const (
	maxExternalIDLen    = 200
	maxLookupIDs        = 1000
	maxResultsPerReport = 20
)

type deviceLookupReq struct {
	ExternalIDs []string `json:"externalIds"`
}

type deviceReadingRefDTO struct {
	ExternalID string    `json:"externalId"`
	ReportID   uuid.UUID `json:"reportId"`
	ProfileID  uuid.UUID `json:"profileId"`
}

// lookupDeviceReadings reports which of the given external ids are already
// imported on a profile the user can access.
func (s *Server) lookupDeviceReadings(w http.ResponseWriter, r *http.Request) {
	var req deviceLookupReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if len(req.ExternalIDs) > maxLookupIDs {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("at most %d ids per lookup", maxLookupIDs))
		return
	}
	imported, err := s.findDeviceReadings(r.Context(), s.q, req.ExternalIDs)
	if err != nil {
		s.log.Error("lookup device readings", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to look up readings")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"imported": imported})
}

func (s *Server) findDeviceReadings(ctx context.Context, q sqlc.Querier, ids []string) ([]deviceReadingRefDTO, error) {
	out := []deviceReadingRefDTO{}
	if len(ids) == 0 {
		return out, nil
	}
	uid := currentUserID(ctx)
	rows, err := q.ListDeviceReportsByExternalIDForUser(ctx, sqlc.ListDeviceReportsByExternalIDForUserParams{
		ExternalIds: ids,
		UserID:      &uid,
	})
	if err != nil {
		return nil, err
	}
	for _, row := range rows {
		out = append(out, deviceReadingRefDTO{ExternalID: row.ExternalID.String, ReportID: row.ID, ProfileID: row.ProfileID})
	}
	return out, nil
}

type deviceResultIn struct {
	Analyte string  `json:"analyte"`
	Value   float64 `json:"value"`
	Unit    string  `json:"unit"`
}

type deviceReadingReq struct {
	ExternalID string           `json:"externalId"`
	ProfileID  string           `json:"profileId"`
	TakenAt    string           `json:"takenAt"` // RFC 3339, in the reading's local offset
	Device     string           `json:"device"`
	Results    []deviceResultIn `json:"results"`
}

type deviceReadingResp struct {
	// Status is "imported" for a new reading, "exists" if it was already there.
	Status string `json:"status"`
	deviceReadingRefDTO
}

// importDeviceReading stores one device reading on a profile, idempotently. A
// reading already imported on any profile the user can access is left alone.
func (s *Server) importDeviceReading(w http.ResponseWriter, r *http.Request) {
	var req deviceReadingReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	req.ExternalID = strings.TrimSpace(req.ExternalID)
	if req.ExternalID == "" || len(req.ExternalID) > maxExternalIDLen {
		writeError(w, http.StatusBadRequest, "externalId is required (max 200 characters)")
		return
	}
	takenAt, err := time.Parse(time.RFC3339, req.TakenAt)
	if err != nil {
		writeError(w, http.StatusBadRequest, "takenAt must be an RFC 3339 timestamp")
		return
	}
	if len(req.Results) == 0 || len(req.Results) > maxResultsPerReport {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("between 1 and %d results are required", maxResultsPerReport))
		return
	}
	for i, res := range req.Results {
		if strings.TrimSpace(res.Analyte) == "" || math.IsNaN(res.Value) || math.IsInf(res.Value, 0) {
			writeError(w, http.StatusBadRequest, fmt.Sprintf("result %d: analyte and a numeric value are required", i+1))
			return
		}
	}
	pid, ok := parseUUID(req.ProfileID)
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid profileId")
		return
	}
	// 404 for profiles the user can't access, like every other endpoint.
	p, ok := s.profileForUser(w, r, pid)
	if !ok {
		return
	}

	ctx := r.Context()
	existing, err := s.findDeviceReadings(ctx, s.q, []string{req.ExternalID})
	if err != nil {
		s.log.Error("lookup device reading", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to import reading")
		return
	}
	if len(existing) > 0 {
		writeJSON(w, http.StatusOK, deviceReadingResp{Status: "exists", deviceReadingRefDTO: existing[0]})
		return
	}

	device := strings.TrimSpace(req.Device)
	if device == "" {
		device = "Home device"
	}
	// The date is taken in the reading's own offset; the time of day goes into
	// the note, since results only carry a date.
	observed := pgtype.Date{Time: time.Date(takenAt.Year(), takenAt.Month(), takenAt.Day(), 0, 0, 0, 0, time.UTC), Valid: true}
	note := fmt.Sprintf("%s reading at %s", device, takenAt.Format("15:04"))

	var created *sqlc.LabReport
	var badResult error
	err = s.withTx(ctx, func(q sqlc.Querier) error {
		report, err := q.CreateDeviceReport(ctx, sqlc.CreateDeviceReportParams{
			ProfileID:     p.ID,
			ExternalID:    pgtype.Text{String: req.ExternalID, Valid: true},
			SourceLab:     pgtype.Text{String: device, Valid: true},
			CollectedDate: observed,
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return nil // imported concurrently on this profile
		}
		if err != nil {
			return fmt.Errorf("create device report: %w", err)
		}
		for i, res := range req.Results {
			analyteID, err := lookupAnalyteByName(ctx, q, res.Analyte)
			if err != nil {
				badResult = fmt.Errorf("result %d: %w", i+1, err)
				return badResult
			}
			value := res.Value
			if _, err := q.CreateResult(ctx, sqlc.CreateResultParams{
				ReportID:     report.ID,
				ProfileID:    p.ID,
				AnalyteID:    analyteID,
				RawTestName:  strings.TrimSpace(res.Analyte),
				ValueText:    pgtype.Text{String: formatValue(value), Valid: true},
				ValueNumeric: ptrToFloat8(&value),
				Unit:         optText(strings.TrimSpace(res.Unit)),
				Note:         pgtype.Text{String: note, Valid: true},
				ObservedDate: observed,
			}); err != nil {
				return fmt.Errorf("create result: %w", err)
			}
		}
		created = &report
		return nil
	})
	if badResult != nil {
		writeError(w, http.StatusBadRequest, badResult.Error())
		return
	}
	if err != nil {
		s.log.Error("import device reading", "err", err)
		writeError(w, http.StatusInternalServerError, "failed to import reading")
		return
	}
	if created == nil {
		writeJSON(w, http.StatusOK, deviceReadingResp{Status: "exists", deviceReadingRefDTO: deviceReadingRefDTO{ExternalID: req.ExternalID, ProfileID: p.ID}})
		return
	}
	writeJSON(w, http.StatusCreated, deviceReadingResp{
		Status:              "imported",
		deviceReadingRefDTO: deviceReadingRefDTO{ExternalID: req.ExternalID, ReportID: created.ID, ProfileID: p.ID},
	})
}

var errUnknownAnalyte = errors.New("unknown analyte")

// lookupAnalyteByName resolves a canonical analyte name or a known alias.
// Device importers send canonical names; unknown names are rejected rather
// than creating new analytes.
func lookupAnalyteByName(ctx context.Context, q sqlc.Querier, name string) (uuid.UUID, error) {
	a, err := q.GetAnalyteByName(ctx, name)
	if err == nil {
		return a.ID, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, err
	}
	a, err = q.GetAliasByRawName(ctx, name)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, fmt.Errorf("%w %q", errUnknownAnalyte, name)
	}
	if err != nil {
		return uuid.Nil, err
	}
	return a.ID, nil
}

func formatValue(v float64) string { return strconv.FormatFloat(v, 'f', -1, 64) }

// withTx runs fn against a transaction-scoped Querier. Without a pool (handler
// tests use a fake Querier) it runs against s.q directly.
func (s *Server) withTx(ctx context.Context, fn func(sqlc.Querier) error) error {
	if s.pool == nil {
		return fn(s.q)
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op after commit
	if err := fn(sqlc.New(tx)); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
