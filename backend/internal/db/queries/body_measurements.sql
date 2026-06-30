-- name: ListBodyMeasurements :many
SELECT * FROM body_measurements
WHERE profile_id = $1
ORDER BY measured_on DESC, created_at DESC;

-- name: AddBodyMeasurement :one
-- Upsert: a row with a real external_id re-imported from the same source updates
-- in place (idempotent); manual rows (external_id NULL) never conflict, so they
-- always insert.
INSERT INTO body_measurements (profile_id, kind, value, measured_on, source, external_id)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (profile_id, source, external_id) DO UPDATE
  SET value = EXCLUDED.value, measured_on = EXCLUDED.measured_on
RETURNING *;

-- name: DeleteBodyMeasurement :exec
DELETE FROM body_measurements
WHERE id = $1 AND profile_id = $2;
