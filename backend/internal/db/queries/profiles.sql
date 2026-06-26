-- name: ListProfilesForUser :many
-- Profiles the user owns or that have been shared with them.
SELECT p.* FROM profiles p
WHERE p.owner_user_id = sqlc.arg(user_id)
   OR EXISTS (
       SELECT 1 FROM profile_members m
       WHERE m.profile_id = p.id AND m.user_id = sqlc.arg(user_id)
   )
ORDER BY p.name;

-- name: GetProfileForUser :one
-- A profile by id, but only if the user owns it or it's shared with them.
-- Returns no rows (treated as 404) otherwise, so existence isn't leaked.
SELECT p.* FROM profiles p
WHERE p.id = sqlc.arg(id)
  AND (
      p.owner_user_id = sqlc.arg(user_id)
      OR EXISTS (
          SELECT 1 FROM profile_members m
          WHERE m.profile_id = p.id AND m.user_id = sqlc.arg(user_id)
      )
  );

-- name: ListProfiles :many
-- Unscoped: every profile. Only the MCP connector uses this, and only when it
-- runs without a configured user (MCP_USER_SUB). The API always scopes by user.
SELECT * FROM profiles
ORDER BY name;

-- name: GetProfile :one
SELECT * FROM profiles
WHERE id = $1;

-- name: CreateProfile :one
INSERT INTO profiles (name, date_of_birth, owner_user_id)
VALUES ($1, $2, $3)
RETURNING *;

-- name: DeleteProfile :exec
DELETE FROM profiles
WHERE id = $1;
