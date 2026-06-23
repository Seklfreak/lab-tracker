-- name: AddFavorite :exec
INSERT INTO favorites (profile_id, analyte_id)
VALUES ($1, $2)
ON CONFLICT (profile_id, analyte_id) DO NOTHING;

-- name: RemoveFavorite :exec
DELETE FROM favorites
WHERE profile_id = $1 AND analyte_id = $2;
