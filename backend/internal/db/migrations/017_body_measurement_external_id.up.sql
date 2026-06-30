-- Stable id of the source record (e.g. a HealthKit sample UUID) so re-importing
-- from Apple Health is idempotent. NULL for manual entries.
ALTER TABLE body_measurements ADD COLUMN external_id text;

-- Unique per (profile, source, external_id). NULLs are distinct in a unique
-- index, so manual entries (external_id NULL) are unconstrained; only imported
-- rows with a real external_id are deduped.
CREATE UNIQUE INDEX idx_body_measurements_external
    ON body_measurements (profile_id, source, external_id);
