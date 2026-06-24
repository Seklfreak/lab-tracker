import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { api, type Report, type ReportStatus } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { Badge, Button, Card, Spinner } from "@/components/ui";

const statusTone: Record<ReportStatus, "good" | "warn" | "bad" | "muted"> = {
  parsing: "warn",
  parsed: "warn",
  saved: "good",
  error: "bad",
};

export function Reports() {
  const { profileId } = useProfile();
  const qc = useQueryClient();
  const navigate = useNavigate();

  const reports = useQuery({
    queryKey: ["reports", profileId],
    queryFn: () => api.listReports(profileId!),
    enabled: !!profileId,
    refetchInterval: (q) =>
      (q.state.data as Report[] | undefined)?.some((r) => r.status === "parsing") ? 1500 : false,
  });

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ["reports", profileId] });
    qc.invalidateQueries({ queryKey: ["latest", profileId] });
  };

  const reparse = useMutation({
    mutationFn: (id: string) => api.reparseReport(id),
    onSuccess: invalidate,
  });
  const remove = useMutation({
    mutationFn: (id: string) => api.deleteReport(id),
    onSuccess: invalidate,
  });

  if (!profileId) return <p className="text-muted">Select a profile.</p>;
  if (reports.isLoading) return <Spinner label="Loading reports…" />;

  const data = reports.data ?? [];
  if (data.length === 0)
    return (
      <Card>
        <p className="text-muted">No uploads yet.</p>
      </Card>
    );

  return (
    <div className="space-y-3">
      {data.map((r) => {
        const hasDraft = r.status === "parsed" || r.status === "saved";
        const busy =
          r.status === "parsing" ||
          (reparse.isPending && reparse.variables === r.id) ||
          (remove.isPending && remove.variables === r.id);
        return (
          <Card key={r.id}>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <span className="truncate font-medium">
                    {r.originalFilename ?? r.id.slice(0, 8)}
                  </span>
                  <Badge tone={statusTone[r.status]}>{r.status}</Badge>
                </div>
                <div className="mt-1 text-xs text-muted">
                  {r.sourceLab ?? "Unknown lab"} · collected {r.collectedDate ?? "—"}
                </div>
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  onClick={() => void api.openPdf(r.id)}
                  className="px-2 py-1 text-sm text-accent"
                >
                  PDF
                </button>
                {hasDraft && (
                  <Button
                    variant="ghost"
                    className="px-2 py-1"
                    onClick={() => navigate(`/upload?report=${r.id}`)}
                  >
                    Review
                  </Button>
                )}
                <Button
                  variant="ghost"
                  className="px-2 py-1"
                  disabled={busy}
                  onClick={() => reparse.mutate(r.id)}
                  title="Re-run extraction on the stored PDF"
                >
                  Retry
                </Button>
                <Button
                  variant="danger"
                  className="px-2 py-1"
                  disabled={busy}
                  onClick={() => {
                    if (confirm("Delete this report and its saved results?")) remove.mutate(r.id);
                  }}
                >
                  Delete
                </Button>
              </div>
            </div>
          </Card>
        );
      })}
    </div>
  );
}
