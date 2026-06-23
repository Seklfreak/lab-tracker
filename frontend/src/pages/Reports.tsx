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
    <Card>
      <div className="overflow-x-auto">
      <table className="w-full min-w-[560px] text-sm">
        <thead>
          <tr className="text-left text-muted">
            <th className="pb-2">File</th>
            <th className="pb-2">Lab</th>
            <th className="pb-2">Collected</th>
            <th className="pb-2">Status</th>
            <th className="pb-2">PDF</th>
            <th className="pb-2 text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          {data.map((r) => {
            const hasDraft = r.status === "parsed" || r.status === "saved";
            const busy =
              r.status === "parsing" ||
              (reparse.isPending && reparse.variables === r.id) ||
              (remove.isPending && remove.variables === r.id);
            return (
              <tr key={r.id} className="border-t border-border">
                <td className="py-2">{r.originalFilename ?? r.id.slice(0, 8)}</td>
                <td className="py-2 text-muted">{r.sourceLab ?? "—"}</td>
                <td className="py-2 text-muted">{r.collectedDate ?? "—"}</td>
                <td className="py-2">
                  <Badge tone={statusTone[r.status]}>{r.status}</Badge>
                </td>
                <td className="py-2">
                  <a href={api.pdfUrl(r.id)} target="_blank" rel="noreferrer" className="text-accent">
                    View
                  </a>
                </td>
                <td className="py-2">
                  <div className="flex items-center justify-end gap-2">
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
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
      </div>
    </Card>
  );
}
