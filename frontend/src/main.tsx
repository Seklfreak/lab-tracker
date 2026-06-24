import React from "react";
import ReactDOM from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter } from "react-router-dom";
import { AuthProvider } from "react-oidc-context";
import App from "./App";
import { ProfileProvider } from "./lib/profile";
import { authEnabled, oidcConfig } from "./lib/auth";
import "./index.css";

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

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    {authEnabled ? <AuthProvider {...oidcConfig}>{tree}</AuthProvider> : tree}
  </React.StrictMode>,
);
