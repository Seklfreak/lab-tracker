-- Where a body measurement came from: 'manual' (typed in), 'apple_health',
-- etc. Free text with a default so existing rows backfill to manual; future
-- integrations (HealthKit) stamp their own source.
ALTER TABLE body_measurements ADD COLUMN source text NOT NULL DEFAULT 'manual';
