import { type UserManagerSettings } from "oidc-client-ts";

// Runtime config is injected via /config.js (window.__APP_CONFIG__) so the
// OIDC provider URL lives in the deployment, not the image/source.
declare global {
  interface Window {
    __APP_CONFIG__?: { oidcAuthority?: string; oidcClientId?: string };
  }
}

const authority =
  import.meta.env.VITE_OIDC_AUTHORITY ?? window.__APP_CONFIG__?.oidcAuthority ?? "";
const clientId =
  import.meta.env.VITE_OIDC_CLIENT_ID ?? window.__APP_CONFIG__?.oidcClientId ?? "lab-tracker";

// Auth is on only when an authority is configured (prod). Local dev leaves it
// empty, so the app runs without login (backend runs with AUTH_DISABLED).
export const authEnabled = authority !== "";

export const oidcConfig: UserManagerSettings & { onSigninCallback?: () => void } = {
  authority,
  client_id: clientId,
  redirect_uri: window.location.origin + "/",
  post_logout_redirect_uri: window.location.origin + "/",
  scope: "openid profile email offline_access",
  automaticSilentRenew: true,
  // Strip the ?code&state from the URL after a successful login.
  onSigninCallback: () => {
    window.history.replaceState({}, document.title, window.location.pathname);
  },
};

// Current access token, kept in sync from React (see AuthGate) so the non-React
// API client can attach it synchronously without guessing the oidc storage key.
let currentAccessToken: string | null = null;
export function setAccessToken(token: string | null) {
  currentAccessToken = token;
}
export function getAccessToken(): string | null {
  return currentAccessToken;
}

// Bridge so the non-React API client can trigger a re-login on 401.
let unauthorizedHandler: (() => void) | null = null;
export function setUnauthorizedHandler(fn: (() => void) | null) {
  unauthorizedHandler = fn;
}
export function handleUnauthorized() {
  unauthorizedHandler?.();
}
