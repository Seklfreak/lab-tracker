import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { clsx } from "clsx";
import { AlertTriangle, Download, LineChart, Printer, RotateCw, Sparkles, Star } from "lucide-react";
import { api, type Result } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { Badge, Button, Card, Input, Select, Spinner } from "@/components/ui";
import { Markdown } from "@/components/Markdown";
import { downloadCsv } from "@/lib/csv";
import { derivedFlag, displayValue, referenceLabel, statusTone } from "@/lib/format";

const SORT_KEYS = ["category", "count", "name", "recent"] as const;
type SortKey = (typeof SORT_KEYS)[number];

function comparator(key: SortKey): (a: Result, b: Result) => number {
  const byName = (a: Result, b: Result) => a.analyteName.localeCompare(b.analyteName);
  switch (key) {
    case "count":
      return (a, b) => (b.count ?? 1) - (a.count ?? 1) || byName(a, b);
    case "recent":
      return (a, b) => (b.observedDate ?? "").localeCompare(a.observedDate ?? "") || byName(a, b);
    default:
      return byName;
  }
}

export function Dashboard() {
  const { profileId } = useProfile();
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [query, setQuery] = useState("");
  const [onlyAbnormal, setOnlyAbnormal] = useState(false);
  // Analytes selected (via card checkboxes) to overlay on the Compare view.
  const [sel, setSel] = useState<string[]>([]);
  const toggleSel = (id: string) =>
    setSel((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));

  // Persist the sort in the URL (?sort=) so it survives navigation / browser back.
  const [searchParams, setSearchParams] = useSearchParams();
  const sortParam = searchParams.get("sort");
  const sort: SortKey = SORT_KEYS.includes(sortParam as SortKey)
    ? (sortParam as SortKey)
    : "category";
  const setSort = (value: SortKey) =>
    setSearchParams(
      (prev) => {
        const next = new URLSearchParams(prev);
        if (value === "category") next.delete("sort");
        else next.set("sort", value);
        return next;
      },
      { replace: true },
    );

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
      selected={sel.includes(r.analyteId)}
      onToggleSelect={() => toggleSel(r.analyteId)}
      onToggleFav={() =>
        toggleFav.mutate({ analyteId: r.analyteId, isFav: !!r.isFavorite })
      }
    />
  );

  const q = query.trim().toLowerCase();
  const abnormalCount = data.filter((r) => derivedFlag(r)).length;
  let filtered = q ? data.filter((r) => r.analyteName.toLowerCase().includes(q)) : data;
  if (onlyAbnormal) filtered = filtered.filter((r) => derivedFlag(r));

  const cmp = comparator(sort);
  const favorites = [...filtered.filter((r) => r.isFavorite)].sort(cmp);
  const rest = filtered.filter((r) => !r.isFavorite);

  // Export the current view (respects search / needs-attention filters).
  const exportCsv = () =>
    downloadCsv(
      `lab-panel-${new Date().toISOString().slice(0, 10)}.csv`,
      ["Analyte", "Value", "Unit", "Reference", "Date", "Flag"],
      [...filtered]
        .sort((a, b) => a.analyteName.localeCompare(b.analyteName))
        .map((r) => [
          r.analyteName,
          displayValue(r),
          r.unit ?? "",
          referenceLabel(r) ?? "",
          r.observedDate ?? "",
          derivedFlag(r) ?? "Normal",
        ]),
    );

  const controls = (
    <div className="flex flex-wrap items-center gap-3">
      <Input
        type="search"
        placeholder="Search analytes…"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        className="w-full sm:max-w-xs"
      />
      {abnormalCount > 0 && (
        <button
          onClick={() => setOnlyAbnormal((v) => !v)}
          aria-pressed={onlyAbnormal}
          className={clsx(
            "flex items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-sm transition",
            onlyAbnormal
              ? "border-bad/50 bg-bad/15 text-bad"
              : "border-border bg-panel2 text-muted hover:text-text",
          )}
        >
          <AlertTriangle size={14} /> Needs attention
          <span className="rounded-full bg-bad/20 px-1.5 text-xs font-semibold text-bad">
            {abnormalCount}
          </span>
        </button>
      )}
      <div className="flex items-center gap-2 text-sm sm:ml-auto">
        <Button variant="ghost" className="px-2 py-1.5" onClick={exportCsv} title="Export CSV">
          <Download size={14} /> CSV
        </Button>
        <Button
          variant="ghost"
          className="px-2 py-1.5"
          onClick={() => window.print()}
          title="Print / Save as PDF"
        >
          <Printer size={14} /> Print
        </Button>
        <span className="shrink-0 text-muted">Sort by</span>
        {/* Select forces w-full; constrain it via a fixed-width wrapper. */}
        <div className="w-44">
          <Select value={sort} onChange={(e) => setSort(e.target.value as SortKey)}>
            <option value="category">Category</option>
            <option value="count">Most readings</option>
            <option value="recent">Most recent</option>
            <option value="name">Name (A–Z)</option>
          </Select>
        </div>
      </div>
    </div>
  );

  const favSection = favorites.length > 0 && (
    <section>
      <h2 className="mb-3 flex items-center gap-1.5 text-sm font-semibold uppercase tracking-wide text-warn">
        <Star size={14} className="fill-warn" /> Favorites
      </h2>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {favorites.map(renderCard)}
      </div>
    </section>
  );

  // Category sort keeps the grouped layout; any other sort flattens into one list.
  let body;
  if (sort === "category") {
    const groups = new Map<string, Result[]>();
    for (const r of rest) {
      const key = r.category ?? "Other";
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key)!.push(r);
    }
    body = [...groups.entries()].map(([category, rows]) => (
      <section key={category}>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted">{category}</h2>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {[...rows].sort(cmp).map(renderCard)}
        </div>
      </section>
    ));
  } else {
    body = (
      <section>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {[...rest].sort(cmp).map(renderCard)}
        </div>
      </section>
    );
  }

  return (
    <div className="space-y-6">
      <PanelSummaryCard key={profileId} profileId={profileId} currentCount={data.length} />
      {controls}
      {/* Floating (fixed) so selecting doesn't reflow the list under your finger. */}
      {sel.length > 0 && (
        <div className="fixed inset-x-0 bottom-4 z-20 flex justify-center px-4">
          <div className="flex items-center gap-3 rounded-full border border-accent/40 bg-panel px-4 py-2 text-sm shadow-lg">
            <span className="text-muted">{sel.length} selected</span>
            <Button variant="ghost" className="px-2 py-1" onClick={() => setSel([])}>
              Clear
            </Button>
            <Button
              className="px-3 py-1"
              disabled={sel.length < 2}
              onClick={() => navigate(`/compare?ids=${sel.join(",")}`)}
              title={sel.length < 2 ? "Select at least 2 analytes" : "Compare selected"}
            >
              <LineChart size={14} /> Compare
            </Button>
          </div>
        </div>
      )}
      {filtered.length === 0 ? (
        <p className="text-sm text-muted">
          {onlyAbnormal ? "Nothing is out of range. 🎉" : `No analytes match “${query}”.`}
        </p>
      ) : (
        <>
          {favSection}
          {body}
        </>
      )}
    </div>
  );
}

