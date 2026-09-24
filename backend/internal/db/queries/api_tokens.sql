-- name: CreateAPIToken :one
INSERT INTO api_tokens (user_id, name, token_hash, token_prefix)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: GetActiveAPITokenByHash :one
-- The token's owner, if the token exists and hasn't been revoked.
SELECT t.id AS token_id, u.*
FROM api_tokens t
JOIN users u ON u.id = t.user_id
WHERE t.token_hash = $1 AND t.revoked_at IS NULL;

-- name: TouchAPIToken :exec
UPDATE api_tokens SET last_used_at = now()
WHERE id = $1;

-- name: ListAPITokensForUser :many
SELECT * FROM api_tokens
WHERE user_id = $1 AND revoked_at IS NULL
ORDER BY created_at DESC;

-- name: RevokeAPIToken :execrows
UPDATE api_tokens SET revoked_at = now()
WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL;
