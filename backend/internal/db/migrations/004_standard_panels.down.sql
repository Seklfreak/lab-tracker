DELETE FROM analyte_aliases WHERE raw_name IN (
    'A/G Ratio', 'Hepatitis B Surface Antibody QL', 'Hep B Surface Ab',
    'Hep B Surface Ag', 'Hepatitis A Ab, Total', 'Hep C Ab',
    'RPR (DX) W/Refl Titer and Confirmatory Testing', 'RPR (Diagnosis)',
    'Chlamydia trachomatis RNA, TMA, Urogenital',
    'Neisseria gonorrhoeae RNA, TMA, Urogenital',
    'Color', 'Appearance', 'pH', 'Occult Blood', 'Blood'
);
DELETE FROM analytes WHERE name IN (
    'T3, Total', 'Uric Acid', 'Globulin', 'Albumin/Globulin Ratio',
    'MCV', 'MCH', 'MCHC', 'RDW', 'MPV',
    'Neutrophils', 'Lymphocytes', 'Monocytes', 'Eosinophils', 'Basophils',
    'Absolute Neutrophils', 'Absolute Lymphocytes', 'Absolute Monocytes',
    'Absolute Eosinophils', 'Absolute Basophils',
    'Hepatitis C Antibody', 'Hepatitis B Surface Antibody',
    'Hepatitis B Surface Antigen', 'Hepatitis A Antibody, Total',
    'Hepatitis A IgM', 'HIV Ag/Ab, 4th Gen', 'RPR',
    'Chlamydia trachomatis RNA', 'Neisseria gonorrhoeae RNA',
    'Urine Color', 'Urine Appearance', 'Specific Gravity', 'Urine pH',
    'Nitrite', 'Leukocyte Esterase', 'Urine Occult Blood'
);
