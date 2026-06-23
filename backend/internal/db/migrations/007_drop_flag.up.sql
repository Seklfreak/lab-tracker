-- The H/L/abnormal flag is derivable from value vs reference, so don't store it.
ALTER TABLE lab_results DROP COLUMN flag;
