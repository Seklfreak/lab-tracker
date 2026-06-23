DELETE FROM analyte_aliases WHERE raw_name IN ('Total CO2', 'LDL Cholesterol (Calc)');
DELETE FROM analytes WHERE name IN (
    'Troponin I POC Result', 'BNP POC Result',
    'Blood Gas Ven pH POCT', 'Blood Gas Ven CO2 POCT', 'Blood Gas Ven O2 POCT',
    'Blood Gas Na POCT', 'Blood Gas K POCT', 'Blood Gas Ionized Ca POCT',
    'Blood Gas Gluc POCT', 'Blood Gas Lactic POCT', 'Blood Gas Ven Bicarb POCT',
    'Blood Gas Base Excess POCT', 'Blood Gas Ven O2 Sat POCT',
    'POC Chloride', 'POC Creatinine', 'POC BUN',
    'HDL % of Total Cholesterol', 'Estimated Avg Glucose (Calc)'
);
