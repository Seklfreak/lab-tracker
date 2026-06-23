-- An analyte can be valid on more than one specimen (e.g. Glucose on serum or
-- plasma), so replace the single specimen column with a text[] array.
ALTER TABLE analytes ADD COLUMN specimens text[];

-- Carry over the existing single value.
UPDATE analytes SET specimens = ARRAY[specimen] WHERE specimen IS NOT NULL;

-- Backfill typical specimens by category for everything still untagged.
UPDATE analytes SET specimens = ARRAY['whole blood']
    WHERE specimens IS NULL AND category = 'Hematology';
UPDATE analytes SET specimens = ARRAY['serum', 'plasma']
    WHERE specimens IS NULL;

ALTER TABLE analytes DROP COLUMN specimen;
