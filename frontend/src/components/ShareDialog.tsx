import { useState } from "react";
import { createPortal } from "react-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { Button, Input, Spinner, Badge } from "@/components/ui";
import { X, Trash2 } from "lucide-react";

// ShareDialog manages who can access a profile. The owner can add editors by
// email (the target must have signed in once) and revoke access. Co-editors can
// view the member list but not change it (the backend enforces owner-only).
export function ShareDialog({
  profileId,
  profileName,
  canManage,
  onClose,
}: {
  profileId: string;
  profileName: string;
  canManage: boolean; // current user owns the profile
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);

  const members = useQuery({
    queryKey: ["members", profileId],
    queryFn: () => api.listMembers(profileId),
  });

  const invalidate = () => qc.invalidateQueries({ queryKey: ["members", profileId] });

  const add = useMutation({
    mutationFn: () => api.addMember(profileId, email.trim()),
    onSuccess: () => {
      setEmail("");
      setError(null);
      invalidate();
    },
    onError: (e: Error) => setError(e.message),
  });

  const remove = useMutation({
    mutationFn: (userId: string) => api.removeMember(profileId, userId),
    onSuccess: invalidate,
    onError: (e: Error) => setError(e.message),
  });

  // Render through a portal to document.body: the app header uses backdrop-blur,
  // which creates a containing block for position:fixed descendants — without the
  // portal the overlay would be sized to the header, not the viewport.
  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md rounded-xl border border-border bg-panel p-5 shadow-lg"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-base font-semibold">
            Share <span className="text-muted">{profileName}</span>
          </h2>
          <Button variant="ghost" onClick={onClose} title="Close">
            <X size={16} />
          </Button>
        </div>

        {members.isLoading ? (
          <Spinner label="Loading members…" />
        ) : members.isError ? (
          <p className="text-sm text-bad">Failed to load members.</p>
        ) : (
          <ul className="mb-4 space-y-2">
            {members.data?.map((m) => (
              <li
                key={m.userId}
                className="flex items-center justify-between rounded-md border border-border bg-panel2 px-3 py-2"
              >
                <div className="min-w-0">
                  <div className="truncate text-sm">
                    {m.name || m.email || m.userId}
                  </div>
                  {m.name && m.email && (
                    <div className="truncate text-xs text-muted">{m.email}</div>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  <Badge tone={m.isOwner ? "good" : "muted"}>
                    {m.isOwner ? "Owner" : m.role}
                  </Badge>
                  {!m.isOwner && canManage && (
                    <Button
                      variant="ghost"
                      onClick={() => remove.mutate(m.userId)}
                      disabled={remove.isPending}
                      title="Remove access"
                    >
                      <Trash2 size={14} />
                    </Button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}

        {canManage ? (
          <>
            <form
              className="flex items-center gap-2"
              onSubmit={(e) => {
                e.preventDefault();
                if (email.trim()) add.mutate();
              }}
            >
              <Input
                type="email"
                placeholder="Share with email…"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
              <Button type="submit" disabled={add.isPending || !email.trim()}>
                Share
              </Button>
            </form>
            {error && <p className="mt-2 text-sm text-bad">{error}</p>}
            <p className="mt-2 text-xs text-muted">
              The person must have signed in at least once before you can share
              with them. Shared users can view and edit this profile.
            </p>
          </>
        ) : (
          <p className="text-xs text-muted">
            This profile is shared with you. Only the owner can manage sharing.
          </p>
        )}
      </div>
    </div>,
    document.body,
  );
}
