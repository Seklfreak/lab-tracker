import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { useProfile } from "@/lib/profile";
import { Button, Input } from "@/components/ui";

// Shown when the signed-in user owns/was-shared zero profiles. An empty list is
// ambiguous — a brand-new user vs. someone signed in as the wrong identity look
// identical to the API — so instead of guessing, we show who they are and let
// them act: create a first profile, or sign out (header) if that isn't them.
export function EmptyProfiles({ email }: { email?: string | null }) {
  const { setProfileId } = useProfile();
  const qc = useQueryClient();
  const [name, setName] = useState("");

  const create = useMutation({
    mutationFn: () => api.createProfile(name.trim(), null),
    onSuccess: (p) => {
      qc.invalidateQueries({ queryKey: ["profiles"] });
      setProfileId(p.id);
      setName("");
    },
  });

  return (
    <div className="mx-auto flex max-w-md flex-col items-center gap-4 py-16 text-center">
      <h1 className="text-lg font-semibold">No profiles yet</h1>
      <p className="text-sm text-muted">Create a profile to start tracking lab results.</p>
      <form
        className="flex w-full items-center gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          if (name.trim()) create.mutate();
        }}
      >
        <Input
          autoFocus
          placeholder="Profile name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="flex-1"
        />
        <Button type="submit" disabled={!name.trim() || create.isPending}>
          Create profile
        </Button>
      </form>
      {create.isError && (
        <p className="text-sm text-bad">Couldn’t create the profile. Try again.</p>
      )}
      {email && (
        <p className="text-xs text-muted">
          Signed in as {email}. Not you? Use Sign out, top right.
        </p>
      )}
    </div>
  );
}
