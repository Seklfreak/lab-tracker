import { describe, expect, it } from "vitest";
import { unitFactor } from "./units";

describe("unitFactor", () => {
  it("returns 1 for identical units (case/space-insensitive)", () => {
    expect(unitFactor("mg/dL", "mg/dl")).toBe(1);
    expect(unitFactor("g/L", " g/l ")).toBe(1);
  });

  it("scales mass/volume units (analyte-independent)", () => {
    expect(unitFactor("g/dL", "g/L")).toBeCloseTo(10);
    expect(unitFactor("g/L", "g/dL")).toBeCloseTo(0.1);
    expect(unitFactor("g/dL", "mg/dL")).toBeCloseTo(1000);
    expect(unitFactor("mg/dL", "µg/dL")).toBeCloseTo(1000);
  });

  it("scales molar units", () => {
    expect(unitFactor("mmol/L", "µmol/L")).toBeCloseTo(1000);
    expect(unitFactor("mmol/L", "umol/L")).toBeCloseTo(1000);
    expect(unitFactor("mol/L", "mmol/L")).toBeCloseTo(1000);
  });

  it("does not cross dimensions without an analyte factor", () => {
    expect(unitFactor("mg/dL", "mmol/L")).toBeNull();
    expect(unitFactor("mg/dL", "mmol/L", "Sodium")).toBeNull();
  });

  it("applies analyte-specific molar conversions both ways", () => {
    expect(unitFactor("mg/dL", "mmol/L", "Glucose")).toBeCloseTo(0.0555);
    expect(unitFactor("mmol/L", "mg/dL", "Glucose")).toBeCloseTo(1 / 0.0555);
    expect(unitFactor("mg/dL", "mmol/L", "Total Cholesterol")).toBeCloseTo(0.02586);
    expect(unitFactor("mg/dL", "umol/L", "Creatinine")).toBeCloseTo(88.42);
  });

  it("returns null for unknown units", () => {
    expect(unitFactor("widgets", "mg/dl")).toBeNull();
    expect(unitFactor("mg/dl", "")).toBeNull();
  });
});
