import type { Result } from "./api";

export function displayValue(r: Pick<Result, "valueText" | "valueNumeric">): string {
  if (r.valueText && r.valueText.trim() !== "") return r.valueText;
  if (r.valueNumeric !== null) return String(r.valueNumeric);
  return "—";
}

export type Tone = "good" | "warn" | "bad" | "muted";

// Common qualitative abbreviations, normalized to a canonical form so a value
// matches its (often abbreviated) reference — e.g. "NEGATIVE" vs "NEG".
const QUAL_SYNONYMS: Record<string, string> = {
  neg: "negative",
  pos: "positive",
  nr: "non reactive",
  nonreactive: "non reactive",
  reactive: "reactive",
  nd: "not detected",
  notdetected: "not detected",
  detected: "detected",
};

function normalizeQual(s: string): string {
  const t = s.trim().toLowerCase().replace(/[\s_-]+/g, " ").trim();
  return QUAL_SYNONYMS[t] ?? t;
}

// statusTone returns "bad" when a result is out of range: for numeric results,
// outside the reference band; for qualitative results (e.g. "Negative"),
// different from the expected reference value. "good" if in range, "muted" if
// undeterminable.
export function statusTone(r: Result): Tone {
  if (r.valueNumeric !== null) {
    if (r.referenceLow !== null && r.valueNumeric < r.referenceLow) return "bad";
    if (r.referenceHigh !== null && r.valueNumeric > r.referenceHigh) return "bad";
    if (r.referenceLow !== null || r.referenceHigh !== null) return "good";
  } else if (r.valueText && r.referenceText) {
    return normalizeQual(r.valueText) === normalizeQual(r.referenceText) ? "good" : "bad";
  }
  return "muted";
}

// derivedFlag computes the H/L/Abnormal flag from value vs reference (we don't
// store the lab's printed flag). Returns null when in range or undeterminable.
export function derivedFlag(r: Result): string | null {
  if (r.valueNumeric !== null) {
    if (r.referenceLow !== null && r.valueNumeric < r.referenceLow) return "L";
    if (r.referenceHigh !== null && r.valueNumeric > r.referenceHigh) return "H";
    return null;
  }
  if (r.valueText && r.referenceText) {
    return normalizeQual(r.valueText) === normalizeQual(r.referenceText) ? null : "Abnormal";
  }
  return null;
}

// chartYDomain pads the y-axis to include the data and the reference bounds so
// the in-range/out-of-range zones are fully visible. Falls back to [0, 1] when
// there is nothing to plot.
export function chartYDomain(
  values: number[],
  refLow: number | null,
  refHigh: number | null,
): [number, number] {
  const bounds = [...values];
  if (refLow !== null) bounds.push(refLow);
  if (refHigh !== null) bounds.push(refHigh);
  if (bounds.length === 0) return [0, 1];
  const lo = Math.min(...bounds);
  const hi = Math.max(...bounds);
  const span = hi - lo || Math.abs(hi) || 1;
  const pad = span * 0.15;
  return [lo - pad, hi + pad];
}

export function referenceLabel(r: Pick<Result, "referenceLow" | "referenceHigh" | "referenceText">): string | null {
  if (r.referenceText && r.referenceText.trim() !== "") return r.referenceText;
  if (r.referenceLow !== null && r.referenceHigh !== null)
    return `${r.referenceLow}–${r.referenceHigh}`;
  if (r.referenceHigh !== null) return `< ${r.referenceHigh}`;
  if (r.referenceLow !== null) return `> ${r.referenceLow}`;
  return null;
}
