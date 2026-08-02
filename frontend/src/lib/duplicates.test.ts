import { describe, expect, it } from "vitest";
import { findDuplicateGroups, pairKey, type DuplicateGroup } from "./duplicates";
import type { Result } from "./api";

// Minimal Result factory — only the fields the heuristic reads.
function a(id: string, analyteName: string, category: string | null = null): Result {
  return {
    id: `res-${id}`, reportId: "r", analyteId: id, analyteName, category,
    rawTestName: analyteName, valueText: null, valueNumeric: 1, unit: null,
    referenceLow: null, referenceHigh: null, referenceText: null, note: null,
    observedDate: "2026-01-01", sourceLab: null,
  };
}

const names = (g: DuplicateGroup) => g.analytes.map((x) => x.name);

describe("findDuplicateGroups", () => {
  it("groups a marker with its qualified variant", () => {
    const groups = findDuplicateGroups([a("1", "Glucose"), a("2", "Glucose, Fasting")]);
    expect(groups).toHaveLength(1);
    expect(names(groups[0])).toEqual(["Glucose", "Glucose, Fasting"]);
  });

  it("groups a subset name that shares the lead token and category", () => {
    const groups = findDuplicateGroups([
      a("1", "Vitamin D", "Vitamins"),
      a("2", "Vitamin D, 25-Hydroxy", "Vitamins"),
    ]);
    expect(groups).toHaveLength(1);
  });

  it("does not flag genuinely different markers that share a prefix", () => {
    // Vitamin B vs Vitamin B12 are different vitamins — must not merge.
    expect(findDuplicateGroups([a("1", "Vitamin B", "Vitamins"), a("2", "Vitamin B12", "Vitamins")])).toEqual([]);
    // Different markers entirely.
    expect(findDuplicateGroups([a("1", "Sodium"), a("2", "Potassium")])).toEqual([]);
  });

  it("ignores a subset match across different categories", () => {
    expect(findDuplicateGroups([a("1", "Cortisol", "Hormones"), a("2", "Cortisol, Free", "Urine")])).toEqual([]);
  });

  it("returns nothing for a single analyte", () => {
    expect(findDuplicateGroups([a("1", "Glucose")])).toEqual([]);
  });

  it("suppresses a group whose pair is ignored", () => {
    const results = [a("1", "Glucose"), a("2", "Glucose, Fasting")];
    expect(findDuplicateGroups(results)).toHaveLength(1);
    const ignored = new Set([pairKey("1", "2")]);
    expect(findDuplicateGroups(results, ignored)).toEqual([]);
  });
});
