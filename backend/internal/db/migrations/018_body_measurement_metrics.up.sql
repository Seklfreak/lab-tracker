-- Expand body metrics beyond weight/height: vitals + body composition, mostly
-- imported from Apple Health. blood_pressure stores systolic in `value` and
-- diastolic in the new `value2`; every other kind is scalar (value2 NULL).
ALTER TABLE body_measurements DROP CONSTRAINT body_measurements_kind_check;
ALTER TABLE body_measurements ADD CONSTRAINT body_measurements_kind_check
    CHECK (kind IN ('weight', 'height', 'body_fat', 'resting_heart_rate',
                    'waist', 'vo2max', 'oxygen', 'blood_pressure'));

ALTER TABLE body_measurements ADD COLUMN value2 double precision;
