-- name: ListBodyMeasurements :many
SELECT * FROM body_measurements
WHERE profile_id = $1
ORDER BY measured_on DESC, created_at DESC;

-- name: AddBodyMeasurement :one
INSERT INTO body_measurements (profile_id, kind, value, measured_on, source)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: DeleteBodyMeasurement :exec
DELETE FROM body_measurements
WHERE id = $1 AND profile_id = $2;
