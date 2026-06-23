DELETE FROM analyte_aliases WHERE raw_name IN (
    'Varicella-Zoster Virus AB (IgG)', 'Hepatitis B Surface Antibody, Quantitative'
);
DELETE FROM analytes WHERE name IN (
    'Measles AB (IgG), Immune Status', 'Mumps Virus AB (IgG), Immune Status',
    'Rubella AB (IgG), Immune Status', 'Varicella Zoster Virus Antibody (IgG)',
    'Hepatitis B Surface AB Immunity, QN'
);
