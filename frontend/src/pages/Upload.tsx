import { useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { api, type Draft, type Report } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { Badge, Button, Card, Input, Select, Spinner } from "@/components/ui";
import { UploadCloud, Trash2 } from "lucide-react";

function parseNum(s: string): number | null {
  const t = s.trim();
  if (t === "") return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

export function Upload() {
  const { profileId } = useProfile();
  const [reportId, setReportId] = useState<string | null>(null);
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
  flag: string;
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
      flag: d.flag ?? "",
      learnAlias: !d.suggestedAnalyteId,
      include: true,
    })),
  );

  const update = (i: number, patch: Partial<Row>) =>
    setRows((rs) => rs.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));

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
            flag: r.flag || null,
            observedDate: null, // falls back to collectedDate server-side
            learnAlias: r.learnAlias,
          })),
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["latest"] });
      qc.invalidateQueries({ queryKey: ["report", report.id] });
      navigate("/");
    },
  });

  const includedCount = useMemo(() => rows.filter((r) => r.include).length, [rows]);
  const canSave = collectedDate !== "" && includedCount > 0;

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-xl font-semibold">Review extracted results</h1>
        <p className="text-sm text-muted">
          Check the values, map each test to an analyte, then save.{" "}
          <a
            href={api.pdfUrl(report.id)}
            target="_blank"
            rel="noreferrer"
            className="text-accent"
          >
            View source PDF
          </a>
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
                <th className="pb-2 pr-2">Flag</th>
                <th className="pb-2 pr-2">Learn</th>
                <th className="pb-2"></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row, i) => (
                <tr
                  key={i}
                  className={
                    row.include ? "border-t border-border" : "border-t border-border opacity-40"
                  }
                >
                  <td className="py-2 pr-2 align-top">
                    <div className="max-w-[180px]">{row.rawTestName}</div>
                    {row.specimen && (
                      <div className="mt-0.5 text-xs text-muted">{row.specimen}</div>
                    )}
                  </td>
                  <td className="py-2 pr-2 align-top">
                    <Select
                      className="min-w-[180px]"
                      value={row.analyteId}
                      onChange={(e) => update(i, { analyteId: e.target.value })}
                    >
                      <option value="new">➕ New: {row.newName}</option>
                      {analytes.data?.map((a) => (
                        <option key={a.id} value={a.id}>
                          {a.name}
                          {a.specimen ? ` · ${a.specimen}` : ""}
                        </option>
                      ))}
                    </Select>
                    {row.analyteId === "new" && (
                      <Input
                        className="mt-1"
                        value={row.newName}
                        onChange={(e) => update(i, { newName: e.target.value })}
                        placeholder="Canonical name"
                      />
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
                      className="w-16"
                      value={row.flag}
                      onChange={(e) => update(i, { flag: e.target.value })}
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
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      <div className="flex items-center justify-between">
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
