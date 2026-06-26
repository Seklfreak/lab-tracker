import { useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { useQueries, useQuery } from "@tanstack/react-query";
import { clsx } from "clsx";
import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ReferenceArea,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { api, type Result } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { Card, Spinner } from "@/components/ui";
import { chartYDomain } from "@/lib/format";
import { useThemeColors } from "@/lib/theme";

const MAX = 6;
const PALETTE = ["#2f6fed", "#1f9d6b", "#b9761f", "#d2433f", "#7c5cff", "#0e9aa7"];

// Normalized position within the reference range: 0 = low end, 1 = high end.
// Needs a usable upper bound; lower bound defaults to 0 when absent.
function refPosition(r: Result): number | null {
  if (r.valueNumeric === null) return null;
  const hi = r.referenceHigh;
  const lo = r.referenceLow ?? 0;
  if (hi === null || hi <= lo) return null;
  return (r.valueNumeric - lo) / (hi - lo);
}

export function Compare() {
  const { profileId } = useProfile();
  const colors = useThemeColors();

  const latest = useQuery({
    queryKey: ["latest", profileId],
    queryFn: () => api.latestResults(profileId!),
    enabled: !!profileId,
  });

  // Initial selection comes from the dashboard via ?ids=a,b,c; the chips below
  // let you adjust it.
  const [params] = useSearchParams();
  const [selected, setSelected] = useState<string[]>(() =>
    (params.get("ids") ?? "").split(",").filter(Boolean).slice(0, MAX),
  );
  const toggle = (id: string) =>
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : s.length >= MAX ? s : [...s, id]));

  const trends = useQueries({
    queries: selected.map((id) => ({
      queryKey: ["trend", profileId, id],
      queryFn: () => api.analyteTrend(profileId!, id),
      enabled: !!profileId,
    })),
  });

  const nameById = useMemo(() => {
    const m = new Map<string, string>();
    for (const r of latest.data ?? []) m.set(r.analyteId, r.analyteName);
    return m;
  }, [latest.data]);

  // Merge each selected analyte's normalized series into rows keyed by date.
  const { chartData, plotted, skipped } = useMemo(() => {
    const byDate = new Map<string, Record<string, number | string>>();
    const plotted: string[] = [];
    const skipped: string[] = [];
    selected.forEach((id, idx) => {
      const name = nameById.get(id) ?? id;
      const rows = trends[idx]?.data ?? [];
      let any = false;
      for (const r of rows) {
        const pos = refPosition(r);
        if (pos === null) continue;
        any = true;
        const date = r.observedDate ?? "";
        if (!byDate.has(date)) byDate.set(date, { date });
        byDate.get(date)![name] = pos;
      }
      (any ? plotted : skipped).push(name);
    });
    const chartData = [...byDate.values()].sort((a, b) =>
      String(a.date).localeCompare(String(b.date)),
    );
    return { chartData, plotted, skipped };
  }, [selected, trends, nameById]);

  const yDomain = useMemo(() => {
    const vals = chartData.flatMap((row) =>
      Object.entries(row)
        .filter(([k]) => k !== "date")
        .map(([, v]) => v as number),
    );
    return chartYDomain(vals, 0, 1);
  }, [chartData]);

  if (!profileId) return <p className="text-muted">Select a profile.</p>;
  if (latest.isLoading) return <Spinner label="Loading…" />;

  const options = [...(latest.data ?? [])]
    .map((r) => ({ id: r.analyteId, name: r.analyteName }))
    .sort((a, b) => a.name.localeCompare(b.name));

  if (options.length === 0)
    return (
      <Card>
        <p className="text-muted">No results yet to compare.</p>
      </Card>
    );

  const loading = trends.some((t) => t.isLoading);

  return (
    <div className="space-y-5">
      <div>
        <Link to="/" className="text-sm text-accent">
          ← Dashboard
        </Link>
        <h1 className="mt-1 text-xl font-semibold">Compare analytes</h1>
        <p className="text-sm text-muted">
          Pick up to {MAX} analytes. Each is plotted relative to its reference range — 0 = low end,
          1 = high end; the shaded band is normal, points outside it are out of range.
        </p>
      </div>

      <Card>
        <div className="flex flex-wrap gap-2">
          {options.map((o) => {
            const on = selected.includes(o.id);
            const i = selected.indexOf(o.id);
            return (
              <button
                key={o.id}
                onClick={() => toggle(o.id)}
                className={clsx(
                  "rounded-full border px-3 py-1 text-sm transition",
                  on
                    ? "border-transparent text-white"
                    : "border-border bg-panel2 text-muted hover:text-text",
                )}
                style={on ? { backgroundColor: PALETTE[i % PALETTE.length] } : undefined}
              >
                {o.name}
              </button>
            );
          })}
        </div>
        {selected.length >= MAX && (
          <p className="mt-2 text-xs text-muted">Maximum of {MAX} selected.</p>
        )}
      </Card>

      {selected.length === 0 ? (
        <Card>
          <p className="text-sm text-muted">Select analytes above to overlay their trends.</p>
        </Card>
      ) : loading ? (
        <Spinner label="Loading trends…" />
      ) : chartData.length === 0 ? (
        <Card>
          <p className="text-sm text-muted">
            None of the selected analytes have numeric values with a reference range to normalize.
          </p>
        </Card>
      ) : (
        <Card>
          <div className="h-80 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={chartData} margin={{ top: 8, right: 16, bottom: 0, left: -8 }}>
                <CartesianGrid stroke={colors.border} strokeDasharray="3 3" />
                <XAxis dataKey="date" stroke={colors.muted} fontSize={12} />
                <YAxis stroke={colors.muted} fontSize={12} domain={yDomain} allowDataOverflow />
                {/* normal range band */}
                <ReferenceArea y1={0} y2={1} fill={colors.good} fillOpacity={0.1} />
                <Tooltip
                  contentStyle={{
                    background: colors.panel,
                    border: `1px solid ${colors.border}`,
                    borderRadius: 8,
                    color: colors.text,
                  }}
                  formatter={(v) => `${Math.round(Number(v) * 100)}% of range`}
                />
                <Legend />
                {plotted.map((name) => (
                  <Line
                    key={name}
                    type="monotone"
                    dataKey={name}
                    stroke={PALETTE[selected.findIndex((id) => nameById.get(id) === name) % PALETTE.length]}
                    strokeWidth={2}
                    dot={{ r: 2 }}
                    connectNulls
                  />
                ))}
              </LineChart>
            </ResponsiveContainer>
          </div>
          {skipped.length > 0 && (
            <p className="mt-2 text-xs text-muted">
              Not shown (no numeric value + reference range to normalize): {skipped.join(", ")}.
            </p>
          )}
        </Card>
      )}
    </div>
  );
}
