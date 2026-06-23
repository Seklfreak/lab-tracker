-- Common immune-status / titer serologies (named close to the printed Quest
-- forms so case-insensitive matching maps them without aliases).
INSERT INTO analytes (name, default_unit, category, specimens) VALUES
    ('Measles AB (IgG), Immune Status',       'AU/mL',  'Serology', ARRAY['serum']),
    ('Mumps Virus AB (IgG), Immune Status',   'AU/mL',  'Serology', ARRAY['serum']),
    ('Rubella AB (IgG), Immune Status',       'Index',  'Serology', ARRAY['serum']),
    ('Varicella Zoster Virus Antibody (IgG)', 'Index',  'Serology', ARRAY['serum']),
    ('Hepatitis B Surface AB Immunity, QN',   'mIU/mL', 'Serology', ARRAY['serum'])
ON CONFLICT (name) DO NOTHING;

INSERT INTO analyte_aliases (analyte_id, raw_name)
SELECT a.id, v.raw_name
FROM (VALUES
    ('Varicella Zoster Virus Antibody (IgG)', 'Varicella-Zoster Virus AB (IgG)'),
    ('Hepatitis B Surface AB Immunity, QN',   'Hepatitis B Surface Antibody, Quantitative')
) AS v(analyte_name, raw_name)
JOIN analytes a ON a.name = v.analyte_name
ON CONFLICT (raw_name) DO NOTHING;
