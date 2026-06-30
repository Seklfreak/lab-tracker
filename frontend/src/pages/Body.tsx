import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { api, type BodyMeasurement } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { useThemeColors } from "@/lib/theme";
import { Badge, Button, Card, Input, Select, Spinner } from "@/components/ui";

type WeightUnit = "kg" | "lb";
type HeightUnit = "cm" | "in";

const toDisplay = (canonical: number, kind: string, unit: string) => {
  if (kind === "weight" && unit === "lb") return canonical * 2.20462;
  if (kind === "height" && unit === "in") return canonical / 2.54;
  return canonical;
};
const toCanonical = (display: number, kind: string, unit: string) => {
  if (kind === "weight" && unit === "lb") return display / 2.20462;
  if (kind === "height" && unit === "in") return display * 2.54;
  return display;
};

const prettySource = (s?: string) =>
  s === "apple_health" ? "Apple Health" : s === "manual" || !s ? "Manual entry" : s;

function bmiCategory(v: number): { label: string; tone: "good" | "warn" | "bad" } {
  if (v < 18.5) return { label: "Underweight", tone: "warn" };
  if (v < 25) return { label: "Healthy", tone: "good" };
  if (v < 30) return { label: "Overweight", tone: "warn" };
  return { label: "Obese", tone: "bad" };
}

export function Body() {
  const { profileId } = useProfile();
  const qc = useQueryClient();

  const profiles = useQuery({ queryKey: ["profiles"], queryFn: api.listProfiles });
  const profile = profiles.data?.find((p) => p.id === profileId);

  const measurements = useQuery({
    queryKey: ["body", profileId],
    queryFn: () => api.bodyMeasurements(profileId!),
    enabled: !!profileId,
  });

  const [weightUnit, setWeightUnit] = useState<WeightUnit>(
    () => (localStorage.getItem("weightUnit") as WeightUnit) ?? "kg",
  );
  const [heightUnit, setHeightUnit] = useState<HeightUnit>(
    () => (localStorage.getItem("heightUnit") as HeightUnit) ?? "cm",
  );
  const [dob, setDob] = useState<string | null>(null);

  const rows = measurements.data ?? [];
  const weights = rows.filter((m) => m.kind === "weight");
  const heights = rows.filter((m) => m.kind === "height");
  const latestWeight = weights[0]?.value ?? null;
  const latestHeight = heights[0]?.value ?? null;
  const bmi =
    latestWeight !== null && latestHeight !== null && latestHeight > 0
      ? latestWeight / (latestHeight / 100) ** 2
      : null;

  const invalidate = () => qc.invalidateQueries({ queryKey: ["body", profileId] });
  const add = useMutation({
    mutationFn: (v: { kind: "weight" | "height"; value: number }) =>
      api.addBody(profileId!, v.kind, v.value, null),
    onSuccess: invalidate,
  });
  const del = useMutation({
    mutationFn: (id: string) => api.deleteBody(profileId!, id),
    onSuccess: invalidate,
  });
  const saveDob = useMutation({
    mutationFn: (value: string | null) =>
      api.updateProfile(profileId!, profile!.name, value),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["profiles"] }),
  });

  if (!profileId) {
    return <p className="text-sm text-muted">Select a profile first.</p>;
  }
  if (measurements.isLoading || profiles.isLoading) return <Spinner label="Loading…" />;

  const dobValue = dob ?? profile?.dateOfBirth ?? "";

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <h1 className="text-xl font-semibold">Body</h1>

      <Card>
        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-muted">Birthdate</span>
            <Input
              type="date"
              value={dobValue}
              onChange={(e) => setDob(e.target.value)}
              className="w-44"
            />
          </label>
          <Button
            onClick={() => saveDob.mutate(dobValue || null)}
            disabled={saveDob.isPending || dobValue === (profile?.dateOfBirth ?? "")}
          >
            Save
          </Button>
        </div>
      </Card>

      {bmi !== null && (
        <Card>
          <div className="flex items-center justify-between">
            <div>
              <div className="text-sm text-muted">BMI</div>
              <div className="text-2xl font-semibold tabular-nums">{bmi.toFixed(1)}</div>
            </div>
            <Badge tone={bmiCategory(bmi).tone}>{bmiCategory(bmi).label}</Badge>
          </div>
        </Card>
      )}

      <MetricCard
        title="Weight"
        kind="weight"
        items={weights}
        unit={weightUnit}
        units={["kg", "lb"]}
        onUnit={(u) => {
          setWeightUnit(u as WeightUnit);
          localStorage.setItem("weightUnit", u);
        }}
        onAdd={(value) => add.mutate({ kind: "weight", value })}
        onDelete={(id) => del.mutate(id)}
        showTrend
      />
      <MetricCard
        title="Height"
        kind="height"
        items={heights}
        unit={heightUnit}
        units={["cm", "in"]}
        onUnit={(u) => {
          setHeightUnit(u as HeightUnit);
          localStorage.setItem("heightUnit", u);
        }}
        onAdd={(value) => add.mutate({ kind: "height", value })}
        onDelete={(id) => del.mutate(id)}
      />
    </div>
  );
}

