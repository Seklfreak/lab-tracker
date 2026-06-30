-- Self-entered body metrics (weight, height) tracked over time, per profile.
-- Canonical units: weight in kilograms, height in centimetres — the UI converts
-- for display. Powers BMI and personalizes the AI analysis.
CREATE TABLE body_measurements (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id  uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    kind        text NOT NULL CHECK (kind IN ('weight', 'height')),
    value       double precision NOT NULL CHECK (value > 0),
    measured_on date NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_body_measurements_profile
    ON body_measurements (profile_id, kind, measured_on DESC);
