// Unit normalization for lab values. Two kinds of conversions:
//  - scale-only (SI prefix / volume), safe for any analyte (pure powers of ten);
//  - molar (mg/dL <-> mmol/L or µmol/L), which depend on the substance's molar
//    mass and are therefore keyed per analyte with vetted factors.
// unitFactor() returns the multiplicative factor to convert a value from one unit
// to another, or null when there's no vetted conversion (caller leaves it as-is).
// Conversions are linear through the origin, so a single factor suffices and also
// scales any error/whisker bounds.

const n = (u: string | null | undefined): string =>
  (u ?? "").trim().toLowerCase().replace(/\s+/g, "");

type Dim = "massvol" | "molar";

// Each scale unit expressed against a base (g/L for mass/volume, mol/L for molarity).
const SCALE: Record<string, { dim: Dim; base: number }> = {
  "g/l": { dim: "massvol", base: 1 },
  "g/dl": { dim: "massvol", base: 10 },
  "mg/l": { dim: "massvol", base: 1e-3 },
  "mg/dl": { dim: "massvol", base: 1e-2 },
  "µg/dl": { dim: "massvol", base: 1e-5 },
  "ug/dl": { dim: "massvol", base: 1e-5 },
  "µg/l": { dim: "massvol", base: 1e-6 },
  "ug/l": { dim: "massvol", base: 1e-6 },
  "mol/l": { dim: "molar", base: 1 },
  "mmol/l": { dim: "molar", base: 1e-3 },
  "µmol/l": { dim: "molar", base: 1e-6 },
  "umol/l": { dim: "molar", base: 1e-6 },
  "nmol/l": { dim: "molar", base: 1e-9 },
};

// Analyte-specific molar conversions (mg/dL -> mmol/L or µmol/L).
const MOLAR: { match: RegExp; from: string; to: string; factor: number }[] = [
  { match: /glucose/, from: "mg/dl", to: "mmol/l", factor: 0.0555 },
  { match: /cholesterol|hdl|ldl/, from: "mg/dl", to: "mmol/l", factor: 0.02586 },
  { match: /triglyceride/, from: "mg/dl", to: "mmol/l", factor: 0.01129 },
  { match: /creatinine/, from: "mg/dl", to: "umol/l", factor: 88.42 },
  { match: /urea|bun/, from: "mg/dl", to: "mmol/l", factor: 0.357 },
  { match: /calcium/, from: "mg/dl", to: "mmol/l", factor: 0.2495 },
  { match: /uric acid|urate/, from: "mg/dl", to: "umol/l", factor: 59.48 },
  { match: /bilirubin/, from: "mg/dl", to: "umol/l", factor: 17.1 },
];

export function unitFactor(
  from: string | null,
  to: string | null,
  analyte?: string,
): number | null {
  const f = n(from);
  const t = n(to);
  if (!f || !t) return null;
  if (f === t) return 1;

  // Scale conversion within the same dimension (analyte-independent).
  const sf = SCALE[f];
  const st = SCALE[t];
  if (sf && st && sf.dim === st.dim) return sf.base / st.base;

  // Molar conversion (substance-specific).
  const name = (analyte ?? "").toLowerCase();
  for (const m of MOLAR) {
    if (!m.match.test(name)) continue;
    if (f === m.from && t === m.to) return m.factor;
    if (f === m.to && t === m.from) return 1 / m.factor;
  }
  return null;
}
