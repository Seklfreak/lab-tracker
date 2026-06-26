import { Fragment, useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useNavigate, useSearchParams } from "react-router-dom";
import { api, type Draft, type Report, type Result } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { Badge, Button, Card, Input, Spinner } from "@/components/ui";
import { Combobox, type ComboOption } from "@/components/Combobox";
import { derivedFlag, displayValue, referenceLabel, statusTone } from "@/lib/format";
import { UploadCloud, Trash2, ArrowUp, ArrowDown } from "lucide-react";

function parseNum(s: string): number | null {
  const t = s.trim();
  if (t === "") return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

// Canonical string for a value, so "5.50" and 5.5 compare equal across imports.
function valueKey(valueText: string | null, valueNumeric: number | null): string {
  if (valueNumeric !== null) return String(valueNumeric);
  return (valueText ?? "").trim().toLowerCase();
}

// Duplicate key: same analyte + observed date + value. Returns null when the row
// has no resolved analyte yet (can't be judged a duplicate).
function dupKey(analyteId: string, date: string, vKey: string): string | null {
  if (!analyteId || analyteId === "new" || !date) return null;
  return `${analyteId}|${date}|${vKey}`;
}

function labelFor(analyteId: string, options: ComboOption[], fallback: string): string {
  return options.find((o) => o.value === analyteId)?.label ?? fallback;
}

interface SavedRow {
  analyteId: string; // uuid or "new"
  name: string;
  value: string;
  valueNumeric: number | null;
  unit: string;
  refLow: number | null;
  refHigh: number | null;
  refText: string;
}

export function Upload() {
  const { profileId } = useProfile();
  const [searchParams] = useSearchParams();
  // Allow re-opening an existing report's review form via ?report=<id>.
  const [reportId, setReportId] = useState<string | null>(() => searchParams.get("report"));
  const fileRef = useRef<HTMLInputElement>(null);

  const upload = useMutation({
    mutationFn: (file: File) => api.uploadReport(profileId!, file),
    onSuccess: (r) => setReportId(r.id),
  });

  // Poll the report until parsing finishes.
  const report = useQuery({
    queryKey: ["report", reportId],
    queryFn: () => api.getReport(reportId!),
    enabled: !!reportId,
    refetchInterval: (q) => {
      const data = q.state.data as Report | undefined;
      return data && data.status === "parsing" ? 1500 : false;
    },
  });

  if (!profileId)
    return <p className="text-muted">Select a profile before uploading.</p>;

  // Reset to upload a new file.
  const reset = () => {
    setReportId(null);
    upload.reset();
  };

  if (!reportId) {
    return (
      <Card className="mx-auto max-w-xl">
        <div className="flex flex-col items-center gap-4 py-8 text-center">
          <UploadCloud className="text-accent" size={40} />
          <div>
            <p className="font-medium">Upload a lab result PDF</p>
            <p className="text-sm text-muted">
              Claude will scan it and pre-fill a form you can review.
            </p>
          </div>
          <input
            ref={fileRef}
            type="file"
            accept="application/pdf"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) upload.mutate(f);
            }}
          />
          <Button onClick={() => fileRef.current?.click()} disabled={upload.isPending}>
            {upload.isPending ? "Uploading…" : "Choose PDF"}
          </Button>
          {upload.error && (
            <p className="text-sm text-bad">{String(upload.error)}</p>
          )}
        </div>
      </Card>
    );
  }

  const r = report.data;
  if (!r || (report.isLoading && !r)) return <Spinner label="Loading…" />;

  if (r.status === "parsing") {
    return (
      <Card className="mx-auto max-w-xl">
        <div className="flex flex-col items-center gap-4 py-10">
          <Spinner label="Claude is scanning your PDF…" />
          <p className="text-sm text-muted">This usually takes 10–30 seconds.</p>
        </div>
      </Card>
    );
  }

  if (r.status === "error") {
    return (
      <Card className="mx-auto max-w-xl">
        <p className="font-medium text-bad">Parsing failed</p>
        <p className="mt-1 text-sm text-muted">{r.parseError ?? "Unknown error"}</p>
        <Button className="mt-4" variant="ghost" onClick={reset}>
          Try another file
        </Button>
      </Card>
    );
  }

  if (!r.draft) {
    return (
      <Card>
        <p className="text-muted">No data was extracted from this PDF.</p>
        <Button className="mt-4" variant="ghost" onClick={reset}>
          Try another file
        </Button>
      </Card>
    );
  }

  return <ReviewForm report={r} draft={r.draft} onDone={reset} />;
}

