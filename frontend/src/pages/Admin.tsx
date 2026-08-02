import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api, type Analyte } from "@/lib/api";
import { Badge, Button, Card, Input, Spinner } from "@/components/ui";

function fmtDate(iso: string): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? "—"
    : d.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

// Admin is the super-user area: every user with how many profiles they own and
// how many are shared with them. The backend gates /api/admin/users to admins,
// so a non-admin reaching this page just sees an error.
export function Admin() {
  const users = useQuery({ queryKey: ["admin", "users"], queryFn: api.adminUsers });

  if (users.isLoading) return <Spinner label="Loading users…" />;
  if (users.isError) {
    return (
      <Card>
        <p className="text-bad">
          {String((users.error as Error)?.message ?? "Failed to load users.")}
        </p>
      </Card>
    );
  }

  const rows = users.data ?? [];
  const totalOwned = rows.reduce((n, u) => n + u.ownedCount, 0);

  return (
    <div className="space-y-4">
      <div className="flex items-baseline justify-between">
        <h1 className="text-lg font-semibold">Users</h1>
        <span className="text-sm text-muted">
          {rows.length} user{rows.length === 1 ? "" : "s"} · {totalOwned} profile
          {totalOwned === 1 ? "" : "s"}
        </span>
      </div>

      {rows.length === 0 ? (
        <Card>
          <p className="text-muted">No users yet.</p>
        </Card>
      ) : (
        <Card className="divide-y divide-border p-0">
          {rows.map((u) => (
            <div key={u.id} className="p-4">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="truncate font-medium">{u.name || u.email || u.oidcSub}</div>
                  {u.email && u.name && (
                    <div className="truncate text-xs text-muted">{u.email}</div>
                  )}
                </div>
                <div className="flex shrink-0 gap-4">
                  <Stat label="owned" value={u.ownedCount} />
                  <Stat label="shared" value={u.sharedCount} muted />
                </div>
              </div>
              <div className="mt-2 flex flex-wrap gap-x-4 gap-y-0.5 text-xs text-muted">
                <span>Joined {fmtDate(u.createdAt)}</span>
                <span>Last seen {fmtDate(u.lastSeenAt)}</span>
              </div>
            </div>
          ))}
        </Card>
      )}

      <AnalyteMerge />
    </div>
  );
}

// AnalyteMerge folds duplicate analytes (the parser sometimes splits one marker
// into several, e.g. "HbA1c" vs "Hemoglobin A1c") into a single kept one. The
// catalog is global, so this affects every profile and is permanent — admin only.
function AnalyteMerge() {
  const qc = useQueryClient();
  const analytes = useQuery({ queryKey: ["analytes"], queryFn: api.listAnalytes });
  const [search, setSearch] = useState("");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [target, setTarget] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [done, setDone] = useState<string | null>(null);

  const all = useMemo(() => analytes.data ?? [], [analytes.data]);
  const byId = useMemo(() => new Map(all.map((a) => [a.id, a])), [all]);
  const chosen = [...selected].map((id) => byId.get(id)).filter(Boolean) as Analyte[];
  // The kept analyte: an explicit pick if still selected, else the first chosen.
  const keep = (target && selected.has(target) ? target : chosen[0]?.id) ?? null;

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return q ? all.filter((a) => a.name.toLowerCase().includes(q)) : all;
  }, [all, search]);

  const merge = useMutation({
    mutationFn: () => api.mergeAnalytes(keep!, [...selected].filter((id) => id !== keep)),
    onSuccess: (a) => {
      setDone(`Merged ${chosen.length - 1} analyte${chosen.length - 1 === 1 ? "" : "s"} into “${a.name}”.`);
      setSelected(new Set());
      setTarget(null);
      setConfirming(false);
      // Analyte ids changed under existing results/dashboards — refetch broadly.
      qc.invalidateQueries();
    },
  });

  function toggle(id: string) {
    setDone(null);
    setConfirming(false);
    setSelected((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }

  return (
    <div className="space-y-3 pt-4">
      <div className="flex items-baseline justify-between">
        <h1 className="text-lg font-semibold">Merge analytes</h1>
        <span className="text-sm text-muted">{all.length} in catalog</span>
      </div>

      {analytes.isLoading ? (
        <Spinner label="Loading analytes…" />
      ) : (
        <Card className="space-y-3">
          <p className="text-sm text-muted">
            Fold duplicates of the same marker into one. This rewrites the shared catalog for{" "}
            <strong>all profiles</strong> and can’t be undone; the merged-away names become aliases,
            so future uploads map to the kept analyte.
          </p>

          <Input
            placeholder="Search analytes…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />

          <div className="max-h-72 divide-y divide-border overflow-y-auto rounded-md border border-border">
            {filtered.slice(0, 200).map((a) => (
              <label key={a.id} className="flex cursor-pointer items-center gap-3 px-3 py-2 hover:bg-border/20">
                <input type="checkbox" checked={selected.has(a.id)} onChange={() => toggle(a.id)} />
                <span className="min-w-0 flex-1 truncate">{a.name}</span>
                {a.category && <Badge>{a.category}</Badge>}
              </label>
            ))}
            {filtered.length === 0 && <p className="px-3 py-4 text-sm text-muted">No matches.</p>}
            {filtered.length > 200 && (
              <p className="px-3 py-2 text-xs text-muted">Showing first 200 — refine your search.</p>
            )}
          </div>

          {chosen.length >= 2 && (
            <div className="space-y-2 rounded-md border border-border bg-panel2 p-3">
              <p className="text-sm font-medium">Keep which one?</p>
              {chosen.map((a) => (
                <label key={a.id} className="flex items-center gap-2 text-sm">
                  <input
                    type="radio"
                    name="mergeTarget"
                    checked={keep === a.id}
                    onChange={() => setTarget(a.id)}
                  />
                  <span className="truncate">{a.name}</span>
                  {a.category && <Badge>{a.category}</Badge>}
                </label>
              ))}
              {confirming ? (
                <div className="flex flex-wrap items-center gap-2 pt-1">
                  <span className="text-sm text-warn">
                    Merge {chosen.length - 1} into “{byId.get(keep!)?.name}”? This is permanent.
                  </span>
                  <Button variant="danger" onClick={() => merge.mutate()} disabled={merge.isPending}>
                    {merge.isPending ? "Merging…" : "Confirm merge"}
                  </Button>
                  <Button variant="ghost" onClick={() => setConfirming(false)} disabled={merge.isPending}>
                    Cancel
                  </Button>
                </div>
              ) : (
                <Button className="mt-1" onClick={() => setConfirming(true)}>
                  Merge {chosen.length - 1} into “{byId.get(keep!)?.name}”
                </Button>
              )}
            </div>
          )}

          {merge.error && <p className="text-sm text-bad">{String((merge.error as Error).message)}</p>}
          {done && <p className="text-sm text-good">{done}</p>}
        </Card>
      )}
    </div>
  );
}

function Stat({ label, value, muted }: { label: string; value: number; muted?: boolean }) {
  return (
    <div className="text-center">
      <div className={`text-base font-semibold tabular-nums ${muted ? "text-muted" : ""}`}>
        {value}
      </div>
      <div className="text-[11px] uppercase tracking-wide text-muted">{label}</div>
    </div>
  );
}
