ALTER TABLE analytes ADD COLUMN specimen text;
UPDATE analytes SET specimen = specimens[1] WHERE specimens IS NOT NULL;
ALTER TABLE analytes DROP COLUMN specimens;
