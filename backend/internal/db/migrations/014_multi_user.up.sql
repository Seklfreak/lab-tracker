-- Multi-user: per-user ownership of profiles, with sharing for households.
-- A user is keyed on their OIDC `sub` (upserted from the JWT on each request).
CREATE TABLE users (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    oidc_sub     text NOT NULL UNIQUE,
    email        text,
    name         text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now()
);

-- Every profile has an owner. Nullable here so the column can be added without a
-- default; existing rows are backfilled to the admin user at startup
-- (see db.BootstrapOwners), and new profiles always set it in application code.
ALTER TABLE profiles ADD COLUMN owner_user_id uuid REFERENCES users (id) ON DELETE CASCADE;
CREATE INDEX idx_profiles_owner ON profiles (owner_user_id);

-- Shared access: a profile can be shared with other users, who can co-edit.
-- The owner (profiles.owner_user_id) is implicit and not stored here.
CREATE TABLE profile_members (
    profile_id uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role       text NOT NULL DEFAULT 'editor',
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (profile_id, user_id)
);

CREATE INDEX idx_profile_members_user ON profile_members (user_id);
