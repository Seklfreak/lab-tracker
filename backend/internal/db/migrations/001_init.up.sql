CREATE TABLE profiles (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name          text NOT NULL,
    date_of_birth date,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE analytes (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name         text NOT NULL UNIQUE,
    default_unit text,
    loinc        text,
    category     text,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE analyte_aliases (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analyte_id uuid NOT NULL REFERENCES analytes (id) ON DELETE CASCADE,
    raw_name   text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE lab_reports (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id        uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    pdf_object_key    text NOT NULL,
    original_filename text,
    source_lab        text,
    collected_date    date,
    reported_date     date,
    status            text NOT NULL DEFAULT 'parsing',
    parse_error       text,
    parsed_draft      jsonb,
    created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_lab_reports_profile ON lab_reports (profile_id, created_at DESC);

CREATE TABLE lab_results (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id       uuid NOT NULL REFERENCES lab_reports (id) ON DELETE CASCADE,
    profile_id      uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    analyte_id      uuid NOT NULL REFERENCES analytes (id) ON DELETE RESTRICT,
    raw_test_name   text NOT NULL,
    value_text      text,
    value_numeric   double precision,
    unit            text,
    reference_low   double precision,
    reference_high  double precision,
    reference_text  text,
    flag            text,
    observed_date   date NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_lab_results_trend ON lab_results (profile_id, analyte_id, observed_date);
