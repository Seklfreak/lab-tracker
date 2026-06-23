-- Per-profile favorited analytes (pinned on the dashboard).
CREATE TABLE favorites (
    profile_id uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    analyte_id uuid NOT NULL REFERENCES analytes (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (profile_id, analyte_id)
);