function MetricCard({
  title,
  kind,
  items,
  unit,
  units,
  onUnit,
  onAdd,
  onDelete,
  showTrend = false,
}: {
  title: string;
  kind: "weight" | "height";
  items: BodyMeasurement[];
  unit: string;
  units: string[];
  onUnit: (u: string) => void;
  onAdd: (canonicalValue: number) => void;
  onDelete: (id: string) => void;
  showTrend?: boolean;
}) {
  const colors = useThemeColors();
  const [text, setText] = useState("");
  const latest = items[0];

  const chartData = [...items]
    .reverse()
    .map((m) => ({ date: m.measuredOn, value: Number(toDisplay(m.value, kind, unit).toFixed(1)) }));

  const submit = () => {
    const v = Number(text);
    if (!Number.isFinite(v) || v <= 0) return;
    onAdd(toCanonical(v, kind, unit));
    setText("");
  };

  return (
    <Card>
      <div className="mb-3 flex items-center justify-between">
        <h2 className="font-semibold">{title}</h2>
        {latest && (
          <span className="tabular-nums">
            {toDisplay(latest.value, kind, unit).toFixed(1)}{" "}
            <span className="text-muted">{unit}</span>
          </span>
        )}
      </div>

      {showTrend && chartData.length >= 2 && (
        <div className="mb-3 h-40 w-full">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={chartData} margin={{ top: 8, right: 12, bottom: 0, left: -12 }}>
              <CartesianGrid stroke={colors.border} strokeDasharray="3 3" />
              <XAxis dataKey="date" stroke={colors.muted} fontSize={11} />
              <YAxis stroke={colors.muted} fontSize={11} domain={["auto", "auto"]} />
              <Tooltip
                contentStyle={{
                  background: colors.panel,
                  border: `1px solid ${colors.border}`,
                  borderRadius: 8,
                  color: colors.text,
                }}
              />
              <Line type="monotone" dataKey="value" stroke={colors.accent} strokeWidth={2} dot />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}

      <div className="flex items-center gap-2">
        <Input
          type="number"
          inputMode="decimal"
          placeholder={`Add reading (${unit})`}
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && submit()}
          className="w-40"
        />
        <Select value={unit} onChange={(e) => onUnit(e.target.value)} className="w-20">
          {units.map((u) => (
            <option key={u} value={u}>
              {u}
            </option>
          ))}
        </Select>
        <Button onClick={submit}>Add</Button>
      </div>

      {items.length > 0 && (
        <ul className="mt-3 divide-y divide-border text-sm">
          {items.map((m) => (
            <li key={m.id} className="flex items-center justify-between py-1.5">
              <span className="flex flex-col">
                <span>{m.measuredOn}</span>
                <span className="text-xs text-muted">{prettySource(m.source)}</span>
              </span>
              <span className="flex items-center gap-3">
                <span className="tabular-nums">
                  {toDisplay(m.value, kind, unit).toFixed(1)} {unit}
                </span>
                <button
                  className="text-muted hover:text-bad"
                  title="Delete"
                  onClick={() => onDelete(m.id)}
                >
                  ✕
                </button>
              </span>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
