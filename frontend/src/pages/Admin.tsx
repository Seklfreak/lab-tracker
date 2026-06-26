import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { Card, Spinner } from "@/components/ui";

function fmtDate(iso: string): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleString();
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

      <Card className="overflow-x-auto p-0">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-left text-xs uppercase tracking-wide text-muted">
              <th className="px-4 py-3 font-medium">User</th>
              <th className="px-4 py-3 text-right font-medium">Owned</th>
              <th className="px-4 py-3 text-right font-medium">Shared</th>
              <th className="px-4 py-3 font-medium">Joined</th>
              <th className="px-4 py-3 font-medium">Last seen</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((u) => (
              <tr key={u.id} className="border-b border-border last:border-0">
                <td className="px-4 py-3">
                  <div className="font-medium">{u.name || u.email || u.oidcSub}</div>
                  {u.email && u.name && (
                    <div className="text-xs text-muted">{u.email}</div>
                  )}
                </td>
                <td className="px-4 py-3 text-right tabular-nums">{u.ownedCount}</td>
                <td className="px-4 py-3 text-right tabular-nums text-muted">
                  {u.sharedCount}
                </td>
                <td className="px-4 py-3 text-muted">{fmtDate(u.createdAt)}</td>
                <td className="px-4 py-3 text-muted">{fmtDate(u.lastSeenAt)}</td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr>
                <td className="px-4 py-6 text-muted" colSpan={5}>
                  No users yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </Card>
    </div>
  );
}
