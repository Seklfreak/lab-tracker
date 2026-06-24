-- name: GetAnalysis :one
SELECT * FROM analyte_analyses
WHERE profile_id = $1 AND analyte_id = $2;

-- name: UpsertAnalysis :exec
INSERT INTO analyte_analyses (profile_id, analyte_id, content, result_count, generated_at)
VALUES ($1, $2, $3, $4, now())
ON CONFLICT (profile_id, analyte_id) DO UPDATE
SET content = EXCLUDED.content,
    result_count = EXCLUDED.result_count,
    generated_at = now();

-- name: CountResultsForProfileAnalyte :one
SELECT count(*) FROM lab_results
WHERE profile_id = $1 AND analyte_id = $2;
