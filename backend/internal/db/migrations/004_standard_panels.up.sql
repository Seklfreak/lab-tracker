-- Standard CBC-with-differential, hepatic, thyroid, urinalysis, and serology
-- analytes commonly present on Quest/LabCorp comprehensive panels.
INSERT INTO analytes (name, default_unit, category) VALUES
    -- Thyroid / metabolic / liver additions
    ('T3, Total',                  'ng/dL',     'Thyroid'),
    ('Uric Acid',                  'mg/dL',     'Metabolic'),
    ('Globulin',                   'g/dL',      'Liver'),
    ('Albumin/Globulin Ratio',     'ratio',     'Liver'),
    -- CBC red-cell indices
    ('MCV',                        'fL',        'Hematology'),
    ('MCH',                        'pg',        'Hematology'),
    ('MCHC',                       'g/dL',      'Hematology'),
    ('RDW',                        '%',         'Hematology'),
    ('MPV',                        'fL',        'Hematology'),
    -- CBC differential (relative %)
    ('Neutrophils',                '%',         'Hematology'),
    ('Lymphocytes',                '%',         'Hematology'),
    ('Monocytes',                  '%',         'Hematology'),
    ('Eosinophils',                '%',         'Hematology'),
    ('Basophils',                  '%',         'Hematology'),
    -- CBC differential (absolute counts)
    ('Absolute Neutrophils',       'cells/uL',  'Hematology'),
    ('Absolute Lymphocytes',       'cells/uL',  'Hematology'),
    ('Absolute Monocytes',         'cells/uL',  'Hematology'),
    ('Absolute Eosinophils',       'cells/uL',  'Hematology'),
    ('Absolute Basophils',         'cells/uL',  'Hematology'),
    -- Serology / infectious disease (qualitative)
    ('Hepatitis C Antibody',           NULL, 'Serology'),
    ('Hepatitis B Surface Antibody',   NULL, 'Serology'),
    ('Hepatitis B Surface Antigen',    NULL, 'Serology'),
    ('Hepatitis A Antibody, Total',    NULL, 'Serology'),
    ('Hepatitis A IgM',                NULL, 'Serology'),
    ('HIV Ag/Ab, 4th Gen',             NULL, 'Serology'),
    ('RPR',                            NULL, 'Serology'),
    ('Chlamydia trachomatis RNA',      NULL, 'Serology'),
    ('Neisseria gonorrhoeae RNA',      NULL, 'Serology'),
    -- Urinalysis (named distinctly to avoid colliding with chemistry analytes)
    ('Urine Color',                NULL, 'Urinalysis'),
    ('Urine Appearance',           NULL, 'Urinalysis'),
    ('Specific Gravity',           NULL, 'Urinalysis'),
    ('Urine pH',                   NULL, 'Urinalysis'),
    ('Nitrite',                    NULL, 'Urinalysis'),
    ('Leukocyte Esterase',         NULL, 'Urinalysis'),
    ('Urine Occult Blood',         NULL, 'Urinalysis')
ON CONFLICT (name) DO NOTHING;

-- Aliases for printed forms that differ from the canonical name.
INSERT INTO analyte_aliases (analyte_id, raw_name)
SELECT a.id, v.raw_name
FROM (VALUES
    ('Albumin/Globulin Ratio',         'A/G Ratio'),
    ('Hepatitis B Surface Antibody',   'Hepatitis B Surface Antibody QL'),
    ('Hepatitis B Surface Antibody',   'Hep B Surface Ab'),
    ('Hepatitis B Surface Antigen',    'Hep B Surface Ag'),
    ('Hepatitis A Antibody, Total',    'Hepatitis A Ab, Total'),
    ('Hepatitis C Antibody',           'Hep C Ab'),
    ('RPR',                            'RPR (DX) W/Refl Titer and Confirmatory Testing'),
    ('RPR',                            'RPR (Diagnosis)'),
    ('Chlamydia trachomatis RNA',      'Chlamydia trachomatis RNA, TMA, Urogenital'),
    ('Neisseria gonorrhoeae RNA',      'Neisseria gonorrhoeae RNA, TMA, Urogenital'),
    ('Urine Color',                    'Color'),
    ('Urine Appearance',               'Appearance'),
    ('Urine pH',                       'pH'),
    ('Urine Occult Blood',             'Occult Blood'),
    ('Urine Occult Blood',             'Blood')
) AS v(analyte_name, raw_name)
JOIN analytes a ON a.name = v.analyte_name
ON CONFLICT (raw_name) DO NOTHING;
