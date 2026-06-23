package api

import (
	"encoding/json"

	"github.com/google/uuid"
	"github.com/winkler/lab-tracker/backend/internal/db/sqlc"
)

type ProfileDTO struct {
	ID          uuid.UUID `json:"id"`
	Name        string    `json:"name"`
	DateOfBirth *string   `json:"dateOfBirth"`
}

func toProfileDTO(p sqlc.Profile) ProfileDTO {
	return ProfileDTO{ID: p.ID, Name: p.Name, DateOfBirth: dateToPtr(p.DateOfBirth)}
}

type AnalyteDTO struct {
	ID          uuid.UUID `json:"id"`
	Name        string    `json:"name"`
	DefaultUnit *string   `json:"defaultUnit"`
	Category    *string   `json:"category"`
	Loinc       *string   `json:"loinc"`
	Specimens   []string  `json:"specimens"`
}

func toAnalyteDTO(a sqlc.Analyte) AnalyteDTO {
	return AnalyteDTO{
		ID:          a.ID,
		Name:        a.Name,
		DefaultUnit: textToPtr(a.DefaultUnit),
		Category:    textToPtr(a.Category),
		Loinc:       textToPtr(a.Loinc),
		Specimens:   a.Specimens,
	}
}

type ResultDTO struct {
	ID            uuid.UUID `json:"id"`
	ReportID      uuid.UUID `json:"reportId"`
	AnalyteID     uuid.UUID `json:"analyteId"`
	AnalyteName   string    `json:"analyteName"`
	Category      *string   `json:"category"`
	RawTestName   string    `json:"rawTestName"`
	ValueText     *string   `json:"valueText"`
	ValueNumeric  *float64  `json:"valueNumeric"`
	Unit          *string   `json:"unit"`
	ReferenceLow  *float64  `json:"referenceLow"`
	ReferenceHigh *float64  `json:"referenceHigh"`
	ReferenceText *string   `json:"referenceText"`
	Note          *string   `json:"note"`
	ObservedDate  *string   `json:"observedDate"`
}

func toResultDTO(r sqlc.ListResultsForProfileRow) ResultDTO {
	return ResultDTO{
		ID:            r.ID,
		ReportID:      r.ReportID,
		AnalyteID:     r.AnalyteID,
		AnalyteName:   r.AnalyteName,
		Category:      textToPtr(r.AnalyteCategory),
		RawTestName:   r.RawTestName,
		ValueText:     textToPtr(r.ValueText),
		ValueNumeric:  float8ToPtr(r.ValueNumeric),
		Unit:          textToPtr(r.Unit),
		ReferenceLow:  float8ToPtr(r.ReferenceLow),
		ReferenceHigh: float8ToPtr(r.ReferenceHigh),
		ReferenceText: textToPtr(r.ReferenceText),
		Note:          textToPtr(r.Note),
		ObservedDate:  dateToPtr(r.ObservedDate),
	}
}

func toResultDTOFromAnalyte(r sqlc.ListResultsForProfileAnalyteRow) ResultDTO {
	return ResultDTO{
		ID:            r.ID,
		ReportID:      r.ReportID,
		AnalyteID:     r.AnalyteID,
		AnalyteName:   r.AnalyteName,
		Category:      textToPtr(r.AnalyteCategory),
		RawTestName:   r.RawTestName,
		ValueText:     textToPtr(r.ValueText),
		ValueNumeric:  float8ToPtr(r.ValueNumeric),
		Unit:          textToPtr(r.Unit),
		ReferenceLow:  float8ToPtr(r.ReferenceLow),
		ReferenceHigh: float8ToPtr(r.ReferenceHigh),
		ReferenceText: textToPtr(r.ReferenceText),
		Note:          textToPtr(r.Note),
		ObservedDate:  dateToPtr(r.ObservedDate),
	}
}

func toResultDTOFromLatest(r sqlc.ListLatestResultsForProfileRow) ResultDTO {
	return ResultDTO{
		ID:            r.ID,
		ReportID:      r.ReportID,
		AnalyteID:     r.AnalyteID,
		AnalyteName:   r.AnalyteName,
		Category:      textToPtr(r.AnalyteCategory),
		RawTestName:   r.RawTestName,
		ValueText:     textToPtr(r.ValueText),
		ValueNumeric:  float8ToPtr(r.ValueNumeric),
		Unit:          textToPtr(r.Unit),
		ReferenceLow:  float8ToPtr(r.ReferenceLow),
		ReferenceHigh: float8ToPtr(r.ReferenceHigh),
		ReferenceText: textToPtr(r.ReferenceText),
		Note:          textToPtr(r.Note),
		ObservedDate:  dateToPtr(r.ObservedDate),
	}
}

// DraftResultDTO is one parsed row plus a server-suggested canonical analyte
// (resolved from the alias table during parsing).
type DraftResultDTO struct {
	TestName             string   `json:"testName"`
	Value                string   `json:"value"`
	ValueNumeric         *float64 `json:"valueNumeric"`
	Unit                 *string  `json:"unit"`
	ReferenceRange       *string  `json:"referenceRange"`
	ReferenceLow         *float64 `json:"referenceLow"`
	ReferenceHigh        *float64 `json:"referenceHigh"`
	Specimen             *string  `json:"specimen"`
	Note                 *string  `json:"note"`
	SuggestedAnalyteID   *string  `json:"suggestedAnalyteId"`
	SuggestedAnalyteName *string  `json:"suggestedAnalyteName"`
}

// DraftDTO is the enriched, review-ready extraction stored on the report.
type DraftDTO struct {
	LabName       *string          `json:"labName"`
	CollectedDate *string          `json:"collectedDate"`
	ReportedDate  *string          `json:"reportedDate"`
	Results       []DraftResultDTO `json:"results"`
}

type ReportDTO struct {
	ID               uuid.UUID `json:"id"`
	ProfileID        uuid.UUID `json:"profileId"`
	OriginalFilename *string   `json:"originalFilename"`
	SourceLab        *string   `json:"sourceLab"`
	Status           string    `json:"status"`
	ParseError       *string   `json:"parseError"`
	CollectedDate    *string   `json:"collectedDate"`
	ReportedDate     *string   `json:"reportedDate"`
	Draft            *DraftDTO `json:"draft"`
}

func toReportDTO(r sqlc.LabReport) ReportDTO {
	dto := ReportDTO{
		ID:               r.ID,
		ProfileID:        r.ProfileID,
		OriginalFilename: textToPtr(r.OriginalFilename),
		SourceLab:        textToPtr(r.SourceLab),
		Status:           r.Status,
		ParseError:       textToPtr(r.ParseError),
		CollectedDate:    dateToPtr(r.CollectedDate),
		ReportedDate:     dateToPtr(r.ReportedDate),
	}
	if len(r.ParsedDraft) > 0 {
		var draft DraftDTO
		if err := json.Unmarshal(r.ParsedDraft, &draft); err == nil {
			dto.Draft = &draft
		}
	}
	return dto
}
