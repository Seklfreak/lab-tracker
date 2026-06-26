-- name: CreateResult :one
INSERT INTO lab_results (
    report_id, profile_id, analyte_id, raw_test_name,
    value_text, value_numeric, unit,
    reference_low, reference_high, reference_text, note, observed_date
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12
)
RETURNING *;

-- name: GetResult :one
SELECT * FROM lab_results
WHERE id = $1;

-- name: DeleteResultsForReport :exec
DELETE FROM lab_results
WHERE report_id = $1;

-- name: UpdateResult :exec
UPDATE lab_results SET
    analyte_id = $2,
    value_text = $3,
    value_numeric = $4,
    unit = $5,
    reference_low = $6,
    reference_high = $7,
    reference_text = $8,
    note = $9,
    observed_date = $10,
    updated_at = now()
WHERE id = $1;

-- name: DeleteResult :exec
DELETE FROM lab_results
WHERE id = $1;

-- name: ListResultsForProfile :many
SELECT r.*, a.name AS analyte_name, a.category AS analyte_category, rep.source_lab AS source_lab
FROM lab_results r
JOIN analytes a ON a.id = r.analyte_id
LEFT JOIN lab_reports rep ON rep.id = r.report_id
WHERE r.profile_id = $1
ORDER BY r.observed_date DESC, a.name;

-- name: ListResultsForProfileAnalyte :many
SELECT r.*, a.name AS analyte_name, a.category AS analyte_category, rep.source_lab AS source_lab,
    (f.analyte_id IS NOT NULL)::boolean AS is_favorite
FROM lab_results r
JOIN analytes a ON a.id = r.analyte_id
LEFT JOIN lab_reports rep ON rep.id = r.report_id
LEFT JOIN favorites f ON f.profile_id = r.profile_id AND f.analyte_id = r.analyte_id
WHERE r.profile_id = $1 AND r.analyte_id = $2
ORDER BY r.observed_date;

-- name: ListLatestResultsForProfile :many
SELECT DISTINCT ON (r.analyte_id)
    r.*, a.name AS analyte_name, a.category AS analyte_category,
    rep.source_lab AS source_lab,
    COUNT(*) OVER (PARTITION BY r.analyte_id) AS result_count,
    (f.analyte_id IS NOT NULL)::boolean AS is_favorite
FROM lab_results r
JOIN analytes a ON a.id = r.analyte_id
LEFT JOIN lab_reports rep ON rep.id = r.report_id
LEFT JOIN favorites f ON f.profile_id = r.profile_id AND f.analyte_id = r.analyte_id
WHERE r.profile_id = $1
ORDER BY r.analyte_id, r.observed_date DESC, r.created_at DESC;
