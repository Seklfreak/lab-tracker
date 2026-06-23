-- Additional common Quest/LabCorp panel members and name variants.
INSERT INTO analytes (name, default_unit, category) VALUES
    ('Non-HDL Cholesterol',   'mg/dL', 'Lipids'),
    ('Cholesterol/HDL Ratio', 'ratio', 'Lipids'),
    ('BUN/Creatinine Ratio',  'ratio', 'Metabolic')
ON CONFLICT (name) DO NOTHING;

INSERT INTO analyte_aliases (analyte_id, raw_name)
SELECT a.id, v.raw_name
FROM (VALUES
    ('LDL Cholesterol',        'LDL-Cholesterol'),
    ('LDL Cholesterol',        'LDL Chol Calc (NIH)'),
    ('Non-HDL Cholesterol',    'Non HDL Cholesterol'),
    ('Cholesterol/HDL Ratio',  'Chol/HDLc Ratio'),
    ('Cholesterol/HDL Ratio',  'Chol/HDL Ratio'),
    ('BUN/Creatinine Ratio',   'BUN/Creatinine Ratio'),
    ('Carbon Dioxide',         'Carbon Dioxide, Total'),
    ('eGFR',                   'eGFR (Non-African American)')
) AS v(analyte_name, raw_name)
JOIN analytes a ON a.name = v.analyte_name
ON CONFLICT (raw_name) DO NOTHING;
