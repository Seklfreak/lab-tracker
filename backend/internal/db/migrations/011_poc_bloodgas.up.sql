-- Point-of-care, venous blood-gas, cardiac, and lipid/A1c-derived analytes
-- (hospital POC reports). Whole-blood specimen; names match the printed forms
-- case-insensitively.
INSERT INTO analytes (name, default_unit, category, specimens) VALUES
    ('Troponin I POC Result',        'ng/mL',  'Cardiac',       ARRAY['whole blood']),
    ('BNP POC Result',               'pg/mL',  'Cardiac',       ARRAY['whole blood']),
    ('Blood Gas Ven pH POCT',        NULL,     'Blood Gas',     ARRAY['whole blood']),
    ('Blood Gas Ven CO2 POCT',       'mm Hg',  'Blood Gas',     ARRAY['whole blood']),
    ('Blood Gas Ven O2 POCT',        'mm Hg',  'Blood Gas',     ARRAY['whole blood']),
    ('Blood Gas Na POCT',            'mmol/L', 'Blood Gas',     ARRAY['whole blood']),
    ('Blood Gas K POCT',             'mmol/L', 'Blood Gas',     ARRAY['whole blood']),
    ('Blood Gas Ionized Ca POCT',    'mmol/L', 'Blood Gas',     ARRAY['whole blood']),
    ('Blood Gas Gluc POCT',          'mg/dL',  'Blood Gas',     ARRAY['whole blood']),
    ('Blood Gas Lactic POCT',        'mmol/L', 'Blood Gas',     ARRAY['whole blood']),
    ('Blood Gas Ven Bicarb POCT',    'mmol/L', 'Blood Gas',     ARRAY['whole blood']),
    ('Blood Gas Base Excess POCT',   'mmol/L', 'Blood Gas',     ARRAY['whole blood']),
    ('Blood Gas Ven O2 Sat POCT',    '%',      'Blood Gas',     ARRAY['whole blood']),
    ('POC Chloride',                 'mmol/L', 'Point of Care', ARRAY['whole blood']),
    ('POC Creatinine',               'mg/dL',  'Point of Care', ARRAY['whole blood']),
    ('POC BUN',                      'mg/dL',  'Point of Care', ARRAY['whole blood']),
    ('HDL % of Total Cholesterol',   '%',      'Lipids',        ARRAY['whole blood']),
    ('Estimated Avg Glucose (Calc)', 'mg/dL',  'Metabolic',     ARRAY['whole blood'])
ON CONFLICT (name) DO NOTHING;

-- These printed forms are really existing analytes.
INSERT INTO analyte_aliases (analyte_id, raw_name)
SELECT a.id, v.raw_name
FROM (VALUES
    ('Carbon Dioxide',  'Total CO2'),
    ('LDL Cholesterol', 'LDL Cholesterol (Calc)')
) AS v(analyte_name, raw_name)
JOIN analytes a ON a.name = v.analyte_name
ON CONFLICT (raw_name) DO NOTHING;
