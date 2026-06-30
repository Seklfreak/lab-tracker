# Roadmap / TODO

A scratchpad of where this could go. Nothing here is committed work — just ideas
and rough notes so they aren't lost.

## Done

- [x] **Birthdate + weight/height + BMI** (2026-06-30) — profiles gained an edit
  path (`PATCH /api/profiles/{id}`) for birthdate; a `body_measurements` table
  tracks self-entered weight/height over time (canonical kg/cm), exposed at
  `/api/profiles/{id}/body`. BMI is derived from the latest weight/height, and
  age/weight/height/BMI now feed the AI analysis. Web (Body page) and iOS (Body
  sheet) both let you edit birthdate and add/track measurements with unit
  toggles (kg/lb, cm/in). Kept separate from `lab_results` so the PDF pipeline is
  untouched.
- [x] **Version display** (2026-06-27) — web/api/mcp are stamped with the release
  version at build time (Vite define / Go ldflags). The web footer shows its own
  version plus the api's (read from the public `/health`, which now also returns
  `version`); they're deployed independently so can differ. mcp reports its
  version in the MCP handshake.
- [x] **App-level OIDC auth** (2026-06-25) — Authentik OIDC: backend validates
  Bearer JWTs on `/api` (by issuer), SPA does Authorization Code + PKCE via
  react-oidc-context. Forward-auth removed. Gate-only (all logged-in allowed-group
  users share all profiles). The API is now token-auth and mobile-ready.
- [x] **MCP server** (2026-06-25) — `cmd/mcp` exposes lab data over the Model
  Context Protocol (Streamable HTTP): list profiles, latest results, analyte trends,
  search, and read/generate the stored AI analyses. DB-direct (reuses the sqlc
  queries). Deployed as a claude.ai connector via Cloudflare Access Managed OAuth in
  the `mcp` namespace.
- [x] **Versioned releases + CI/CD** (2026-06-26) — multi-arch images build on
  native arm64/amd64 runners (no QEMU). Every green commit to `main` auto-cuts a
  semver release: Claude (Haiku) picks the bump — or skips non-shipping (docs/CI)
  changes — and writes the GitHub release notes; deploys pin explicit versions
  (off `:latest`). Renovate keeps dependencies current with auto-merge.
- [x] **Dashboard & analysis improvements** (2026-06-26) — code-split frontend
  (faster first load); whole-panel "Health snapshot" AI summary; needs-attention
  filter; CSV + print/PDF export; unit-normalized trend charts; duplicate-upload
  guard; post-save "what changed" diff; multi-analyte Compare overlay.
- [x] **Per-user data isolation + sharing** (2026-06-26) — auth was gate-only
  (every signed-in user saw *all* profiles). Now each user sees only the profiles
  they own or that are shared with them, and shared users can co-edit.
  - **Model:** a `users` table keyed on the OIDC `sub`, upserted from the JWT per
    request (`authMiddleware`); `profiles.owner_user_id` + a
    `profile_members(profile_id, user_id, role)` table for sharing. Every
    profile/result/report query is scoped to owned-or-shared (`GetProfileForUser`
    / `ListProfilesForUser`); by-id report/result endpoints resolve their profile
    and access-check it. Legacy profiles were migrated to an admin user at startup
    (`db.BootstrapOwner`); local dev maps to a fixed dev user.
  - **Sharing:** owner-only `GET/POST/DELETE /api/profiles/{id}/members`; share
    by email (target must have logged in once). Frontend Share dialog +
    owned/shared badge.
  - **MCP identity:** per-request, derived from the Cloudflare Access identity
    JWT (`Cf-Access-Jwt-Assertion`) Access injects after the connector OAuth
    login. The MCP server validates it against the team certs, maps the email to
    a user, and scopes every tool to that user (`CF_ACCESS_TEAM_DOMAIN` +
    `CF_ACCESS_AUD`); unset = unscoped (local dev).
- [x] **Super-user admin area** (2026-06-26) — `ADMIN_EMAILS` allowlist (matched
  against the JWT email) gates `/api/me` (returns `isAdmin`) and the admin-only
  `/api/admin/users`, which lists every user with their owned/shared profile
  counts. Frontend: an Admin nav link + table, shown only to admins.
- [x] **Frontend ESLint** (2026-06-26) — flat-config ESLint with
  `react-hooks/rules-of-hooks` (error) + `exhaustive-deps` (warn), run in CI.
  Catches hook-order bugs that `tsc`/`vite build` can't (e.g. a hook after an
  early return → white screen on save).

## Near-term

