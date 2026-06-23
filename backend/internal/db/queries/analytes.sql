-- name: ListAnalytes :many
SELECT * FROM analytes
ORDER BY category NULLS LAST, name;

-- name: GetAnalyte :one
SELECT * FROM analytes
WHERE id = $1;

-- name: CreateAnalyte :one
INSERT INTO analytes (name, default_unit, category)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetAnalyteByName :one
SELECT * FROM analytes
WHERE lower(btrim(name)) = lower(btrim($1))
LIMIT 1;

-- name: GetAliasByRawName :one
SELECT a.* FROM analytes a
JOIN analyte_aliases al ON al.analyte_id = a.id
WHERE lower(btrim(al.raw_name)) = lower(btrim($1))
LIMIT 1;

-- name: MatchAliasBySpecimen :one
SELECT a.* FROM analytes a
JOIN analyte_aliases al ON al.analyte_id = a.id
WHERE lower(btrim(al.raw_name)) = lower(btrim(@raw_name))
  AND (
    (@want_urine::bool AND 'urine' = ANY(COALESCE(a.specimens, '{}')))
    OR (NOT @want_urine::bool AND NOT ('urine' = ANY(COALESCE(a.specimens, '{}'))))
  )
LIMIT 1;

-- name: MatchAnalyteBySpecimen :one
SELECT * FROM analytes
WHERE lower(btrim(name)) = lower(btrim(@name))
  AND (
    (@want_urine::bool AND 'urine' = ANY(COALESCE(specimens, '{}')))
    OR (NOT @want_urine::bool AND NOT ('urine' = ANY(COALESCE(specimens, '{}'))))
  )
LIMIT 1;

-- name: UpsertAlias :exec
INSERT INTO analyte_aliases (analyte_id, raw_name)
VALUES ($1, $2)
ON CONFLICT (raw_name) DO NOTHING;

-- name: ListAnalytesWithDataForProfile :many
SELECT DISTINCT a.* FROM analytes a
JOIN lab_results r ON r.analyte_id = a.id
WHERE r.profile_id = $1
ORDER BY a.category NULLS LAST, a.name;
