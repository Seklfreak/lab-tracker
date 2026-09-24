-- Reports that come from a home device (e.g. a fingerstick lipid meter) rather
-- than an uploaded PDF. They have no PDF and carry the device's stable record id
-- so re-importing is idempotent.
ALTER TABLE lab_reports ALTER COLUMN pdf_object_key DROP NOT NULL;
ALTER TABLE lab_reports ADD COLUMN source text NOT NULL DEFAULT 'pdf'
    CHECK (source IN ('pdf', 'device'));
ALTER TABLE lab_reports ADD COLUMN external_id text;

-- A PDF report always has its object; a device report never does.
ALTER TABLE lab_reports ADD CONSTRAINT lab_reports_source_pdf
    CHECK ((source = 'pdf') = (pdf_object_key IS NOT NULL));

-- Unique per (profile, source, external_id), like body_measurements. NULLs are
-- distinct, so PDF reports (external_id NULL) are unconstrained. Dedup across a
-- user's other profiles is enforced by the import handler.
CREATE UNIQUE INDEX idx_lab_reports_external
    ON lab_reports (profile_id, source, external_id);
