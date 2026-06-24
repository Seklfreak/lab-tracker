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

// parseBounded extracts a leading comparison operator + number from a value like
// "<0.05" or ">90". Returns null for plain or non-numeric values.
function parseBounded(s: string): { op: "<" | ">"; num: number } | null {
  const m = s.trim().match(/^([<>]=?|≤|≥)\s*(-?\d+(?:\.\d+)?)/);
  if (!m) return null;
  const num = parseFloat(m[2]);
  if (!Number.isFinite(num)) return null;
  return { op: m[1][0] === "<" || m[1] === "≤" ? "<" : ">", num };
}

// evaluateRange returns "L"/"H" when out of range, "ok" when in range against a
// numeric reference, or null when it can't be decided numerically. Handles plain
// numeric values and bounded values ("<0.05", ">90").
function evaluateRange(r: Result): "L" | "H" | "ok" | null {
  const hasRef = r.referenceLow !== null || r.referenceHigh !== null;
  if (r.valueNumeric !== null) {
    if (r.referenceLow !== null && r.valueNumeric < r.referenceLow) return "L";
    if (r.referenceHigh !== null && r.valueNumeric > r.referenceHigh) return "H";
    return hasRef ? "ok" : null;
  }
  const b = r.valueText ? parseBounded(r.valueText) : null;
  if (b && hasRef) {
    // "<x": the value is below x. Only "low" if x is at/below the lower bound.
    if (b.op === "<") return r.referenceLow !== null && b.num <= r.referenceLow ? "L" : "ok";
    // ">x": the value is above x. Only "high" if x is at/above the upper bound.
    return r.referenceHigh !== null && b.num >= r.referenceHigh ? "H" : "ok";
  }
  return null;
}

// statusTone returns "bad" when a result is out of range: for numeric/bounded
// results, outside the reference band; for qualitative results (e.g. "Negative"),
// different from the expected reference value. "good" if in range, "muted" if
// undeterminable.
export function statusTone(r: Result): Tone {
  const range = evaluateRange(r);
  if (range === "L" || range === "H") return "bad";
  if (range === "ok") return "good";
  if (r.valueText && r.referenceText) {
    return normalizeQual(r.valueText) === normalizeQual(r.referenceText) ? "good" : "bad";
  }
  return "muted";
}

// derivedFlag computes the H/L/Abnormal flag from value vs reference (we don't
// store the lab's printed flag). Returns null when in range or undeterminable.
export function derivedFlag(r: Result): string | null {
  const range = evaluateRange(r);
  if (range === "L") return "L";
  if (range === "H") return "H";
  if (range === "ok") return null;
  if (r.valueText && r.referenceText) {
    return normalizeQual(r.valueText) === normalizeQual(r.referenceText) ? null : "Abnormal";
  }
  return null;
}

// plotPoint maps a result to a chart point. Plain numbers plot as-is; bounded
// values ("<x" / ">x") plot at their threshold with an error whisker covering
// the range the true value could lie in (e.g. "<0.05" → from refLow/0 up to
// 0.05). Returns null for non-plottable (purely qualitative) results.
export function plotPoint(
  r: Pick<Result, "valueNumeric" | "valueText" | "referenceLow" | "referenceHigh">,
): { value: number; err: [number, number] } | null {
  if (r.valueNumeric !== null) return { value: r.valueNumeric, err: [0, 0] };
  const b = r.valueText ? parseBounded(r.valueText) : null;
  if (!b) return null;
  if (b.op === "<") {
    const low = r.referenceLow ?? 0;
    return { value: b.num, err: [Math.max(0, b.num - low), 0] };
  }
  const high = r.referenceHigh;
  return { value: b.num, err: [0, high !== null && high > b.num ? high - b.num : 0] };
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
