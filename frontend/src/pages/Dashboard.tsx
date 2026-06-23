import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { clsx } from "clsx";
import { Star } from "lucide-react";
import { api, type Result } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { Badge, Card, Spinner } from "@/components/ui";
import { derivedFlag, displayValue, referenceLabel, statusTone } from "@/lib/format";

export function Dashboard() {
  const { profileId } = useProfile();
  const qc = useQueryClient();

  const results = useQuery({
    queryKey: ["latest", profileId],
    queryFn: () => api.latestResults(profileId!),
    enabled: !!profileId,
  });

  const toggleFav = useMutation({
    mutationFn: ({ analyteId, isFav }: { analyteId: string; isFav: boolean }) =>
      isFav ? api.removeFavorite(profileId!, analyteId) : api.addFavorite(profileId!, analyteId),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["latest", profileId] }),
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

  const renderCard = (r: Result) => (
    <ResultCard
      key={r.id}
      r={r}
      onToggleFav={() =>
        toggleFav.mutate({ analyteId: r.analyteId, isFav: !!r.isFavorite })
      }
    />
  );

  const favorites = data.filter((r) => r.isFavorite);
  const rest = data.filter((r) => !r.isFavorite);

  // Group the non-favorited results by category.
  const groups = new Map<string, Result[]>();
  for (const r of rest) {
    const key = r.category ?? "Other";
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(r);
  }

  return (
    <div className="space-y-8">
      {favorites.length > 0 && (
        <section>
          <h2 className="mb-3 flex items-center gap-1.5 text-sm font-semibold uppercase tracking-wide text-warn">
            <Star size={14} className="fill-warn" /> Favorites
          </h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {favorites.map(renderCard)}
          </div>
        </section>
      )}

      {[...groups.entries()].map(([category, rows]) => (
        <section key={category}>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted">
            {category}
          </h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {rows.map(renderCard)}
          </div>
        </section>
      ))}
    </div>
  );
}

function ResultCard({ r, onToggleFav }: { r: Result; onToggleFav: () => void }) {
  const tone = statusTone(r);
  const ref = referenceLabel(r);
  const flag = derivedFlag(r);
  return (
    <Link to={`/analytes/${r.analyteId}`}>
      <Card className="transition hover:border-accent">
        <div className="flex items-start justify-between gap-2">
          <div className="font-medium">{r.analyteName}</div>
          <div className="flex shrink-0 items-center gap-1.5">
            {flag && <Badge tone={tone}>{flag}</Badge>}
            <button
              onClick={(e) => {
                e.preventDefault();
                e.stopPropagation();
                onToggleFav();
              }}
              title={r.isFavorite ? "Unfavorite" : "Favorite"}
              className={clsx(
                "rounded p-0.5 transition hover:text-warn",
                r.isFavorite ? "text-warn" : "text-muted",
              )}
            >
              <Star size={16} className={r.isFavorite ? "fill-warn" : ""} />
            </button>
          </div>
        </div>
        <div className="mt-2 flex items-baseline gap-1">
          <span className={tone === "bad" ? "text-2xl font-semibold text-bad" : "text-2xl font-semibold"}>
            {displayValue(r)}
          </span>
          {r.unit && <span className="text-sm text-muted">{r.unit}</span>}
        </div>
        <div className="mt-1 flex items-center justify-between text-xs text-muted">
          <span>
            {ref ? `Ref: ${ref}` : "No reference"} · {r.observedDate ?? "no date"}
          </span>
          <span className="shrink-0">
            {r.count ?? 1} reading{(r.count ?? 1) === 1 ? "" : "s"}
          </span>
        </div>
      </Card>
    </Link>
  );
}
