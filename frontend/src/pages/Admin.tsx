import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { Card, Spinner } from "@/components/ui";

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
