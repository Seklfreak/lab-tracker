import { useQuery } from "@tanstack/react-query";
import { api, type ReportStatus } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { Badge, Card, Spinner } from "@/components/ui";

const statusTone: Record<ReportStatus, "good" | "warn" | "bad" | "muted"> = {
  parsing: "warn",
  parsed: "warn",
  saved: "good",
  error: "bad",
};

export function Reports() {
  const { profileId } = useProfile();
  const reports = useQuery({
    queryKey: ["reports", profileId],
    queryFn: () => api.listReports(profileId!),
    enabled: !!profileId,
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
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-muted">
            <th className="pb-2">File</th>
            <th className="pb-2">Lab</th>
            <th className="pb-2">Collected</th>
            <th className="pb-2">Status</th>
            <th className="pb-2">PDF</th>
          </tr>
        </thead>
        <tbody>
          {data.map((r) => (
            <tr key={r.id} className="border-t border-border">
              <td className="py-2">{r.originalFilename ?? r.id.slice(0, 8)}</td>
              <td className="py-2 text-muted">{r.sourceLab ?? "—"}</td>
              <td className="py-2 text-muted">{r.collectedDate ?? "—"}</td>
              <td className="py-2">
                <Badge tone={statusTone[r.status]}>{r.status}</Badge>
              </td>
              <td className="py-2">
                <a
                  href={api.pdfUrl(r.id)}
                  target="_blank"
                  rel="noreferrer"
                  className="text-accent"
                >
                  View
                </a>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  );
}
