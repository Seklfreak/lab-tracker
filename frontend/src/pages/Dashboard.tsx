import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { api } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { Badge, Card, Spinner } from "@/components/ui";
import { derivedFlag, displayValue, referenceLabel, statusTone } from "@/lib/format";

export function Dashboard() {
  const { profileId } = useProfile();

  const results = useQuery({
    queryKey: ["latest", profileId],
    queryFn: () => api.latestResults(profileId!),
    enabled: !!profileId,
  });

  if (!profileId) {
    return <p className="text-muted">Create or select a profile to get started.</p>;
  }
  if (results.isLoading) return <Spinner label="Loading results…" />;
  if (results.error)
    return <p className="text-bad">Failed to load results: {String(results.error)}</p>;

  const data = results.data ?? [];
  if (data.length === 0) {
    return (
      <Card>
        <p className="text-muted">
          No lab results yet.{" "}
          <Link to="/upload" className="text-accent">
            Upload a PDF
          </Link>{" "}
          to begin tracking.
        </p>
      </Card>
    );
  }

  // Group by category for a tidy dashboard.
  const groups = new Map<string, typeof data>();
  for (const r of data) {
    const key = r.category ?? "Other";
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(r);
  }

  return (
    <div className="space-y-8">
      {[...groups.entries()].map(([category, rows]) => (
        <section key={category}>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted">
            {category}
          </h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {rows.map((r) => {
              const tone = statusTone(r);
              const ref = referenceLabel(r);
              const flag = derivedFlag(r);
              return (
                <Link key={r.id} to={`/analytes/${r.analyteId}`}>
                  <Card className="transition hover:border-accent">
                    <div className="flex items-start justify-between">
                      <div className="font-medium">{r.analyteName}</div>
                      {flag && <Badge tone={tone}>{flag}</Badge>}
                    </div>
                    <div className="mt-2 flex items-baseline gap-1">
                      <span
                        className={
                          tone === "bad"
                            ? "text-2xl font-semibold text-bad"
                            : "text-2xl font-semibold"
                        }
                      >
                        {displayValue(r)}
                      </span>
                      {r.unit && <span className="text-sm text-muted">{r.unit}</span>}
                    </div>
                    <div className="mt-1 text-xs text-muted">
                      {ref ? `Ref: ${ref}` : "No reference"} ·{" "}
                      {r.observedDate ?? "no date"}
                    </div>
                  </Card>
                </Link>
              );
            })}
          </div>
        </section>
      ))}
    </div>
  );
}
