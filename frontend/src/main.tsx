import React from "react";
import ReactDOM from "react-dom/client";
import * as Sentry from "@sentry/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter } from "react-router";
import { AuthProvider } from "react-oidc-context";
import App from "./App";
import { ProfileProvider } from "./lib/profile";
import { authEnabled, oidcConfig } from "./lib/auth";
import "./index.css";

// DSN and version are baked in at build time (Docker build args → VITE_*);
// local dev builds have neither, so Sentry stays off there.
if (import.meta.env.VITE_SENTRY_DSN) {
  Sentry.init({
    dsn: import.meta.env.VITE_SENTRY_DSN,
    release: `lab-tracker@${import.meta.env.VITE_APP_VERSION || "dev"}`,
    integrations: [Sentry.browserTracingIntegration()],
    // Household-scale traffic: trace every pageload/navigation. API fetches
    // carry the sentry-trace header, so traces continue into the backend.
    tracesSampleRate: 1.0,
  });
}

const queryClient = new QueryClient({
  defaultOptions: { queries: { refetchOnWindowFocus: false, retry: 1 } },
});

const tree = (
  <QueryClientProvider client={queryClient}>
    <ProfileProvider>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </ProfileProvider>
  </QueryClientProvider>
);

// The boundary reports render crashes to Sentry and swaps the white screen
// for a reload prompt.
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <Sentry.ErrorBoundary
      fallback={
        <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-6 text-center">
          <p className="text-lg font-semibold">Something went wrong.</p>
          <button
            className="rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white"
            onClick={() => window.location.reload()}
          >
            Reload
          </button>
        </div>
      }
    >
      {authEnabled ? <AuthProvider {...oidcConfig}>{tree}</AuthProvider> : tree}
    </Sentry.ErrorBoundary>
  </React.StrictMode>,
);
