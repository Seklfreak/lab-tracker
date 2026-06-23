-- name: ListProfiles :many
SELECT * FROM profiles
ORDER BY name;

-- name: GetProfile :one
SELECT * FROM profiles
WHERE id = $1;

-- name: CreateProfile :one
INSERT INTO profiles (name, date_of_birth)
VALUES ($1, $2)
RETURNING *;

-- name: DeleteProfile :exec
DELETE FROM profiles
WHERE id = $1;
