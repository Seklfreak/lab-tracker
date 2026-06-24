-- Track when a result last changed so a stored analysis can be flagged stale
-- after edits (not just when the result count changes).
ALTER TABLE lab_results ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
