# Roadmap / TODO

A scratchpad of where this could go. Nothing here is committed work — just ideas
and rough notes so they aren't lost.

## Done

- [x] **App-level OIDC auth** (2026-06-25) — Authentik OIDC: backend validates
  Bearer JWTs on `/api` (by issuer), SPA does Authorization Code + PKCE via
  react-oidc-context. Forward-auth removed. Gate-only (all logged-in allowed-group
  users share all profiles). The API is now token-auth and mobile-ready.

## Near-term

- [ ] **MCP server** — expose lab data over the Model Context Protocol so Claude
  (and other MCP clients) can query results, trends, and the stored AI analyses,
  and maybe trigger uploads/analysis. Could live alongside the Go backend (reuse
  the same queries) or be a thin separate service hitting the existing API.
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
- **Auth / multi-user:** app-level OIDC is in place, but it's gate-only — every
  authenticated user shares all profiles. A broader record likely needs per-user
  ownership + sharing (a `users` table keyed on the OIDC `sub`, profile owners,
  query scoping). Deferred until actually needed.
- **Privacy:** this is health PII — keep it self-hosted, consider
  encryption-at-rest, and provide export/delete.
