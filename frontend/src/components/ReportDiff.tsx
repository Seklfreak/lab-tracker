import { useQuery } from "@tanstack/react-query";
import { ArrowDown, ArrowUp } from "lucide-react";
import { api, type Result } from "@/lib/api";
import { Badge, Spinner } from "@/components/ui";
import { derivedFlag, displayValue, referenceLabel, statusTone } from "@/lib/format";

const fmtNum = (n: number) => String(Math.round(n * 1000) / 1000);

// Most recent reading for an analyte from a different report, before `before`.
function priorReading(all: Result[], analyteId: string, before: string, excludeReport: string): Result | undefined {
  let best: Result | undefined;
  for (const r of all) {
    if (r.analyteId !== analyteId || r.reportId === excludeReport) continue;
    const d = r.observedDate ?? "";
    if (before && d >= before) continue;
    if (!best || d > (best.observedDate ?? "")) best = r;
  }
  return best;
}

// ReportDiff shows "what changed" for a saved report: out-of-range results, deltas
// vs the previous reading per analyte, and first-time readings. Computed entirely
// from the profile's results, so it works for any past upload — not just on save.
export function ReportDiff({ reportId, profileId }: { reportId: string; profileId: string }) {
  const all = useQuery({
    queryKey: ["all-results", profileId],
    queryFn: () => api.allResults(profileId),
  });

  if (all.isLoading) return <Spinner />;
  const results = all.data ?? [];
  const own = results.filter((r) => r.reportId === reportId);
  if (own.length === 0) return <p className="text-sm text-muted">No saved results for this report.</p>;

  const enriched = own.map((cur) => {
    const prev = priorReading(results, cur.analyteId, cur.observedDate ?? "", reportId);
    const numericDelta =
      prev && cur.valueNumeric !== null && prev.valueNumeric !== null
        ? cur.valueNumeric - prev.valueNumeric
        : null;
    return { cur, prev, flag: derivedFlag(cur), numericDelta };
  });

  const outOfRange = enriched.filter((e) => e.flag);
  const changed = enriched.filter((e) => e.numericDelta !== null && e.numericDelta !== 0);
  const firstReadings = enriched.filter((e) => !e.prev);

  if (outOfRange.length === 0 && changed.length === 0 && firstReadings.length === 0)
    return (
      <p className="text-sm text-muted">
        Everything is within range and unchanged from previous readings. 🎉
      </p>
    );

  return (
    <div className="space-y-4">
      {outOfRange.length > 0 && (
        <section>
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-bad">
            Out of range ({outOfRange.length})
          </h3>
          <ul className="space-y-1.5 text-sm">
            {outOfRange.map((e, i) => (
              <li key={i} className="flex flex-wrap items-center justify-between gap-2">
                <span className="font-medium">{e.cur.analyteName}</span>
                <span className="flex items-center gap-2 text-muted">
                  {displayValue(e.cur)} {e.cur.unit}
                  <span className="text-xs">({referenceLabel(e.cur) ?? "no ref"})</span>
                  <Badge tone={statusTone(e.cur)}>{e.flag}</Badge>
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {changed.length > 0 && (
        <section>
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">
            Changed since last reading ({changed.length})
          </h3>
          <ul className="space-y-1.5 text-sm">
            {changed.map((e, i) => {
              const up = (e.numericDelta ?? 0) > 0;
              return (
                <li key={i} className="flex flex-wrap items-center justify-between gap-2">
                  <span className="font-medium">{e.cur.analyteName}</span>
                  <span className="flex items-center gap-1.5 text-muted">
                    <span>{e.prev ? displayValue(e.prev) : "—"}</span>
                    <span>→</span>
                    <span className="text-text">{displayValue(e.cur)}</span>
                    <span className="text-xs">{e.cur.unit}</span>
                    <span className={up ? "flex items-center text-warn" : "flex items-center text-good"}>
                      {up ? <ArrowUp size={13} /> : <ArrowDown size={13} />}
                      {fmtNum(Math.abs(e.numericDelta ?? 0))}
                    </span>
                  </span>
                </li>
              );
            })}
          </ul>
        </section>
      )}

      {firstReadings.length > 0 && (
        <section>
          <h3 className="mb-1.5 text-xs font-semibold uppercase tracking-wide text-muted">
            First-time readings ({firstReadings.length})
          </h3>
          <p className="text-sm text-muted">
            {firstReadings.map((e) => e.cur.analyteName).join(", ")}
          </p>
        </section>
      )}
    </div>
  );
}
