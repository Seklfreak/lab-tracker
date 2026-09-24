import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api, type CreatedApiToken } from "@/lib/api";
import { Button, Card, Input, Spinner } from "@/components/ui";

function fmtDate(iso: string | null): string {
  if (!iso) return "never";
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? "—"
    : d.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

// Tokens manages personal access tokens: long-lived API credentials for scripts
// and device importers (e.g. the curo-l7 lipid meter importer). A token acts as
// the signed-in user, without admin rights.
export function Tokens() {
  const qc = useQueryClient();
  const [name, setName] = useState("");
  const [created, setCreated] = useState<CreatedApiToken | null>(null);
  const [copied, setCopied] = useState(false);

  const tokens = useQuery({ queryKey: ["tokens"], queryFn: api.listTokens });
  const create = useMutation({
    mutationFn: (n: string) => api.createToken(n),
    onSuccess: (t) => {
      setCreated(t);
      setCopied(false);
      setName("");
      qc.invalidateQueries({ queryKey: ["tokens"] });
    },
  });
  const revoke = useMutation({
    mutationFn: (id: string) => api.revokeToken(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["tokens"] }),
  });

  const rows = tokens.data ?? [];

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-lg font-semibold">API tokens</h1>
        <p className="mt-1 text-sm text-muted">
          Tokens let scripts and device importers use the API as you. Send one as{" "}
          <code>Authorization: Bearer &lt;token&gt;</code>. They can't create other tokens or
          use admin features.
        </p>
      </div>

      <Card>
        <form
          className="flex flex-wrap items-center gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (name.trim()) create.mutate(name.trim());
          }}
        >
          <Input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Token name, e.g. curo-l7 on my laptop"
            className="min-w-0 flex-1"
          />
          <Button type="submit" disabled={!name.trim() || create.isPending}>
            Create token
          </Button>
        </form>
        {create.isError && (
          <p className="mt-2 text-sm text-bad">{(create.error as Error).message}</p>
        )}
        {created && (
          <div className="mt-3 space-y-2 rounded-lg border border-warn/40 bg-warn/10 p-3">
            <p className="text-sm">
              Copy <strong>{created.name}</strong> now. It won't be shown again.
            </p>
            <div className="flex flex-wrap items-center gap-2">
              <code className="min-w-0 flex-1 break-all rounded bg-panel2 px-2 py-1 text-xs">
                {created.token}
              </code>
              <Button
                variant="ghost"
                className="px-2 py-1"
                onClick={() => {
                  void navigator.clipboard.writeText(created.token).then(() => setCopied(true));
                }}
              >
                {copied ? "Copied" : "Copy"}
              </Button>
            </div>
          </div>
        )}
      </Card>

      {tokens.isLoading ? (
        <Spinner label="Loading tokens…" />
      ) : tokens.isError ? (
        <Card>
          <p className="text-bad">{(tokens.error as Error).message}</p>
        </Card>
      ) : rows.length === 0 ? (
        <Card>
          <p className="text-muted">No tokens yet.</p>
        </Card>
      ) : (
        <Card className="divide-y divide-border p-0">
          {rows.map((t) => (
            <div key={t.id} className="flex flex-wrap items-center justify-between gap-3 p-4">
              <div className="min-w-0">
                <div className="truncate font-medium">{t.name}</div>
                <div className="text-xs text-muted">
                  <code>{t.prefix}…</code> · created {fmtDate(t.createdAt)} · last used{" "}
                  {fmtDate(t.lastUsedAt)}
                </div>
              </div>
              <Button
                variant="danger"
                className="px-2 py-1"
                disabled={revoke.isPending && revoke.variables === t.id}
                onClick={() => {
                  if (confirm(`Revoke "${t.name}"? Anything using it will stop working.`))
                    revoke.mutate(t.id);
                }}
              >
                Revoke
              </Button>
            </div>
          ))}
        </Card>
      )}
    </div>
  );
}
