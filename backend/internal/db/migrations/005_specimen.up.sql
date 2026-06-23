-- Specimen-aware matching: tag analytes with their specimen so urinalysis
-- dipstick tests (Glucose, Protein, Bilirubin, Ketones) don't collide with the
-- serum chemistry analytes of the same name. NULL = blood/serum/general.
ALTER TABLE analytes ADD COLUMN specimen text;

UPDATE analytes SET specimen = 'urine' WHERE name IN (
    'Urine Color', 'Urine Appearance', 'Specific Gravity', 'Urine pH',
    'Nitrite', 'Leukocyte Esterase', 'Urine Occult Blood'
);

-- Urine variants of dipstick tests whose names collide with chemistry analytes.
INSERT INTO analytes (name, default_unit, category, specimen) VALUES
    ('Urine Glucose',      NULL,    'Urinalysis', 'urine'),
    ('Urine Protein',      NULL,    'Urinalysis', 'urine'),
    ('Urine Bilirubin',    NULL,    'Urinalysis', 'urine'),
    ('Urine Ketones',      NULL,    'Urinalysis', 'urine'),
    ('Urine Urobilinogen', 'mg/dL', 'Urinalysis', 'urine')
ON CONFLICT (name) DO NOTHING;

-- Bare dipstick names map to the urine variants. These only match when the
-- parsed row's specimen is "urine" (see MatchAliasBySpecimen).
INSERT INTO analyte_aliases (analyte_id, raw_name)
SELECT a.id, v.raw_name
FROM (VALUES
    ('Urine Glucose',      'Glucose'),
    ('Urine Protein',      'Protein'),
    ('Urine Bilirubin',    'Bilirubin'),
    ('Urine Ketones',      'Ketones'),
    ('Urine Urobilinogen', 'Urobilinogen')
) AS v(analyte_name, raw_name)
JOIN analytes a ON a.name = v.analyte_name
ON CONFLICT (raw_name) DO NOTHING;
