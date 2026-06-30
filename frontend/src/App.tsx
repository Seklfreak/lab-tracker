import { lazy, Suspense, useEffect } from "react";
import { NavLink, Route, Routes } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { clsx } from "clsx";
import { useAuth } from "react-oidc-context";
import {
  Activity,
  LayoutGrid,
  Upload as UploadIcon,
  FileText,
  LogOut,
  PersonStanding,
  Shield,
} from "lucide-react";
import { ProfileSwitcher } from "@/components/ProfileSwitcher";
import { EmptyProfiles } from "@/components/EmptyProfiles";
import { Button, Spinner } from "@/components/ui";
import { api, health } from "@/lib/api";
import { authEnabled, setAccessToken, setUnauthorizedHandler } from "@/lib/auth";

// Lazy-load route pages so each (and Recharts, pulled in by AnalyteDetail) is a
// separate chunk instead of one big bundle.
const Dashboard = lazy(() => import("@/pages/Dashboard").then((m) => ({ default: m.Dashboard })));
const AnalyteDetail = lazy(() =>
  import("@/pages/AnalyteDetail").then((m) => ({ default: m.AnalyteDetail })),
);
const Upload = lazy(() => import("@/pages/Upload").then((m) => ({ default: m.Upload })));
const Reports = lazy(() => import("@/pages/Reports").then((m) => ({ default: m.Reports })));
const Compare = lazy(() => import("@/pages/Compare").then((m) => ({ default: m.Compare })));
const Body = lazy(() => import("@/pages/Body").then((m) => ({ default: m.Body })));
const Admin = lazy(() => import("@/pages/Admin").then((m) => ({ default: m.Admin })));

// RequireAuth gates the app behind OIDC login (no-op when auth is disabled).
function RequireAuth({ children }: { children: React.ReactNode }) {
  if (!authEnabled) return <>{children}</>;
  return <AuthGate>{children}</AuthGate>;
}

// Set just before signoutRedirect so that, on return to the app, AuthGate shows
// a "signed out" landing instead of immediately bouncing back into login (which
// otherwise loops as a perpetual "Signing in…" spinner, especially on iOS).
const SIGNED_OUT_KEY = "lt:signedOut";

function AuthGate({ children }: { children: React.ReactNode }) {
  const auth = useAuth();
  const justSignedOut = sessionStorage.getItem(SIGNED_OUT_KEY) === "1";

  // Keep the API client's token in sync. Set synchronously during render so it's
  // available before child components fire their first request.
  setAccessToken(auth.isAuthenticated ? (auth.user?.access_token ?? null) : null);

  // Let the API client trigger a re-login on 401.
  useEffect(() => {
    setUnauthorizedHandler(() => void auth.signinRedirect());
    return () => setUnauthorizedHandler(null);
  }, [auth]);

  // Once signed in, clear the just-signed-out marker.
  useEffect(() => {
    if (auth.isAuthenticated) sessionStorage.removeItem(SIGNED_OUT_KEY);
  }, [auth.isAuthenticated]);

  // Kick off the login redirect once we know the user isn't signed in — unless
  // they just signed out, in which case we show a landing with a Sign in button.
  // We depend on the specific auth flags rather than the whole `auth` object on
  // purpose, so this doesn't re-run on every unrelated auth state change.
  useEffect(() => {
    if (
      !auth.isLoading &&
      !auth.isAuthenticated &&
      !auth.error &&
      !auth.activeNavigator &&
      !justSignedOut
    ) {
      void auth.signinRedirect();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
    if (justSignedOut) {
      return (
        <div className="flex min-h-screen flex-col items-center justify-center gap-4 text-sm">
          <p className="text-muted">You’ve been signed out.</p>
          <Button
            onClick={() => {
              sessionStorage.removeItem(SIGNED_OUT_KEY);
              void auth.signinRedirect();
            }}
          >
            Sign in
          </Button>
        </div>
      );
    }
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
      onClick={() => {
        sessionStorage.setItem(SIGNED_OUT_KEY, "1");
        void auth.signoutRedirect();
      }}
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
      title={label}
      className={({ isActive }) =>
        clsx(
          "flex items-center gap-2 rounded-md px-2.5 py-2 text-sm font-medium transition sm:px-3",
          isActive ? "bg-accent/15 text-accent" : "text-muted hover:bg-panel2",
        )
      }
    >
      {icon}
      <span className="hidden sm:inline">{label}</span>
    </NavLink>
  );
}

export default function App() {
  return (
    <RequireAuth>
      <AppShell />
    </RequireAuth>
  );
}

function AppShell() {
  // Drives the conditional Admin nav link; the backend independently gates the
  // admin endpoints, so this is purely cosmetic.
  const me = useQuery({ queryKey: ["me"], queryFn: api.me });

  // A signed-in user with zero profiles (new account, or signed in as the wrong
  // identity) gets a clear empty state instead of a blank dashboard. Shares the
  // ["profiles"] query with the header switcher, so no extra request.
  const profiles = useQuery({ queryKey: ["profiles"], queryFn: api.listProfiles });
  const noProfiles = profiles.isSuccess && profiles.data.length === 0;

  return (
    <div className="min-h-full">
        <header className="sticky top-0 z-30 border-b border-border bg-bg/80 backdrop-blur">
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
              <NavItem to="/body" icon={<PersonStanding size={16} />} label="Body" />
              {me.data?.isAdmin && (
                <NavItem to="/admin" icon={<Shield size={16} />} label="Admin" />
              )}
            </nav>
          </div>
        </header>

        <main className="mx-auto max-w-6xl px-4 py-6 sm:px-6">
          {noProfiles ? (
            <EmptyProfiles email={me.data?.email} />
          ) : (
            <Suspense fallback={<Spinner label="Loading…" />}>
              <Routes>
                <Route path="/" element={<Dashboard />} />
                <Route path="/analytes/:analyteId" element={<AnalyteDetail />} />
                <Route path="/upload" element={<Upload />} />
                <Route path="/compare" element={<Compare />} />
                <Route path="/body" element={<Body />} />
                <Route path="/reports" element={<Reports />} />
                <Route path="/admin" element={<Admin />} />
              </Routes>
            </Suspense>
          )}
        </main>

        <VersionFooter />
    </div>
  );
}

// Shows the deployed versions: web is baked in at build time; api is fetched
// (they're released and deployed independently, so they can differ).
function VersionFooter() {
  const apiHealth = useQuery({
    queryKey: ["health"],
    queryFn: health,
    staleTime: Infinity,
    retry: false,
  });
  return (
    <footer className="mx-auto max-w-6xl px-4 pb-6 text-center text-xs text-muted sm:px-6">
      web {__APP_VERSION__}
      {apiHealth.data?.version ? ` · api ${apiHealth.data.version}` : ""}
    </footer>
  );
}
