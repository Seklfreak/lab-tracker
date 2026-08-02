-- Analyte pairs an admin has marked "not duplicates", so the dashboard's
-- duplicate hint stops suggesting them. Stored canonically (analyte_a < analyte_b)
-- so each unordered pair appears once. Cascades away if either analyte is deleted
-- (e.g. after a merge), which naturally clears now-irrelevant pairs.
CREATE TABLE ignored_analyte_pairs (
    analyte_a  uuid NOT NULL REFERENCES analytes (id) ON DELETE CASCADE,
    analyte_b  uuid NOT NULL REFERENCES analytes (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (analyte_a, analyte_b),
    CHECK (analyte_a < analyte_b)
);
