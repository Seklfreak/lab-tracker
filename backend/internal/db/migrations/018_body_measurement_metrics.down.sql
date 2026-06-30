ALTER TABLE body_measurements DROP COLUMN value2;
ALTER TABLE body_measurements DROP CONSTRAINT body_measurements_kind_check;
ALTER TABLE body_measurements ADD CONSTRAINT body_measurements_kind_check
    CHECK (kind IN ('weight', 'height'));
