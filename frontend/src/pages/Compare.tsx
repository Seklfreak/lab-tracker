import { useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { useQueries, useQuery } from "@tanstack/react-query";
import {
  CartesianGrid,
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
import { Button, Card, Spinner } from "@/components/ui";
import { Combobox, type ComboOption } from "@/components/Combobox";
import { chartYDomain, derivedFlag, displayValue, plotPoint, referenceLabel } from "@/lib/format";
import { useThemeColors, type ThemeColors } from "@/lib/theme";
import { downloadCsv } from "@/lib/csv";
import { exportSectionsPdf } from "@/lib/pdf";
import { FileDown, Download, X } from "lucide-react";

const MAX = 12;
const HISTORY_HEAD = ["Date", "Value", "Unit", "Reference", "Flag", "Lab"];

function historyRows(data: Result[]): (string | number)[][] {
  return [...data]
    .sort((a, b) => (a.observedDate ?? "").localeCompare(b.observedDate ?? ""))
    .map((r) => [
      r.observedDate ?? "",
      displayValue(r),
      r.unit ?? "",
      referenceLabel(r) ?? "",
      derivedFlag(r) ?? "Normal",
      r.sourceLab ?? "",
    ]);
}

// One analyte's trend; shares a synced crosshair with the others via syncId.
function MiniChart({ data, colors }: { data: Result[]; colors: ThemeColors }) {
  const refLow = data.find((r) => r.referenceLow !== null)?.referenceLow ?? null;
  const refHigh = data.find((r) => r.referenceHigh !== null)?.referenceHigh ?? null;
  const chartData = [...data]
    .sort((a, b) => (a.observedDate ?? "").localeCompare(b.observedDate ?? ""))
    .map((r) => {
      const p = plotPoint(r);
      return p ? { date: r.observedDate ?? "", value: p.value } : null;
    })
    .filter((d): d is { date: string; value: number } => d !== null);

  if (chartData.length === 0)
    return <p className="text-sm text-muted">No numeric values to plot.</p>;

  const yDomain = chartYDomain(
    chartData.map((d) => d.value),
    refLow,
    refHigh,
  );

  return (
    <div className="h-44 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart
          data={chartData}
          syncId="compare"
          syncMethod="value"
          margin={{ top: 8, right: 16, bottom: 0, left: -8 }}
        >
          <CartesianGrid stroke={colors.border} strokeDasharray="3 3" />
          <XAxis dataKey="date" stroke={colors.muted} fontSize={11} />
          <YAxis stroke={colors.muted} fontSize={11} domain={yDomain} width={44} allowDataOverflow />
          {refLow !== null && refHigh !== null && (
            <ReferenceArea y1={refLow} y2={refHigh} fill={colors.good} fillOpacity={0.1} />
          )}
          <Tooltip
            contentStyle={{
              background: colors.panel,
              border: `1px solid ${colors.border}`,
              borderRadius: 8,
              color: colors.text,
            }}
          />
          <Line type="monotone" dataKey="value" stroke={colors.accent} strokeWidth={2} dot={{ r: 2 }} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}

export function Compare() {
  const { profileId } = useProfile();
  const colors = useThemeColors();
  const [params] = useSearchParams();
  // Initial selection comes from the dashboard (?ids=a,b,c).
  const [selected, setSelected] = useState<string[]>(() =>
    (params.get("ids") ?? "").split(",").filter(Boolean).slice(0, MAX),
  );

  const analytes = useQuery({
    queryKey: ["profile-analytes", profileId],
    queryFn: () => api.listProfileAnalytes(profileId!),
    enabled: !!profileId,
  });
  const nameById = useMemo(() => {
    const m = new Map<string, string>();
    for (const a of analytes.data ?? []) m.set(a.id, a.name);
    return m;
  }, [analytes.data]);

  const trends = useQueries({
    queries: selected.map((id) => ({
      queryKey: ["trend", profileId, id],
      queryFn: () => api.analyteTrend(profileId!, id),
      enabled: !!profileId,
    })),
  });

  const add = (id: string) => setSelected((s) => (s.includes(id) || s.length >= MAX ? s : [...s, id]));
  const remove = (id: string) => setSelected((s) => s.filter((x) => x !== id));

  if (!profileId) return <p className="text-muted">Select a profile.</p>;
  if (analytes.isLoading) return <Spinner label="Loading…" />;

  const options: ComboOption[] = (analytes.data ?? [])
    .filter((a) => !selected.includes(a.id))
    .map((a) => ({ value: a.id, label: a.name, hint: a.category ?? undefined }))
    .sort((a, b) => a.label.localeCompare(b.label));

  const withData = selected
    .map((id, i) => ({ id, name: nameById.get(id) ?? id, data: trends[i]?.data ?? [] }))
    .filter((s) => s.data.length > 0);

  const exportPdf = () => {
    if (withData.length === 0) return;
    exportSectionsPdf({
      filename: `compare-${new Date().toISOString().slice(0, 10)}.pdf`,
      title: "Compare — full history",
      subtitle: new Date().toLocaleDateString(),
      sections: withData.map((s) => ({ heading: s.name, head: HISTORY_HEAD, rows: historyRows(s.data) })),
    });
  };
  const exportCsv = () => {
    if (withData.length === 0) return;
    const rows = withData.flatMap((s) => historyRows(s.data).map((r) => [s.name, ...r]));
    downloadCsv(`compare-${new Date().toISOString().slice(0, 10)}.csv`, ["Analyte", ...HISTORY_HEAD], rows);
  };

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <Link to="/" className="text-sm text-accent">
            ← Dashboard
          </Link>
          <h1 className="mt-1 text-xl font-semibold">Compare analytes</h1>
          <p className="text-sm text-muted">One chart per analyte — hover to sync a crosshair across all.</p>
        </div>
        {withData.length > 0 && (
          <div className="flex gap-2">
            <Button variant="ghost" className="px-2 py-1.5" onClick={exportCsv} title="Export CSV (full history)">
              <Download size={14} /> CSV
            </Button>
            <Button variant="ghost" className="px-2 py-1.5" onClick={exportPdf} title="Download PDF (full history)">
              <FileDown size={14} /> PDF
            </Button>
          </div>
        )}
      </div>

      <Card>
        {selected.length > 0 && (
          <div className="mb-3 flex flex-wrap gap-2">
            {selected.map((id) => (
              <span
                key={id}
                className="flex items-center gap-1 rounded-full bg-panel2 px-3 py-1 text-sm"
              >
                {nameById.get(id) ?? id}
                <button onClick={() => remove(id)} className="text-muted hover:text-bad" title="Remove">
                  <X size={13} />
                </button>
              </span>
            ))}
          </div>
        )}
        {selected.length < MAX ? (
          <Combobox value="" onChange={(id) => id && add(id)} options={options} placeholder="Add an analyte…" />
        ) : (
          <p className="text-xs text-muted">Maximum of {MAX} analytes.</p>
        )}
      </Card>

      {selected.length === 0 ? (
        <Card>
          <p className="text-sm text-muted">Add analytes above to compare their trends.</p>
        </Card>
      ) : (
        <div className="space-y-4">
          {selected.map((id, i) => (
            <Card key={id}>
              <div className="mb-2 flex items-center justify-between">
                <Link to={`/analytes/${id}`} className="font-medium hover:text-accent">
                  {nameById.get(id) ?? id}
                </Link>
                <button onClick={() => remove(id)} className="text-muted hover:text-bad" title="Remove">
                  <X size={15} />
                </button>
              </div>
              {trends[i]?.isLoading ? (
                <Spinner />
              ) : (trends[i]?.data ?? []).length === 0 ? (
                <p className="text-sm text-muted">No readings.</p>
              ) : (
                <MiniChart data={trends[i].data!} colors={colors} />
              )}
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