interface Row {
  rawTestName: string;
  specimen: string | null;
  analyteId: string; // "" | "new" | uuid
  newName: string;
  value: string;
  unit: string;
  refLow: string;
  refHigh: string;
  refText: string;
  note: string;
  suggestedByAi: boolean;
  learnAlias: boolean;
  include: boolean;
}

function ReviewForm({
  report,
  draft,
  onDone,
}: {
  report: Report;
  draft: Draft;
  onDone: () => void;
}) {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const analytes = useQuery({ queryKey: ["analytes"], queryFn: api.listAnalytes });
  // Existing results power duplicate detection + the post-save "what changed" diff.
  const existing = useQuery({
    queryKey: ["all-results", report.profileId],
    queryFn: () => api.allResults(report.profileId),
  });

  const baseOptions = useMemo<ComboOption[]>(
    () =>
      (analytes.data ?? []).map((a) => ({
        value: a.id,
        label: a.name,
        hint: a.specimens && a.specimens.length > 0 ? a.specimens.join(" / ") : a.category,
      })),
    [analytes.data],
  );

  const [sourceLab, setSourceLab] = useState(draft.labName ?? "");
  const [collectedDate, setCollectedDate] = useState(draft.collectedDate ?? "");
  const [reportedDate, setReportedDate] = useState(draft.reportedDate ?? "");

  const [rows, setRows] = useState<Row[]>(() =>
    draft.results.map((d) => ({
      rawTestName: d.testName,
      specimen: d.specimen,
      analyteId: d.suggestedAnalyteId ?? "new",
      newName: d.suggestedAnalyteName ?? d.testName,
      value: d.value ?? "",
      unit: d.unit ?? "",
      refLow: d.referenceLow !== null ? String(d.referenceLow) : "",
      refHigh: d.referenceHigh !== null ? String(d.referenceHigh) : "",
      refText: d.referenceRange ?? "",
      note: d.note ?? "",
      suggestedByAi: d.suggestedByAi,
      learnAlias: !d.suggestedAnalyteId,
      include: true,
    })),
  );

  const update = (i: number, patch: Partial<Row>) =>
    setRows((rs) => rs.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));

  // Duplicate detection: a row matching an already-imported result (same analyte +
  // collected date + value) is flagged and excluded by default.
  const existingKeys = useMemo(() => {
    const set = new Set<string>();
    for (const r of existing.data ?? []) {
      if (r.reportId === report.id) continue;
      const k = dupKey(r.analyteId, r.observedDate ?? "", valueKey(r.valueText, r.valueNumeric));
      if (k) set.add(k);
    }
    return set;
  }, [existing.data, report.id]);
  const isDup = (row: Row) => {
    const k = dupKey(row.analyteId, collectedDate, valueKey(row.value, parseNum(row.value)));
    return k !== null && existingKeys.has(k);
  };
  const dedupApplied = useRef(false);
  useEffect(() => {
    if (dedupApplied.current || !existing.data) return;
    dedupApplied.current = true;
    setRows((rs) => rs.map((r) => (isDup(r) ? { ...r, include: false } : r)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [existing.data]);

  const [saved, setSaved] = useState<SavedRow[] | null>(null);
  const buildSnapshot = (): SavedRow[] =>
    rows
      .filter((r) => r.include)
      .map((r) => ({
        analyteId: r.analyteId,
        name: r.analyteId === "new" ? r.newName || r.rawTestName : labelFor(r.analyteId, baseOptions, r.rawTestName),
        value: r.value,
        valueNumeric: parseNum(r.value),
        unit: r.unit,
        refLow: parseNum(r.refLow),
        refHigh: parseNum(r.refHigh),
        refText: r.refText,
      }));

  const confirm = useMutation({
    mutationFn: () =>
      api.confirmReport(report.id, {
        sourceLab: sourceLab || null,
        collectedDate: collectedDate || null,
        reportedDate: reportedDate || null,
        results: rows
          .filter((r) => r.include)
          .map((r) => ({
            analyteId: r.analyteId && r.analyteId !== "new" ? r.analyteId : null,
            newAnalyteName: r.analyteId === "new" ? r.newName || r.rawTestName : null,
            newAnalyteUnit: r.analyteId === "new" ? r.unit || null : null,
            rawTestName: r.rawTestName,
            valueText: r.value || null,
            valueNumeric: parseNum(r.value),
            unit: r.unit || null,
            referenceLow: parseNum(r.refLow),
            referenceHigh: parseNum(r.refHigh),
            referenceText: r.refText || null,
            note: r.note || null,
            observedDate: null, // falls back to collectedDate server-side
            learnAlias: r.learnAlias,
          })),
      }),
    onSuccess: () => {
      setSaved(buildSnapshot());
      qc.invalidateQueries({ queryKey: ["latest"] });
      qc.invalidateQueries({ queryKey: ["report", report.id] });
    },
  });

  if (saved) {
    return (
      <SaveSummary
        rows={saved}
        prior={existing.data ?? []}
        reportId={report.id}
        collectedDate={collectedDate}
        onDone={() => navigate("/")}
      />
    );
  }

  const includedCount = useMemo(() => rows.filter((r) => r.include).length, [rows]);
  const canSave = collectedDate !== "" && includedCount > 0;

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-xl font-semibold">Review extracted results</h1>
        <p className="text-sm text-muted">
          Check the values, map each test to an analyte, then save.{" "}
          <button
            type="button"
            onClick={() => void api.openPdf(report.id)}
            className="text-accent"
          >
            View source PDF
          </button>
        </p>
      </div>

      <Card>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <label className="text-sm">
            <span className="mb-1 block text-muted">Lab</span>
            <Input value={sourceLab} onChange={(e) => setSourceLab(e.target.value)} />
          </label>
          <label className="text-sm">
            <span className="mb-1 block text-muted">
              Collected date <span className="text-bad">*</span>
            </span>
            <Input
              type="date"
              value={collectedDate}
              onChange={(e) => setCollectedDate(e.target.value)}
            />
          </label>
          <label className="text-sm">
            <span className="mb-1 block text-muted">Reported date</span>
            <Input
              type="date"
              value={reportedDate}
              onChange={(e) => setReportedDate(e.target.value)}
            />
          </label>
        </div>
      </Card>

      <Card>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[900px] text-sm">
            <thead>
              <tr className="text-left text-muted">
                <th className="pb-2 pr-2">Test (as printed)</th>
                <th className="pb-2 pr-2">Analyte</th>
                <th className="pb-2 pr-2">Value</th>
                <th className="pb-2 pr-2">Unit</th>
                <th className="pb-2 pr-2">Ref low</th>
                <th className="pb-2 pr-2">Ref high</th>
                <th className="pb-2 pr-2">Reference</th>
                <th className="pb-2 pr-2">Learn</th>
                <th className="pb-2"></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row, i) => (
                <Fragment key={i}>
                <tr
                  className={
                    row.include ? "border-t border-border" : "border-t border-border opacity-40"
                  }
                >
                  <td className="py-2 pr-2 align-top">
                    <div className="max-w-[180px]">{row.rawTestName}</div>
                    {row.specimen && (
                      <div className="mt-0.5 text-xs text-muted">{row.specimen}</div>
                    )}
                    {isDup(row) && (
                      <div className="mt-0.5">
                        <Badge tone="muted">Already imported</Badge>
                      </div>
                    )}
                  </td>
                  <td className="py-2 pr-2 align-top">
                    <Combobox
                      className="min-w-[200px]"
                      value={row.analyteId}
                      onChange={(v) => update(i, { analyteId: v })}
                      options={[
                        { value: "new", label: `➕ New: ${row.newName}` },
                        ...baseOptions,
                      ]}
                    />
                    {row.analyteId === "new" && (
                      <Input
                        className="mt-1"
                        value={row.newName}
                        onChange={(e) => update(i, { newName: e.target.value })}
                        placeholder="Canonical name"
                      />
                    )}
                    {row.suggestedByAi && row.analyteId !== "new" && (
                      <div className="mt-1">
                        <Badge tone="warn">AI match — verify</Badge>
                      </div>
                    )}
                  </td>
                  <td className="py-2 pr-2 align-top">
                    <Input
                      className="w-24"
                      value={row.value}
                      onChange={(e) => update(i, { value: e.target.value })}
                    />
                  </td>
                  <td className="py-2 pr-2 align-top">
                    <Input
                      className="w-20"
                      value={row.unit}
                      onChange={(e) => update(i, { unit: e.target.value })}
                    />
                  </td>
                  <td className="py-2 pr-2 align-top">
                    <Input
                      className="w-20"
                      value={row.refLow}
                      onChange={(e) => update(i, { refLow: e.target.value })}
                    />
                  </td>
                  <td className="py-2 pr-2 align-top">
                    <Input
                      className="w-20"
                      value={row.refHigh}
                      onChange={(e) => update(i, { refHigh: e.target.value })}
                    />
                  </td>
                  <td className="py-2 pr-2 align-top">
                    <Input
                      className="w-28"
                      value={row.refText}
                      onChange={(e) => update(i, { refText: e.target.value })}
                      placeholder="e.g. Negative"
                    />
                  </td>
                  <td className="py-2 pr-2 align-top">
                    <input
                      type="checkbox"
                      checked={row.learnAlias}
                      onChange={(e) => update(i, { learnAlias: e.target.checked })}
                      title="Remember this name → analyte mapping"
                    />
                  </td>
                  <td className="py-2 align-top">
                    <button
                      onClick={() => update(i, { include: !row.include })}
                      className="text-muted hover:text-bad"
                      title={row.include ? "Exclude row" : "Include row"}
                    >
                      <Trash2 size={16} />
                    </button>
                  </td>
                </tr>
                {row.note !== "" && (
                  <tr className={row.include ? "" : "opacity-40"}>
                    <td className="pb-2 pr-2" colSpan={9}>
                      <div className="flex items-start gap-2">
                        <span className="mt-1 shrink-0 text-xs text-muted">Note</span>
                        <textarea
                          className="w-full rounded-md border border-border bg-panel2 px-2 py-1 text-xs outline-none focus:border-accent"
                          rows={2}
                          value={row.note}
                          onChange={(e) => update(i, { note: e.target.value })}
                        />
                      </div>
                    </td>
                  </tr>
                )}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="text-sm text-muted">
          {includedCount} result{includedCount === 1 ? "" : "s"} to save
          {!collectedDate && (
            <span className="ml-2">
              <Badge tone="warn">Set a collected date</Badge>
            </span>
          )}
        </div>
        <div className="flex gap-2">
          <Button variant="ghost" onClick={onDone}>
            Cancel
          </Button>
          <Button onClick={() => confirm.mutate()} disabled={!canSave || confirm.isPending}>
            {confirm.isPending ? "Saving…" : "Save results"}
          </Button>
        </div>
      </div>
      {confirm.error && <p className="text-sm text-bad">{String(confirm.error)}</p>}
    </div>
  );
}

function toResult(row: SavedRow): Result {
  return {
    valueText: row.value || null,
    valueNumeric: row.valueNumeric,
    unit: row.unit || null,
    referenceLow: row.refLow,
    referenceHigh: row.refHigh,
    referenceText: row.refText || null,
  } as Result;
}

const fmtNum = (n: number) => String(Math.round(n * 1000) / 1000);

// SaveSummary shows "what changed" right after a report is saved: out-of-range
// results, changes vs the previous reading per analyte, and first-time readings.
function SaveSummary({
  rows,
  prior,
  reportId,
  collectedDate,
  onDone,
}: {
  rows: SavedRow[];
  prior: Result[];
  reportId: string;
  collectedDate: string;
  onDone: () => void;
}) {
  // Most recent earlier reading per analyte (excluding this report).
  const priorByAnalyte = new Map<string, Result>();
  for (const r of prior) {
    if (r.reportId === reportId) continue;
    if ((r.observedDate ?? "") >= collectedDate) continue;
    const cur = priorByAnalyte.get(r.analyteId);
    if (!cur || (r.observedDate ?? "") > (cur.observedDate ?? "")) priorByAnalyte.set(r.analyteId, r);
  }

  const enriched = rows.map((row) => {
    const cur = toResult(row);
    const prev = row.analyteId !== "new" ? priorByAnalyte.get(row.analyteId) : undefined;
    const numericDelta =
      prev && row.valueNumeric !== null && prev.valueNumeric !== null
        ? row.valueNumeric - prev.valueNumeric
        : null;
    return { row, cur, flag: derivedFlag(cur), prev, numericDelta };
  });

  const outOfRange = enriched.filter((e) => e.flag);
  const changed = enriched.filter((e) => e.numericDelta !== null && e.numericDelta !== 0);
  const firstReadings = enriched.filter((e) => !e.prev && e.row.analyteId !== "new");
  const nothing = outOfRange.length === 0 && changed.length === 0;

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Saved {rows.length} result{rows.length === 1 ? "" : "s"}</h1>
          <p className="text-sm text-muted">Here’s what changed.</p>
        </div>
        <Button onClick={onDone}>Go to dashboard</Button>
      </div>

      {nothing && (
        <Card>
          <p className="text-sm text-muted">
            Everything is within range and unchanged from your previous readings. 🎉
          </p>
        </Card>
      )}

      {outOfRange.length > 0 && (
        <Card>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-bad">
            Out of range ({outOfRange.length})
          </h2>
          <ul className="space-y-1.5 text-sm">
            {outOfRange.map((e, i) => (
              <li key={i} className="flex flex-wrap items-center justify-between gap-2">
                <span className="font-medium">{e.row.name}</span>
                <span className="flex items-center gap-2 text-muted">
                  {displayValue(e.cur)} {e.row.unit}
                  <span className="text-xs">({referenceLabel(e.cur) ?? "no ref"})</span>
                  <Badge tone={statusTone(e.cur)}>{e.flag}</Badge>
                </span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      {changed.length > 0 && (
        <Card>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted">
            Changed since last reading ({changed.length})
          </h2>
          <ul className="space-y-1.5 text-sm">
            {changed.map((e, i) => {
              const up = (e.numericDelta ?? 0) > 0;
              return (
                <li key={i} className="flex flex-wrap items-center justify-between gap-2">
                  <span className="font-medium">{e.row.name}</span>
                  <span className="flex items-center gap-1.5 text-muted">
                    <span>{e.prev ? displayValue(e.prev) : "—"}</span>
                    <span>→</span>
                    <span className="text-text">{displayValue(e.cur)}</span>
                    <span className="text-xs">{e.row.unit}</span>
                    <span className={up ? "flex items-center text-warn" : "flex items-center text-good"}>
                      {up ? <ArrowUp size={13} /> : <ArrowDown size={13} />}
                      {fmtNum(Math.abs(e.numericDelta ?? 0))}
                    </span>
                  </span>
                </li>
              );
            })}
          </ul>
        </Card>
      )}

      {firstReadings.length > 0 && (
        <Card>
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted">
            First-time readings ({firstReadings.length})
          </h2>
          <p className="text-sm text-muted">{firstReadings.map((e) => e.row.name).join(", ")}</p>
        </Card>
      )}
    </div>
  );
}
