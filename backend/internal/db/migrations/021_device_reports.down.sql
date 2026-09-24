DELETE FROM lab_reports WHERE source = 'device';
DROP INDEX IF EXISTS idx_lab_reports_external;
ALTER TABLE lab_reports DROP CONSTRAINT IF EXISTS lab_reports_source_pdf;
ALTER TABLE lab_reports DROP COLUMN IF EXISTS external_id;
ALTER TABLE lab_reports DROP COLUMN IF EXISTS source;
ALTER TABLE lab_reports ALTER COLUMN pdf_object_key SET NOT NULL;
