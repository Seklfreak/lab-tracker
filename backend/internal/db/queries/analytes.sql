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

-- name: CountResultsForAnalyte :one
SELECT count(*) FROM lab_results WHERE analyte_id = $1;

-- Merge steps: fold one or more source analytes into a target. Run in order,
-- inside a transaction (see mergeAnalytes).

-- name: RepointResultsToAnalyte :exec
UPDATE lab_results SET analyte_id = @target
WHERE analyte_id = ANY(@sources::uuid[]);

-- name: RepointAliasesToAnalyte :exec
UPDATE analyte_aliases SET analyte_id = @target
WHERE analyte_id = ANY(@sources::uuid[]);

-- name: AddAnalyteNamesAsAliases :exec
-- Keep the merged-away names as aliases so future uploads map to the target.
INSERT INTO analyte_aliases (analyte_id, raw_name)
SELECT @target, name FROM analytes WHERE id = ANY(@sources::uuid[])
ON CONFLICT (raw_name) DO NOTHING;

-- name: MigrateFavoritesToAnalyte :exec
INSERT INTO favorites (profile_id, analyte_id)
SELECT profile_id, @target FROM favorites WHERE analyte_id = ANY(@sources::uuid[])
ON CONFLICT DO NOTHING;

-- name: DeleteAnalytes :exec
-- Sources must no longer be referenced by lab_results (RESTRICT); aliases were
-- repointed, and remaining favorites/analyses for the sources cascade away here.
DELETE FROM analytes WHERE id = ANY(@sources::uuid[]);
