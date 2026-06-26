# Roadmap / TODO

A scratchpad of where this could go. Nothing here is committed work — just ideas
and rough notes so they aren't lost.

## Done

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

## Near-term

- [ ] **iOS app** — native client (or a PWA) for: uploading PDFs from the phone
  (share sheet / camera scan), browsing analytes and trends, and reading AI
  analyses. The REST API already exists and is token-auth ready: do the OIDC
  Authorization Code + PKCE flow against Authentik (e.g. `ASWebAuthenticationSession`),
  send the access token as `Bearer`. The only server-side step is adding the app's
  redirect URI (e.g. `labtracker://auth/callback`) to the existing `lab-tracker`
  OIDC client — backend JWT validation already covers it.
  - **App Store approval (self-hosted, no shared backend):** because the app
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

- [x] **Per-user data isolation** (2026-06-26) — auth was gate-only (every
  signed-in user saw *all* profiles). Now each user sees only the profiles they
  own or that are shared with them, and shared users can co-edit.
  - **Model:** a `users` table keyed on the OIDC `sub`, upserted from the JWT per
    request (`authMiddleware`); `profiles.owner_user_id` + a
    `profile_members(profile_id, user_id, role)` table for sharing. Every
    profile/result/report query is scoped to owned-or-shared (`GetProfileForUser`
    / `ListProfilesForUser`); by-id report/result endpoints resolve their profile
    and access-check it. Pre-existing profiles are migrated to `ADMIN_OIDC_SUB`
    at startup (`db.BootstrapOwner`); local dev maps to a fixed dev user.
  - **Sharing:** owner-only `GET/POST/DELETE /api/profiles/{id}/members`; share
    by email (target must have logged in once). Frontend Share dialog +
    owned/shared badge.
  - **MCP identity:** scoped to one configured user via `MCP_USER_SUB`
    (resolves the `sub` to a user; tools see only that user's profiles). Unset =
    unscoped, logged loudly.

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
- **Auth / multi-user:** see the **Per-user data isolation** item above.
- **Privacy:** this is health PII — keep it self-hosted, consider
  encryption-at-rest, and provide export/delete.
