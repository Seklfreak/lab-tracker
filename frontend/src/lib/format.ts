import type { Result } from "./api";

export function displayValue(r: Pick<Result, "valueText" | "valueNumeric">): string {
  if (r.valueText && r.valueText.trim() !== "") return r.valueText;
  if (r.valueNumeric !== null) return String(r.valueNumeric);
  return "—";
}

export type Tone = "good" | "warn" | "bad" | "muted";

const normalizeQual = (s: string) => s.trim().toLowerCase().replace(/[\s_-]+/g, " ");

// statusTone returns "bad" when a result is out of range: for numeric results,
// outside the reference band; for qualitative results (e.g. "Negative"),
// different from the expected reference value. "warn" if only a lab flag is
// present, "good" if in range, "muted" if undeterminable.
export function statusTone(r: Result): Tone {
  if (r.valueNumeric !== null) {
    if (r.referenceLow !== null && r.valueNumeric < r.referenceLow) return "bad";
    if (r.referenceHigh !== null && r.valueNumeric > r.referenceHigh) return "bad";
    if (r.referenceLow !== null || r.referenceHigh !== null) return "good";
  } else if (r.valueText && r.referenceText) {
    return normalizeQual(r.valueText) === normalizeQual(r.referenceText) ? "good" : "bad";
  }
  if (r.flag && r.flag.trim() !== "") return "warn";
  return "muted";
}

export function referenceLabel(r: Pick<Result, "referenceLow" | "referenceHigh" | "referenceText">): string | null {
  if (r.referenceText && r.referenceText.trim() !== "") return r.referenceText;
  if (r.referenceLow !== null && r.referenceHigh !== null)
    return `${r.referenceLow}–${r.referenceHigh}`;
  if (r.referenceHigh !== null) return `< ${r.referenceHigh}`;
  if (r.referenceLow !== null) return `> ${r.referenceLow}`;
  return null;
}
