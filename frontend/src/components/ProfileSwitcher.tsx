import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { Button, Input, Select, Badge } from "@/components/ui";
import { ShareDialog } from "@/components/ShareDialog";
import { Plus, Share2 } from "lucide-react";

export function ProfileSwitcher() {
  const { profileId, setProfileId } = useProfile();
  const qc = useQueryClient();
  const [adding, setAdding] = useState(false);
  const [name, setName] = useState("");
  const [sharing, setSharing] = useState(false);

  const profiles = useQuery({ queryKey: ["profiles"], queryFn: api.listProfiles });
  const current = profiles.data?.find((p) => p.id === profileId);

  const create = useMutation({
    mutationFn: () => api.createProfile(name.trim(), null),
    onSuccess: (p) => {
      qc.invalidateQueries({ queryKey: ["profiles"] });
      setProfileId(p.id);
      setName("");
      setAdding(false);
    },
  });

  // Auto-select first profile if none chosen.
  if (!profileId && profiles.data && profiles.data.length > 0) {
    setProfileId(profiles.data[0].id);
  }

  return (
    <div className="flex items-center gap-2">
      <span className="hidden text-sm text-muted sm:inline">Profile</span>
      {adding ? (
        <form
          className="flex items-center gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (name.trim()) create.mutate();
          }}
        >
          <Input
            autoFocus
            placeholder="Name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-40"
          />
          <Button type="submit" disabled={create.isPending}>
            Add
          </Button>
          <Button type="button" variant="ghost" onClick={() => setAdding(false)}>
            Cancel
          </Button>
        </form>
      ) : (
        <>
          <Select
            className="w-40 sm:w-48"
            value={profileId ?? ""}
            onChange={(e) => setProfileId(e.target.value || null)}
          >
            {(!profiles.data || profiles.data.length === 0) && (
              <option value="">No profiles</option>
            )}
            {profiles.data?.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </Select>
          {current && !current.isOwner && <Badge tone="muted">Shared</Badge>}
          {current && (
            <Button
              variant="ghost"
              onClick={() => setSharing(true)}
              title="Share profile"
            >
              <Share2 size={16} />
            </Button>
          )}
          <Button variant="ghost" onClick={() => setAdding(true)} title="Add profile">
            <Plus size={16} />
          </Button>
        </>
      )}
      {sharing && current && (
        <ShareDialog
          profileId={current.id}
          profileName={current.name}
          canManage={current.isOwner}
          onClose={() => setSharing(false)}
        />
      )}
    </div>
  );
}
