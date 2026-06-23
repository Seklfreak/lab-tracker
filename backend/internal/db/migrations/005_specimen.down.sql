DELETE FROM analyte_aliases WHERE raw_name IN (
    'Glucose', 'Protein', 'Bilirubin', 'Ketones', 'Urobilinogen'
);
DELETE FROM analytes WHERE name IN (
    'Urine Glucose', 'Urine Protein', 'Urine Bilirubin',
    'Urine Ketones', 'Urine Urobilinogen'
);
ALTER TABLE analytes DROP COLUMN specimen;
