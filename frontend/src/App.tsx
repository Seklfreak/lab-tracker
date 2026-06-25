import { useEffect } from "react";
import { NavLink, Route, Routes } from "react-router-dom";
import { clsx } from "clsx";
import { useAuth } from "react-oidc-context";
import { Activity, LayoutGrid, Upload as UploadIcon, FileText, LogOut } from "lucide-react";
import { ProfileSwitcher } from "@/components/ProfileSwitcher";
import { Spinner } from "@/components/ui";
import { authEnabled, setAccessToken, setUnauthorizedHandler } from "@/lib/auth";
import { Dashboard } from "@/pages/Dashboard";
import { AnalyteDetail } from "@/pages/AnalyteDetail";
import { Upload } from "@/pages/Upload";
import { Reports } from "@/pages/Reports";

// RequireAuth gates the app behind OIDC login (no-op when auth is disabled).
function RequireAuth({ children }: { children: React.ReactNode }) {
  if (!authEnabled) return <>{children}</>;
  return <AuthGate>{children}</AuthGate>;
}

function AuthGate({ children }: { children: React.ReactNode }) {
  const auth = useAuth();

  // Keep the API client's token in sync. Set synchronously during render so it's
  // available before child components fire their first request.
  setAccessToken(auth.isAuthenticated ? (auth.user?.access_token ?? null) : null);

  // Let the API client trigger a re-login on 401.
  useEffect(() => {
    setUnauthorizedHandler(() => void auth.signinRedirect());
    return () => setUnauthorizedHandler(null);
  }, [auth]);

  // Kick off the login redirect once we know the user isn't signed in.
  useEffect(() => {
    if (!auth.isLoading && !auth.isAuthenticated && !auth.error && !auth.activeNavigator) {
      void auth.signinRedirect();
    }
  }, [auth.isLoading, auth.isAuthenticated, auth.error, auth.activeNavigator]);

  if (auth.error) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-3 text-sm">
        <p className="text-bad">Sign-in failed: {auth.error.message}</p>
        <button className="text-accent" onClick={() => void auth.signinRedirect()}>
          Try again
        </button>
      </div>
    );
  }
  if (!auth.isAuthenticated) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Spinner label="Signing in…" />
      </div>
    );
  }
  return <>{children}</>;
}

function UserMenu() {
  if (!authEnabled) return null;
  return <UserMenuInner />;
}

function UserMenuInner() {
  const auth = useAuth();
  const who =
    (auth.user?.profile.email as string | undefined) ??
    (auth.user?.profile.preferred_username as string | undefined) ??
    "Account";
  return (
    <button
      onClick={() => void auth.signoutRedirect()}
      title="Sign out"
      className="flex items-center gap-1.5 rounded-md px-2 py-1 text-sm text-muted hover:bg-panel2 hover:text-text"
    >
      <LogOut size={16} />
      <span className="hidden max-w-[12rem] truncate sm:inline">{who}</span>
    </button>
  );
}

function NavItem({
  to,
  icon,
  label,
}: {
  to: string;
  icon: React.ReactNode;
  label: string;
}) {
  return (
    <NavLink
      to={to}
      end={to === "/"}
      className={({ isActive }) =>
        clsx(
          "flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition",
          isActive ? "bg-accent/15 text-accent" : "text-muted hover:bg-panel2",
        )
      }
    >
      {icon}
      {label}
    </NavLink>
  );
}

export default function App() {
  return (
    <RequireAuth>
      <div className="min-h-full">
        <header className="sticky top-0 z-10 border-b border-border bg-bg/80 backdrop-blur">
          {/* Mobile: brand + profile on row 1, nav wraps to a full-width row 2.
              sm+: single row brand | nav | profile. */}
          <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3 sm:px-6">
            <div className="flex items-center gap-2 font-semibold">
              <Activity className="text-accent" size={20} />
              Lab Tracker
            </div>
            <div className="order-2 ml-auto flex items-center gap-2 sm:order-3">
              <ProfileSwitcher />
              <UserMenu />
            </div>
            <nav className="order-3 flex w-full items-center justify-center gap-1 sm:order-2 sm:ml-2 sm:w-auto sm:justify-start">
              <NavItem to="/" icon={<LayoutGrid size={16} />} label="Dashboard" />
              <NavItem to="/upload" icon={<UploadIcon size={16} />} label="Upload" />
              <NavItem to="/reports" icon={<FileText size={16} />} label="Reports" />
            </nav>
          </div>
        </header>

        <main className="mx-auto max-w-6xl px-4 py-6 sm:px-6">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/analytes/:analyteId" element={<AnalyteDetail />} />
            <Route path="/upload" element={<Upload />} />
            <Route path="/reports" element={<Reports />} />
          </Routes>
        </main>
      </div>
    </RequireAuth>
  );
}
