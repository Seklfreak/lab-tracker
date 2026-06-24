# Roadmap / TODO

A scratchpad of where this could go. Nothing here is committed work — just ideas
and rough notes so they aren't lost.

## Near-term

- [ ] **MCP server** — expose lab data over the Model Context Protocol so Claude
  (and other MCP clients) can query results, trends, and the stored AI analyses,
  and maybe trigger uploads/analysis. Could live alongside the Go backend (reuse
  the same queries) or be a thin separate service hitting the existing API.
- [ ] **iOS app** — native client (or a PWA) for: uploading PDFs from the phone
  (share sheet / camera scan), browsing analytes and trends, and reading AI
  analyses. The REST API already exists; the main gap is an auth story for a
  mobile client (today access is only gated by Authentik forward-auth at the
  ingress).

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
- **Auth / multi-user:** still no in-app auth (Authentik gates the deployment).
  A broader record probably needs real per-user accounts + sharing.
- **Privacy:** this is health PII — keep it self-hosted, consider
  encryption-at-rest, and provide export/delete.