type CachedSummary = { content: string; generatedAt: string; basedOnCount: number };

// PanelSummaryCard shows an on-demand whole-panel AI summary. The result is cached
// in localStorage per profile (the backend doesn't store it), with a staleness hint
// when the number of latest results has changed since it was generated.
function PanelSummaryCard({ profileId, currentCount }: { profileId: string; currentCount: number }) {
  const storageKey = `panel-summary:${profileId}`;
  const [summary, setSummary] = useState<CachedSummary | null>(() => {
    try {
      const s = localStorage.getItem(storageKey);
      return s ? (JSON.parse(s) as CachedSummary) : null;
    } catch {
      return null;
    }
  });

  const gen = useMutation({
    mutationFn: () => api.generatePanelSummary(profileId),
    onSuccess: (s) => {
      const cached = { content: s.content, generatedAt: s.generatedAt, basedOnCount: s.basedOnCount };
      setSummary(cached);
      try {
        localStorage.setItem(storageKey, JSON.stringify(cached));
      } catch {
        /* ignore quota / private-mode errors */
      }
    },
  });

  const stale = summary != null && summary.basedOnCount !== currentCount;

  return (
    <Card>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="flex items-center gap-1.5 text-sm font-semibold uppercase tracking-wide text-muted">
          <Sparkles size={14} className="text-accent" /> Health snapshot
        </h2>
        {summary && !gen.isPending && (
          <Button variant="ghost" className="px-2 py-1" onClick={() => gen.mutate()}>
            <RotateCw size={14} /> Regenerate
          </Button>
        )}
      </div>

      {gen.isPending ? (
        <div className="py-4">
          <Spinner label="Summarizing your latest panel…" />
        </div>
      ) : summary ? (
        <div className="mt-2">
          {stale && (
            <div className="mb-3 rounded-md border border-warn/40 bg-warn/10 px-3 py-2 text-xs text-warn">
              Your results have changed since this snapshot. Regenerate to refresh.
            </div>
          )}
          <Markdown>{summary.content}</Markdown>
          <p className="mt-2 text-xs text-muted">
            Generated {new Date(summary.generatedAt).toLocaleString()}
          </p>
        </div>
      ) : (
        <div className="py-2">
          <p className="mb-3 text-sm text-muted">
            An AI overview of your latest panel — what’s out of range, what looks good, and what to
            keep an eye on.
          </p>
          <Button onClick={() => gen.mutate()}>
            <Sparkles size={16} /> Generate health snapshot
          </Button>
        </div>
      )}
      {gen.error && <p className="mt-2 text-sm text-bad">{String(gen.error)}</p>}
    </Card>
  );
}

function ResultCard({
  r,
  selected,
  onToggleSelect,
  onToggleFav,
}: {
  r: Result;
  selected: boolean;
  onToggleSelect: () => void;
  onToggleFav: () => void;
}) {
  const tone = statusTone(r);
  const ref = referenceLabel(r);
  const flag = derivedFlag(r);
  return (
    <div className="relative">
      {/* Checkbox is a sibling of the link (not nested in the anchor) so the native
          toggle fires reliably on touch; the padded label is the tap target. */}
      <label
        className="absolute left-1.5 top-2.5 z-10 flex h-8 w-8 cursor-pointer items-center justify-center"
        title="Select to compare"
      >
        <input
          type="checkbox"
          checked={selected}
          onChange={onToggleSelect}
          className="h-4 w-4 cursor-pointer"
        />
      </label>
      <Link to={`/analytes/${r.analyteId}`}>
        <Card className={clsx("pl-10 transition hover:border-accent", selected && "border-accent")}>
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
    </div>
  );
}
