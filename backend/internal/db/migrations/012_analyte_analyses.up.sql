-- Stored AI analyses, one per (profile, analyte). result_count records how many
-- results the analysis was based on, so we can flag it stale when new ones land.
CREATE TABLE analyte_analyses (
    profile_id   uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    analyte_id   uuid NOT NULL REFERENCES analytes (id) ON DELETE CASCADE,
    content      text NOT NULL,
    result_count integer NOT NULL,
    generated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (profile_id, analyte_id)
);
