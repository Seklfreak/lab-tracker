import { Fragment } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useParams } from "react-router-dom";
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
import { api } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { Badge, Card, Spinner } from "@/components/ui";
import { chartYDomain, derivedFlag, displayValue, referenceLabel, statusTone } from "@/lib/format";
import { useThemeColors } from "@/lib/theme";
import { ArrowLeft } from "lucide-react";

export function AnalyteDetail() {
  const { analyteId } = useParams();
  const { profileId } = useProfile();

  const trend = useQuery({
    queryKey: ["trend", profileId, analyteId],
    queryFn: () => api.analyteTrend(profileId!, analyteId!),
    enabled: !!profileId && !!analyteId,
  });

  const colors = useThemeColors();

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

  const chartData = data
    .filter((r) => r.valueNumeric !== null)
    .map((r) => ({ date: r.observedDate ?? "", value: r.valueNumeric as number }));

  // Y domain padded to include the data and reference bounds, so the green
  // (in-range) and red (out-of-range) zones are fully visible.
  const yDomain = chartYDomain(chartData.map((d) => d.value), refLow, refHigh);

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
                  dot={{ r: 3, fill: colors.accent }}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
          <p className="mt-2 text-xs text-muted">
            Green = in range, red = out of range.
          </p>
        </Card>
      )}

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
            </tr>
          </thead>
          <tbody>
            {[...data].reverse().map((r) => {
              const tone = statusTone(r);
              const flag = derivedFlag(r);
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
                  </tr>
                  {r.note && (
                    <tr>
                      <td colSpan={6} className="pb-2 text-xs italic text-muted">
                        {r.note}
                      </td>
                    </tr>
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
