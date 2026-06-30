import type { BodyMeasurement } from "./api";

export type BodyTone = "good" | "warn" | "bad";

// A changing body stat as shown on the dashboard (excludes height + birthdate/age,
// which don't meaningfully trend). BMI is derived from the latest weight + height.
export interface BodyDashItem {
  key: string;
  label: string;
  value: string;
  date: string;
  count: number;
  tone?: BodyTone; // graded metrics (BMI, blood pressure) only
  status?: string; // category label, e.g. "Healthy", "Stage 2"
}

/** BMI category + tone (WHO bands). */
export function bmiStatus(bmi: number): { tone: BodyTone; label: string } {
  if (bmi < 18.5) return { tone: "warn", label: "Underweight" };
  if (bmi < 25) return { tone: "good", label: "Healthy" };
  if (bmi < 30) return { tone: "warn", label: "Overweight" };
  return { tone: "bad", label: "Obese" };
}

/** Blood-pressure category + tone (ACC/AHA bands). */
export function bpStatus(sys: number, dia: number): { tone: BodyTone; label: string } {
  if (sys >= 140 || dia >= 90) return { tone: "bad", label: "Stage 2" };
  if (sys >= 130 || dia >= 80) return { tone: "warn", label: "Stage 1" };
  if (sys >= 120) return { tone: "warn", label: "Elevated" };
  return { tone: "good", label: "Normal" };
}

const fmtWeight = (kg: number, unit: string) =>
  unit === "lb" ? `${(kg * 2.20462).toFixed(1)} lb` : `${kg.toFixed(1)} kg`;

/** Latest changing body stats, in display order. Empty metrics are omitted. */
export function dashboardBodyItems(rows: BodyMeasurement[], weightUnit: string): BodyDashItem[] {
  const of = (kind: string) => rows.filter((m) => m.kind === kind);
  const items: BodyDashItem[] = [];
  const push = (key: string, label: string, list: BodyMeasurement[], fmt: (m: BodyMeasurement) => string) => {
    if (list.length) items.push({ key, label, value: fmt(list[0]), date: list[0].measuredOn, count: list.length });
  };

  const weights = of("weight");
  const heights = of("height");
  push("weight", "Weight", weights, (m) => fmtWeight(m.value, weightUnit));
  if (weights.length && heights.length && heights[0].value > 0) {
    const bmi = weights[0].value / (heights[0].value / 100) ** 2;
    const s = bmiStatus(bmi);
    items.push({
      key: "bmi",
      label: "BMI",
      value: bmi.toFixed(1),
      date: weights[0].measuredOn,
      count: weights.length,
      tone: s.tone,
      status: s.label,
    });
  }
  const bps = of("blood_pressure");
  if (bps.length) {
    const m = bps[0];
    const s = m.value2 != null ? bpStatus(m.value, m.value2) : undefined;
    items.push({
      key: "blood_pressure",
      label: "Blood Pressure",
      value:
        m.value2 != null ? `${m.value.toFixed(0)}/${m.value2.toFixed(0)} mmHg` : `${m.value.toFixed(0)} mmHg`,
      date: m.measuredOn,
      count: bps.length,
      tone: s?.tone,
      status: s?.label,
    });
  }
  push("resting_heart_rate", "Resting Heart Rate", of("resting_heart_rate"), (m) => `${m.value.toFixed(0)} bpm`);
  push("body_fat", "Body Fat", of("body_fat"), (m) => `${m.value.toFixed(1)}%`);
  push("waist", "Waist", of("waist"), (m) => `${m.value.toFixed(0)} cm`);
  push("vo2max", "Cardio Fitness", of("vo2max"), (m) => `${m.value.toFixed(1)} mL/kg·min`);
  push("oxygen", "Blood Oxygen", of("oxygen"), (m) => `${m.value.toFixed(0)}%`);
  return items;
}
