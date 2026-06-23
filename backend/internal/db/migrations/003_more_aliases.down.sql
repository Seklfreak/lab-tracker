DELETE FROM analyte_aliases WHERE raw_name IN (
    'LDL-Cholesterol', 'LDL Chol Calc (NIH)', 'Non HDL Cholesterol',
    'Chol/HDLc Ratio', 'Chol/HDL Ratio', 'BUN/Creatinine Ratio',
    'Carbon Dioxide, Total', 'eGFR (Non-African American)'
);
DELETE FROM analytes WHERE name IN (
    'Non-HDL Cholesterol', 'Cholesterol/HDL Ratio', 'BUN/Creatinine Ratio'
);
