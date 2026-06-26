-- name: UpsertUser :one
-- Called on every authenticated request from the JWT's sub/email/name. The sub
-- is the stable identity; email/name are refreshed and last_seen_at bumped.
INSERT INTO users (oidc_sub, email, name, last_seen_at)
VALUES ($1, $2, $3, now())
ON CONFLICT (oidc_sub) DO UPDATE
SET email = EXCLUDED.email,
    name = EXCLUDED.name,
    last_seen_at = now()
RETURNING *;

-- name: GetUserBySub :one
SELECT * FROM users WHERE oidc_sub = $1;

-- name: GetUser :one
SELECT * FROM users WHERE id = $1;

-- name: GetUserByEmail :one
-- Used when sharing a profile by email. Case-insensitive; the user must have
-- signed in at least once (so a row exists) to be a share target.
SELECT * FROM users WHERE lower(email) = lower($1);

-- name: ListUsersWithProfileCounts :many
-- Admin view: every user with how many profiles they own and how many are
-- shared with them.
SELECT u.id, u.email, u.name, u.oidc_sub, u.created_at, u.last_seen_at,
       (SELECT count(*) FROM profiles p WHERE p.owner_user_id = u.id)::int AS owned_count,
       (SELECT count(*) FROM profile_members m WHERE m.user_id = u.id)::int AS shared_count
FROM users u
ORDER BY u.created_at;
