import { Fragment, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, useParams } from "react-router-dom";
import {
  CartesianGrid,
  ErrorBar,
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
import { Badge, Button, Card, Input, Spinner } from "@/components/ui";
import { Combobox, type ComboOption } from "@/components/Combobox";
import { Markdown } from "@/components/Markdown";
import {
  chartYDomain,
  derivedFlag,
  displayValue,
  plotPoint,
  referenceLabel,
  statusTone,
} from "@/lib/format";
import { useThemeColors } from "@/lib/theme";
import { ArrowLeft, Pencil, RotateCw, Sparkles, Trash2 } from "lucide-react";

function parseNum(s: string): number | null {
  const t = s.trim();
  if (t === "") return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

interface EditDraft {
  analyteId: string;
  value: string;
  unit: string;
  refLow: string;
  refHigh: string;
  refText: string;
  date: string;
  note: string;
}

function formatWhen(iso: string): string {
  const d = new Date(iso);
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 60) return "just now";
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return d.toLocaleString();
}

export function AnalyteDetail() {
  const { analyteId } = useParams();
  const { profileId } = useProfile();

  const trend = useQuery({
    queryKey: ["trend", profileId, analyteId],
    queryFn: () => api.analyteTrend(profileId!, analyteId!),
    enabled: !!profileId && !!analyteId,
  });

  const colors = useThemeColors();

  const qc = useQueryClient();
  const analysisQ = useQuery({
    queryKey: ["analysis", profileId, analyteId],
    queryFn: () => api.getAnalysis(profileId!, analyteId!),
    enabled: !!profileId && !!analyteId,
  });
  const generate = useMutation({
    mutationFn: () => api.generateAnalysis(profileId!, analyteId!),
    onSuccess: (res) => qc.setQueryData(["analysis", profileId, analyteId], res),
  });

  const analytes = useQuery({ queryKey: ["analytes"], queryFn: api.listAnalytes });
  const analyteOptions: ComboOption[] = (analytes.data ?? []).map((a) => ({
    value: a.id,
    label: a.name,
    hint: a.specimens && a.specimens.length > 0 ? a.specimens.join(" / ") : a.category,
  }));

  const [editingId, setEditingId] = useState<string | null>(null);
  const [draft, setDraft] = useState<EditDraft | null>(null);

  const invalidateResults = () => {
    qc.invalidateQueries({ queryKey: ["trend", profileId, analyteId] });
    qc.invalidateQueries({ queryKey: ["latest", profileId] });
  };
  const update = useMutation({
    mutationFn: (vars: { id: string; input: Parameters<typeof api.updateResult>[1] }) =>
      api.updateResult(vars.id, vars.input),
    onSuccess: () => {
      invalidateResults();
      setEditingId(null);
      setDraft(null);
    },
  });
  const removeResult = useMutation({
    mutationFn: (id: string) => api.deleteResult(id),
    onSuccess: invalidateResults,
  });

  const startEdit = (r: Result) => {
    setEditingId(r.id);
    setDraft({
      analyteId: r.analyteId,
      value: r.valueText ?? (r.valueNumeric != null ? String(r.valueNumeric) : ""),
      unit: r.unit ?? "",
      refLow: r.referenceLow != null ? String(r.referenceLow) : "",
      refHigh: r.referenceHigh != null ? String(r.referenceHigh) : "",
      refText: r.referenceText ?? "",
      date: r.observedDate ?? "",
      note: r.note ?? "",
    });
  };
  const saveEdit = () => {
    if (!editingId || !draft) return;
    update.mutate({
      id: editingId,
      input: {
        analyteId: draft.analyteId,
        valueText: draft.value || null,
        valueNumeric: parseNum(draft.value),
        unit: draft.unit || null,
        referenceLow: parseNum(draft.refLow),
        referenceHigh: parseNum(draft.refHigh),
        referenceText: draft.refText || null,
        note: draft.note || null,
        observedDate: draft.date || null,
      },
    });
  };

  if (!profileId) return <p className="text-muted">Select a profile.</p>;
  if (trend.isLoading) return <Spinner label="Loading trend…" />;
  if (trend.error)
    return <p className="text-bad">Failed to load: {String(trend.error)}</p>;

  const data = trend.data ?? [];
  if (data.length === 0)
    return (
      <div className="space-y-4">
        <BackLink />
        <Card>
          <p className="text-muted">No readings for this analyte.</p>
        </Card>
      </div>
    );

  const name = data[0].analyteName;
  const unit = data.find((r) => r.unit)?.unit ?? "";
  const refLow = data.find((r) => r.referenceLow !== null)?.referenceLow ?? null;
  const refHigh = data.find((r) => r.referenceHigh !== null)?.referenceHigh ?? null;

  // Plain numbers plot as a dot; bounded values ("<0.05") plot as a vertical
  // range line (via ErrorBar) covering where the true value could be.
  const chartData = data
    .map((r) => {
      const p = plotPoint(r);
      if (!p) return null;
      return {
        date: r.observedDate ?? "",
        value: p.value,
        err: p.err,
        bounded: p.err[0] > 0 || p.err[1] > 0,
      };
    })
    .filter((d): d is NonNullable<typeof d> => d !== null);
  const hasBounded = chartData.some((d) => d.bounded);

  // Y domain padded to include the data, the whisker extents, and reference
  // bounds so the green (in-range) and red (out-of-range) zones are visible.
  const yDomain = chartYDomain(
    chartData.flatMap((d) => [d.value, d.value - d.err[0], d.value + d.err[1]]),
    refLow,
    refHigh,
  );

  return (
    <div className="space-y-5">
      <BackLink />
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h1 className="text-xl font-semibold">
          {name} {unit && <span className="text-base text-muted">({unit})</span>}
        </h1>
        <span className="text-sm text-muted">
          {referenceLabel(data[data.length - 1]) ?? "no reference"}
        </span>
      </div>

      {chartData.length > 0 && (
        <Card>
          <div className="h-72 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={chartData} margin={{ top: 8, right: 16, bottom: 0, left: -8 }}>
                <CartesianGrid stroke={colors.border} strokeDasharray="3 3" />
                <XAxis dataKey="date" stroke={colors.muted} fontSize={12} />
                <YAxis stroke={colors.muted} fontSize={12} domain={yDomain} allowDataOverflow />
                <Tooltip
                  contentStyle={{
                    background: colors.panel,
                    border: `1px solid ${colors.border}`,
                    borderRadius: 8,
                    color: colors.text,
                  }}
                />
                {/* out-of-range zones (red): below low and above high */}
                {refLow !== null && (
                  <ReferenceArea y1={yDomain[0]} y2={refLow} fill={colors.bad} fillOpacity={0.08} />
                )}
                {refHigh !== null && (
                  <ReferenceArea y1={refHigh} y2={yDomain[1]} fill={colors.bad} fillOpacity={0.08} />
                )}
                {/* in-range zone (green) */}
                {(refLow !== null || refHigh !== null) && (
                  <ReferenceArea
                    y1={refLow ?? yDomain[0]}
                    y2={refHigh ?? yDomain[1]}
                    fill={colors.good}
                    fillOpacity={0.12}
                    stroke={colors.good}
                    strokeOpacity={0.25}
                  />
                )}
                <Line
                  type="monotone"
                  dataKey="value"
                  stroke={colors.accent}
                  strokeWidth={2}
                  dot={(props) => {
                    const { cx, cy, payload, index } = props;
                    // Bounded values are shown as the range line (ErrorBar), not a dot.
                    if (payload.bounded) return <g key={index} />;
                    return <circle key={index} cx={cx} cy={cy} r={3} fill={colors.accent} />;
                  }}
                >
                  <ErrorBar
                    dataKey="err"
                    direction="y"
                    width={6}
                    stroke={colors.accent}
                    strokeWidth={2}
                  />
                </Line>
              </LineChart>
            </ResponsiveContainer>
          </div>
          <p className="mt-2 text-xs text-muted">
            Green = in range, red = out of range.
            {hasBounded && " A vertical line shows the possible range for a bounded value (e.g. <0.05)."}
          </p>
        </Card>
      )}

      <Card>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="flex items-center gap-1.5 text-sm font-semibold uppercase tracking-wide text-muted">
            <Sparkles size={14} className="text-accent" /> AI analysis
          </h2>
          {analysisQ.data?.analysis && !generate.isPending && (
            <Button
              variant="ghost"
              className="px-2 py-1"
              onClick={() => generate.mutate()}
            >
              <RotateCw size={14} /> Regenerate
            </Button>
          )}
        </div>

        {generate.isPending ? (
          <div className="py-4">
            <Spinner label="Analyzing your results…" />
          </div>
        ) : analysisQ.isLoading ? (
          <div className="py-4">
            <Spinner />
          </div>
        ) : analysisQ.data?.analysis ? (
          <div className="mt-2">
            {analysisQ.data.analysis.stale && (
              <div className="mb-3 rounded-md border border-warn/40 bg-warn/10 px-3 py-2 text-xs text-warn">
                New results have been added since this analysis (
                {analysisQ.data.analysis.basedOnCount} → {analysisQ.data.analysis.currentCount}{" "}
                readings). Regenerate to include them.
              </div>
            )}
            <Markdown>{analysisQ.data.analysis.content}</Markdown>
            <p className="mt-2 text-xs text-muted">
              Generated {formatWhen(analysisQ.data.analysis.generatedAt)}
            </p>
          </div>
        ) : (
          <div className="py-2">
            <p className="mb-3 text-sm text-muted">
              Get a plain-language explanation of this analyte, an analysis of your trend over
              time, and how related results connect.
            </p>
            <Button onClick={() => generate.mutate()}>
              <Sparkles size={16} /> Generate AI analysis
            </Button>
          </div>
        )}
        {generate.error && (
          <p className="mt-2 text-sm text-bad">{String(generate.error)}</p>
        )}
      </Card>

      <Card>
        <div className="overflow-x-auto">
        <table className="w-full min-w-[480px] text-sm">
          <thead>
            <tr className="text-left text-muted">
              <th className="pb-2">Date</th>
              <th className="pb-2">Value</th>
              <th className="pb-2">Reference</th>
              <th className="pb-2">Flag</th>
              <th className="pb-2">Lab</th>
              <th className="pb-2">Source</th>
              <th className="pb-2 text-right">Edit</th>
            </tr>
          </thead>
          <tbody>
            {[...data].reverse().map((r) => {
              const tone = statusTone(r);
              const flag = derivedFlag(r);
              const editing = editingId === r.id;
              return (
                <Fragment key={r.id}>
                  <tr className="border-t border-border">
                    <td className="py-2">{r.observedDate ?? "—"}</td>
                    <td className={tone === "bad" ? "py-2 font-medium text-bad" : "py-2"}>
                      {displayValue(r)} {r.unit}
                    </td>
                    <td className="py-2 text-muted">{referenceLabel(r) ?? "—"}</td>
                    <td className="py-2">{flag ? <Badge tone={tone}>{flag}</Badge> : "—"}</td>
                    <td className="py-2 text-muted">{r.sourceLab ?? "—"}</td>
                    <td className="py-2">
                      <a
                        href={api.pdfUrl(r.reportId)}
                        target="_blank"
                        rel="noreferrer"
                        className="text-accent"
                      >
                        PDF
                      </a>
                    </td>
                    <td className="py-2">
                      <div className="flex items-center justify-end gap-2">
                        <button
                          onClick={() => (editing ? setEditingId(null) : startEdit(r))}
                          className="text-muted hover:text-accent"
                          title="Edit"
                        >
                          <Pencil size={15} />
                        </button>
                        <button
                          onClick={() => {
                            if (confirm("Delete this result?")) removeResult.mutate(r.id);
                          }}
                          className="text-muted hover:text-bad"
                          title="Delete"
                        >
                          <Trash2 size={15} />
                        </button>
                      </div>
                    </td>
                  </tr>
                  {editing && draft ? (
                    <tr>
                      <td colSpan={7} className="bg-panel2/40 px-2 py-3">
                        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                          <label className="col-span-2 text-xs sm:col-span-4">
                            <span className="mb-1 block text-muted">Analyte</span>
                            <Combobox
                              value={draft.analyteId}
                              onChange={(v) => setDraft({ ...draft, analyteId: v })}
                              options={analyteOptions}
                            />
                          </label>
                          <label className="text-xs">
                            <span className="mb-1 block text-muted">Value</span>
                            <Input value={draft.value} onChange={(e) => setDraft({ ...draft, value: e.target.value })} />
                          </label>
                          <label className="text-xs">
                            <span className="mb-1 block text-muted">Unit</span>
                            <Input value={draft.unit} onChange={(e) => setDraft({ ...draft, unit: e.target.value })} />
                          </label>
                          <label className="text-xs">
                            <span className="mb-1 block text-muted">Ref low</span>
                            <Input value={draft.refLow} onChange={(e) => setDraft({ ...draft, refLow: e.target.value })} />
                          </label>
                          <label className="text-xs">
                            <span className="mb-1 block text-muted">Ref high</span>
                            <Input value={draft.refHigh} onChange={(e) => setDraft({ ...draft, refHigh: e.target.value })} />
                          </label>
                          <label className="col-span-2 text-xs">
                            <span className="mb-1 block text-muted">Reference (text)</span>
                            <Input value={draft.refText} onChange={(e) => setDraft({ ...draft, refText: e.target.value })} placeholder="e.g. Negative" />
                          </label>
                          <label className="col-span-2 text-xs">
                            <span className="mb-1 block text-muted">Date</span>
                            <Input type="date" value={draft.date} onChange={(e) => setDraft({ ...draft, date: e.target.value })} />
                          </label>
                          <label className="col-span-2 text-xs sm:col-span-4">
                            <span className="mb-1 block text-muted">Note</span>
                            <textarea
                              className="w-full rounded-md border border-border bg-panel2 px-2 py-1 text-xs outline-none focus:border-accent"
                              rows={2}
                              value={draft.note}
                              onChange={(e) => setDraft({ ...draft, note: e.target.value })}
                            />
                          </label>
                        </div>
                        <div className="mt-3 flex items-center justify-end gap-2">
                          {update.error && <span className="mr-auto text-xs text-bad">{String(update.error)}</span>}
                          <Button variant="ghost" className="px-2 py-1" onClick={() => setEditingId(null)}>
                            Cancel
                          </Button>
                          <Button className="px-3 py-1" onClick={saveEdit} disabled={update.isPending || !draft.date}>
                            {update.isPending ? "Saving…" : "Save"}
                          </Button>
                        </div>
                      </td>
                    </tr>
                  ) : (
                    r.note && (
                      <tr>
                        <td colSpan={7} className="pb-2 text-xs italic text-muted">
                          {r.note}
                        </td>
                      </tr>
                    )
                  )}
                </Fragment>
              );
            })}
          </tbody>
        </table>
        </div>
      </Card>
    </div>
  );
}

function BackLink() {
  return (
    <Link to="/" className="inline-flex items-center gap-1 text-sm text-muted hover:text-text">
      <ArrowLeft size={16} /> Back to dashboard
    </Link>
  );
}