- [~] **iOS app** — native SwiftUI client in [`ios/`](../ios/README.md).
  - **MVP shipped (2026-06-26):** you configure only the server URL → profiles →
    dashboard (latest value per analyte, grouped, color-coded) → analyte detail
    (Swift Charts trend + readings + the stored AI analysis, markdown-rendered).
    Runs on device. xcodegen project, no hand-edited `.xcodeproj`; nothing about
    a specific server is hardcoded.
  - [x] **OIDC sign-in (2026-06-26)** — Authorization Code + PKCE via
    `ASWebAuthenticationSession`. The app reads the provider (issuer + client id)
    from the server's own `{serverURL}/config.js`, so only the server URL is
    entered. Redirect `dev.winktech.labtracker://auth/callback`. Tokens in the
    Keychain, auto-refresh + retry-on-401. **Verified end-to-end on a physical
    device.**
    - [x] **Fix token-refresh race (2026-06-28)** — concurrent API requests (e.g.
      the analyte detail screen fetches trend + analysis at once) each triggered
      their own refresh, so two overlapping refreshes spent the same rotating
      Authentik refresh token; the second was rejected and signed the user out,
      surfacing as `401 invalid token`. Refreshes are now coalesced onto a single
      in-flight task. A 401 on load also offers a **Sign in** button right in the
      error view, so a broken session can be recovered without digging through
      Settings to sign out + back in.
  - [x] **TestFlight via CI (2026-06-29)** — bundle id moved to
    `dev.winktech.labtracker` (US paid Apple Developer account) and a tag-triggered
    [`testflight.yaml`](../.github/workflows/testflight.yaml) archives + uploads
    using App Store Connect API-key cloud signing. Dispatched from the release
    flow; dormant until the `APP_STORE_CONNECT_*` / `APP_STORE_TEAM_ID` secrets are
    set. See the [iOS README](../ios/README.md#testflight-ci).
  - [x] **Visual redesign (2026-06-29)** — gave the app an identity beyond stock
    SwiftUI: brand teal (matching the icon), a status palette that encodes
    direction (in-range teal / high coral / low indigo), tabular values, a
    dashboard summary header, and the signature **reference-range track** on
    each row. The detail screen gained a value hero + a trend chart with the
    reference band shaded behind the line. See
    [`Views/RangeTrack.swift`](../ios/LabTracker/Views/RangeTrack.swift).
  - [x] **Onboarding + Face ID + dashboard parity (2026-06-29)** — first-run
    server-URL onboarding (live-validated against `/health`, no default URL); an
    optional Face ID / Touch ID app lock; an About screen; and dashboard parity
    with web — sort options (category / name / readings / recent), favorites
    pinned on top (swipe to toggle), and a tappable out-of-range filter.
  - [ ] **Smooth out the sign-in / auth flow** — works, but the transition into
    and out of the web-auth sheet is a bit janky; polish later.
  - [ ] **PDF upload** from the phone (share sheet / camera scan).
  - [ ] **App Store approval (self-hosted, no shared backend):** because the app
    points at the user's own server, plan around Apple's review guidelines so a
    reviewer can exercise it without our infra (the "I can't give you a login"
    problem). Strategy is "bring your own server" as a first-class, reviewable
    flow:
    1. **In-app demo/sandbox mode** — local seeded sample data, one tap, no
       network. Biggest win: can't go stale or go down mid-review, fully under
       our control. (Guards against guideline 2.1 — reviewer must be able to
       use full functionality.)
    2. **Pre-auth onboarding content** — explain "client for self-hosted
       lab-tracker, connect your own server" + a server-config screen, so the
       first screen isn't a blank login wall (guards against guideline 4.2
       minimum-functionality rejection).
    3. **Demo video** in App Review Notes showing the connected experience as
       backup proof; spell out demo-mode + (optionally) a temporary review
       server URL/creds in the notes field.
    4. Optional temporary public review instance — nice-to-have, not required
       if 1–3 are solid.
    - Gotchas: Sign in with Apple only required if we add social login (our own
      SSO/username-password doesn't trigger it); privacy nutrition labels +
      privacy policy URL still mandatory; every app update is re-reviewed, so
      keep demo mode in the app permanently.

## Bigger direction: a general health record (not just labs)

This could grow from "lab results" into a personal health chart / mini-EHR:

- [ ] **Biometrics / health stats over time** — height, weight, BMI, blood
  pressure, heart rate, etc. Age is already captured (profile date of birth).
  These behave just like analytes (a value + unit + date + trend), so the
  existing analyte/result model likely extends to them with little change.
- [ ] **Apple Health integration** — import biometrics / vitals / workouts from
  HealthKit (via the iOS app) so they don't have to be entered by hand.
- [ ] **Vaccinations / immunizations** — date, vaccine, dose, lot, provider.
- [ ] **Procedures & visits** — surgeries, imaging, ED visits, encounters.
- [ ] **Conditions / medications / allergies** — the rest of a problem list if
  this becomes a real record.

### Notes / open questions

- **Data model:** measurements (labs, biometrics) fit the current
  analyte + result shape (numeric/qualitative value, unit, reference, date).
  Vaccinations and procedures are *events*, not measurements — probably a
  separate "events" model rather than forcing them into results.
- **Auth / multi-user:** done — see **Per-user data isolation + sharing** under
  Done above; new event/record types just reuse the same per-user scoping.
- **Privacy:** this is health PII — keep it self-hosted, consider
  encryption-at-rest, and provide export/delete.
