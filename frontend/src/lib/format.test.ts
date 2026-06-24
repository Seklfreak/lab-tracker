import { describe, expect, it } from "vitest";
import type { Result } from "./api";
import {
  chartYDomain,
  derivedFlag,
  displayValue,
  referenceLabel,
  statusTone,
} from "./format";

// Build a Result with sensible defaults; override per test.
function mk(over: Partial<Result>): Result {
  return {
    id: "1",
    reportId: "r1",
    analyteId: "a1",
    analyteName: "Glucose",
    category: "Metabolic",
    rawTestName: "Glucose",
    valueText: null,
    valueNumeric: null,
    unit: "mg/dL",
    referenceLow: null,
    referenceHigh: null,
    referenceText: null,
    note: null,
    observedDate: "2026-01-15",
    sourceLab: null,
    ...over,
  };
}

describe("statusTone", () => {
  it("numeric below low / above high is bad", () => {
    expect(statusTone(mk({ valueNumeric: 50, referenceLow: 70, referenceHigh: 99 }))).toBe("bad");
    expect(statusTone(mk({ valueNumeric: 230, referenceLow: 70, referenceHigh: 99 }))).toBe("bad");
  });
  it("numeric in range is good", () => {
    expect(statusTone(mk({ valueNumeric: 85, referenceLow: 70, referenceHigh: 99 }))).toBe("good");
  });
  it("numeric without a reference is muted", () => {
    expect(statusTone(mk({ valueNumeric: 85 }))).toBe("muted");
  });
  it("one-sided reference works", () => {
    expect(statusTone(mk({ valueNumeric: 200, referenceHigh: 150 }))).toBe("bad");
    expect(statusTone(mk({ valueNumeric: 100, referenceHigh: 150 }))).toBe("good");
  });
  it("qualitative match is good, mismatch is bad", () => {
    expect(statusTone(mk({ valueText: "NON-REACTIVE", referenceText: "Non-Reactive" }))).toBe("good");
    expect(statusTone(mk({ valueText: "REACTIVE", referenceText: "Non-Reactive" }))).toBe("bad");
  });
  it("matches common qualitative abbreviations", () => {
    expect(statusTone(mk({ valueText: "NEGATIVE", referenceText: "NEG" }))).toBe("good");
    expect(statusTone(mk({ valueText: "POSITIVE", referenceText: "POS" }))).toBe("good");
    expect(statusTone(mk({ valueText: "NEGATIVE", referenceText: "NEG" }))).not.toBe("bad");
    expect(derivedFlag(mk({ valueText: "NEGATIVE", referenceText: "NEG" }))).toBeNull();
    // a real mismatch still flags
    expect(statusTone(mk({ valueText: "POSITIVE", referenceText: "NEG" }))).toBe("bad");
  });
  it("evaluates bounded values (<x / >x) against the range", () => {
    // "<0.05" within 0.00–0.05 is in range
    const tni = { valueText: "<0.05", referenceLow: 0, referenceHigh: 0.05 };
    expect(statusTone(mk(tni))).toBe("good");
    expect(derivedFlag(mk(tni))).toBeNull();
    // "<5" below a low bound of 10 is low
    expect(statusTone(mk({ valueText: "<5", referenceLow: 10, referenceHigh: 20 }))).toBe("bad");
    expect(derivedFlag(mk({ valueText: "<5", referenceLow: 10, referenceHigh: 20 }))).toBe("L");
    // ">200" above a high bound of 150 is high
    expect(derivedFlag(mk({ valueText: ">200", referenceHigh: 150 }))).toBe("H");
    // ">90" with only a low bound is in range
    expect(statusTone(mk({ valueText: ">90", referenceLow: 60 }))).toBe("good");
  });
  it("qualitative without a reference is muted", () => {
    expect(statusTone(mk({ valueText: "NEGATIVE" }))).toBe("muted");
  });
});

describe("derivedFlag", () => {
  it("flags numeric L / H", () => {
    expect(derivedFlag(mk({ valueNumeric: 50, referenceLow: 70, referenceHigh: 99 }))).toBe("L");
    expect(derivedFlag(mk({ valueNumeric: 230, referenceLow: 70, referenceHigh: 99 }))).toBe("H");
    expect(derivedFlag(mk({ valueNumeric: 85, referenceLow: 70, referenceHigh: 99 }))).toBeNull();
  });
  it("flags qualitative Abnormal on mismatch", () => {
    expect(derivedFlag(mk({ valueText: "REACTIVE", referenceText: "Non-Reactive" }))).toBe("Abnormal");
    expect(derivedFlag(mk({ valueText: "NEGATIVE", referenceText: "Negative" }))).toBeNull();
  });
  it("returns null without a reference", () => {
    expect(derivedFlag(mk({ valueNumeric: 85 }))).toBeNull();
    expect(derivedFlag(mk({ valueText: "NEGATIVE" }))).toBeNull();
  });
});

describe("referenceLabel", () => {
  it("prefers reference text", () => {
    expect(referenceLabel(mk({ referenceText: "Non-Reactive", referenceLow: 1, referenceHigh: 2 }))).toBe(
      "Non-Reactive",
    );
  });
  it("formats numeric bounds", () => {
    expect(referenceLabel(mk({ referenceLow: 70, referenceHigh: 99 }))).toBe("70–99");
    expect(referenceLabel(mk({ referenceHigh: 150 }))).toBe("< 150");
    expect(referenceLabel(mk({ referenceLow: 39 }))).toBe("> 39");
    expect(referenceLabel(mk({}))).toBeNull();
  });
});

describe("displayValue", () => {
  it("prefers text, then numeric, then dash", () => {
    expect(displayValue(mk({ valueText: "NEGATIVE" }))).toBe("NEGATIVE");
    expect(displayValue(mk({ valueNumeric: 95 }))).toBe("95");
    expect(displayValue(mk({}))).toBe("—");
  });
});

describe("chartYDomain", () => {
  it("pads to include data and reference bounds", () => {
    const [lo, hi] = chartYDomain([80, 90, 95], 70, 99);
    // bounds 70..99, span 29, pad 4.35
    expect(lo).toBeCloseTo(65.65, 2);
    expect(hi).toBeCloseTo(103.35, 2);
  });
  it("handles one-sided references", () => {
    const [lo, hi] = chartYDomain([100, 120], null, 150);
    expect(lo).toBeCloseTo(92.5, 2);
    expect(hi).toBeCloseTo(157.5, 2);
  });
  it("falls back to [0,1] with no data", () => {
    expect(chartYDomain([], null, null)).toEqual([0, 1]);
  });
  it("pads a single flat value", () => {
    const [lo, hi] = chartYDomain([50], null, null);
    expect(lo).toBeCloseTo(42.5, 2);
    expect(hi).toBeCloseTo(57.5, 2);
  });
});
