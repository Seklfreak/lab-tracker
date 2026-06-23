-- name: CreateReport :one
INSERT INTO lab_reports (profile_id, pdf_object_key, original_filename, status)
VALUES ($1, $2, $3, 'parsing')
RETURNING *;

-- name: GetReport :one
SELECT * FROM lab_reports
WHERE id = $1;

-- name: ListReportsForProfile :many
SELECT * FROM lab_reports
WHERE profile_id = $1
ORDER BY created_at DESC;

-- name: SetReportParsed :exec
UPDATE lab_reports
SET status = 'parsed',
    parsed_draft = $2,
    source_lab = $3,
    collected_date = $4,
    reported_date = $5
WHERE id = $1;

-- name: SetReportError :exec
UPDATE lab_reports
SET status = 'error',
    parse_error = $2
WHERE id = $1;

-- name: SetReportSaved :exec
UPDATE lab_reports
SET status = 'saved',
    source_lab = $2,
    collected_date = $3,
    reported_date = $4
WHERE id = $1;
