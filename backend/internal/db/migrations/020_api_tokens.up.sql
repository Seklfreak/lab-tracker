-- Personal access tokens: long-lived bearer tokens a user creates for scripts
-- and device importers (e.g. curo-l7). Only a SHA-256 of the token is stored;
-- the plaintext is shown once at creation.
CREATE TABLE api_tokens (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name         text NOT NULL,
    token_hash   bytea NOT NULL UNIQUE,
    -- First characters of the token, so the user can tell tokens apart.
    token_prefix text NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz,
    revoked_at   timestamptz
);

CREATE INDEX idx_api_tokens_user ON api_tokens (user_id, created_at DESC);
