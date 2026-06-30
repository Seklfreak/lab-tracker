DROP INDEX IF EXISTS idx_body_measurements_external;
ALTER TABLE body_measurements DROP COLUMN external_id;
