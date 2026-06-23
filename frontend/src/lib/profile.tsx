import { createContext, useContext, useEffect, useState, type ReactNode } from "react";

interface ProfileContextValue {
  profileId: string | null;
  setProfileId: (id: string | null) => void;
}

const ProfileContext = createContext<ProfileContextValue>({
  profileId: null,
  setProfileId: () => {},
});

const STORAGE_KEY = "labtracker.profileId";

export function ProfileProvider({ children }: { children: ReactNode }) {
  const [profileId, setProfileIdState] = useState<string | null>(() =>
    localStorage.getItem(STORAGE_KEY),
  );

  useEffect(() => {
    if (profileId) localStorage.setItem(STORAGE_KEY, profileId);
    else localStorage.removeItem(STORAGE_KEY);
  }, [profileId]);

  return (
    <ProfileContext.Provider value={{ profileId, setProfileId: setProfileIdState }}>
      {children}
    </ProfileContext.Provider>
  );
}

export function useProfile() {
  return useContext(ProfileContext);
}
