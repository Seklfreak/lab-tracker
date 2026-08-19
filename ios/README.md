# Lab Tracker — iOS

A native SwiftUI client for the lab-tracker API: pick a profile, browse the
latest value per analyte, drill into a trend chart + readings, and read the
stored AI analysis.

## Requirements

- Xcode 26+ (deployment target iOS 17).
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`.

The `.xcodeproj` is generated from [`project.yml`](project.yml) and is **not**
checked in. Generate it before opening/building:

```bash
cd ios
xcodegen generate
open LabTracker.xcodeproj      # or build from the CLI (below)
```

## Run

First launch shows an onboarding screen: enter your **server URL**, which is
live-tested against `{serverURL}/health` (a Lab Tracker server answers with its
version) before **Continue** is enabled. There's no default — you can change it
later under gear → Settings, where the same validation applies.

- **Local dev:** enter `http://localhost:8080`. Run the backend with
  `AUTH_DISABLED=true`; the simulator reaches the host's localhost and no auth is
  needed.
- **A real server:** its https URL, then tap **Sign in**. The app reads the
  server's published OIDC config from `{serverURL}/config.js` (the same one the
  web app uses — nothing hardcoded), runs Authorization Code + PKCE via
  `ASWebAuthenticationSession`, and stores the tokens in the Keychain (auto-
  refresh).

## Run on your iPhone

CLI provisioning needs an interactive Apple ID login, so use Xcode:

1. `xcodegen generate && open LabTracker.xcodeproj`
2. Select the **LabTracker** target → **Signing & Capabilities** → check
   *Automatically manage signing* and pick your **Team** (re-sign in to your
   Apple ID under Xcode ▸ Settings ▸ Accounts if prompted).
3. Plug in the iPhone (trust it), select it as the run destination, **Run** (⌘R).
4. On the phone, first run only: Settings ▸ General ▸ VPN & Device Management ▸
   trust your developer certificate.
5. In the app, set the server URL to your https server and **Sign in**.
   (`localhost` won't work from a physical phone — use the real server.)

CLI build + run on a simulator:

```bash
xcodegen generate
xcodebuild -project LabTracker.xcodeproj -target LabTracker \
  -sdk iphonesimulator -configuration Debug -arch arm64 \
  CODE_SIGNING_ALLOWED=NO SYMROOT="$PWD/build" build
xcrun simctl boot "iPhone 17"
xcrun simctl install booted build/Debug-iphonesimulator/LabTracker.app
xcrun simctl launch booted dev.winktech.labtracker
```

## Apple Health background sync

Settings → **Apple Health** turns on automatic import of new body metrics (weight,
vitals, blood pressure) into a chosen profile. Two layers:

- **Auto-sync on open** works out of the box — an anchored query runs whenever the
  app becomes active and uploads anything new. No entitlement, works in the
  Simulator.
- **True background delivery** (the app syncs even when closed, ~hourly) uses the
  `com.apple.developer.healthkit.background-delivery` entitlement (in
  [`LabTracker/LabTracker.entitlements`](LabTracker/LabTracker.entitlements)) — now
  live: the App ID has HealthKit background delivery enabled, the App Store
  provisioning profile carries the entitlement, and `APP_STORE_PROFILE` holds that
  profile so [`testflight.yaml`](../.github/workflows/testflight.yaml) signs with
  it. If the entitlement ever needs re-provisioning (e.g. a new distribution
  cert/profile), regenerate the App Store profile for `dev.winktech.labtracker` and
  refresh the `APP_STORE_PROFILE` secret — an entitlement in the app without a
  matching profile fails App Store validation.

**Checking it works:** Settings → Apple Health shows **Last synced** (with the
count of new samples) and **Last background sync** — the latter advances only when
an observer fires with the app closed, so if it moves while you haven't opened the
app, background delivery is working. `HealthSync` also logs via `os.Logger`
(subsystem `dev.winktech.labtracker`, category `healthsync`); with the iPhone
connected to a Mac, filter that subsystem in **Console.app** to watch
`background wake: observer fired` / `sync done` lines live, even during a
background wake.

## TestFlight (CI)

Every version tag uploads a build to TestFlight via
[`.github/workflows/testflight.yaml`](../.github/workflows/testflight.yaml)
(also runnable from the Actions tab). Signing is **App Store Connect API-key
cloud signing** (`xcodebuild -allowProvisioningUpdates`) — no certs or profiles
live in the repo. The job is dormant until these repository secrets are set, and
no-ops cleanly otherwise:

- `APP_STORE_CONNECT_KEY_ID` / `APP_STORE_CONNECT_ISSUER_ID` / `APP_STORE_CONNECT_API_KEY`
  — an App Store Connect API key (App Manager role): the Key ID, its Issuer ID,
  and the `.p8` contents.
- `APP_STORE_TEAM_ID` — the paid Apple Developer Team ID.

One-time setup on the Apple side: register the explicit App ID
`dev.winktech.labtracker`, then create the matching app record in App Store
Connect (the first upload fails without it). The marketing version comes from the
tag; the build number is the workflow run number.

**Changelog → "What to Test":** after the upload, the job sets the build's
TestFlight test notes to that release's changelog (the tag's GitHub Release body,
which `release.yaml` writes). It polls the App Store Connect API for the freshly
uploaded build, then creates/updates its `betaBuildLocalizations` `whatsNew`
(see [`scripts/testflight_whats_new.py`](../scripts/testflight_whats_new.py)).
This reuses the existing `APP_STORE_CONNECT_*` key (App Manager can write
TestFlight notes) — no new secrets. It's best-effort: if the build is still
processing past the timeout, it warns rather than failing the upload.

TestFlight builds expire 90 days after upload. Since releases are sporadic, a
monthly cron —
[`.github/workflows/testflight-refresh.yaml`](../.github/workflows/testflight-refresh.yaml)
— rebuilds the latest tag if the most recent TestFlight build is more than ~30
days old, so testers always have a valid build. It just dispatches
`testflight.yaml`, so it inherits the same signing and dormant-if-unset
behaviour; run it from the Actions tab with `force: true` to refresh immediately.

## Layout

- `LabTracker/Models.swift` — Codable mirrors of the API DTOs.
- `LabTracker/APIClient.swift` — async REST client (sends a Bearer token if set).
- `LabTracker/Store.swift` — `@Observable` app state (server URL, token,
  selected profile), persisted to `UserDefaults`.
- `LabTracker/Views/` — `OnboardingView` (first-run server setup), `RootView`
  (profiles + settings), `DashboardView` (latest per analyte, a collapsible
  **Health snapshot** — an on-demand whole-panel AI summary — plus a Body section
  of tracked body stats that opens the Body sheet), `AnalyteDetailView`
  (Swift Charts trend + AI analysis, with generate/regenerate + a staleness
  banner), `SettingsView`, `AboutView` (app/API
  versions + a Diagnostics section linking a `LogViewerView` and, when available, a
  `HealthKitDebugView` showing per-type readable sample counts), `MarkdownText`.
- `LabTracker/Logging.swift` — `AppLog`: the shared `os.Logger` subsystem
  (`dev.winktech.labtracker`) with `auth` / `healthsync` categories, plus a
  `recent()` reader over this process's `OSLogStore` powering the in-app viewer.
- `LabTracker/Views/LogViewerView.swift` — on-device log viewer (About →
  Diagnostics → Logs): shows the app's own sign-in / token-refresh / sync log lines
  with a category filter and share-to-export, so auth issues can be diagnosed
  without a Mac. Auth signs out only on a `400 invalid_grant`, logged with the
  server's reason and also written to a persistent **Auth history** trail
  (`UserDefaults`, via `AppLog.persistAuth`) so a sign-out that happened in a
  *background* launch is still visible next time the app opens (the live OSLog
  reader only sees the current process). Token refresh is race-safe across
  processes: on `invalid_grant`, if the Keychain already holds a rotated refresh
  token (another process refreshed first — e.g. a background sync), the app adopts
  it instead of signing out.
- `LabTracker/Views/ServerCheck.swift` — probes `{url}/health` to validate a
  server URL (shared by onboarding + settings).
- `LabTracker/Views/HealthSnapshot.swift` — the dashboard's collapsible **Health
  snapshot** card: an on-demand whole-panel AI summary (`POST …/summary`). The
  server doesn't store it, so the result is cached per profile in `UserDefaults`
  (mirroring the web app), with a staleness dot when the latest-result count has
  changed since it was generated.
- `LabTracker/Views/BodyView.swift` — per-profile birthdate + weight/height
  tracking (kg/lb, cm or ft·in) with BMI, plus read-only vitals (blood pressure,
  resting heart rate, body fat, waist, VO₂max, blood oxygen) shown once imported;
  opened from the dashboard toolbar, with an **Import from Apple Health** button.
  `BodyInputs.swift` holds the weight/height entry fields.
- `LabTracker/HealthImport.swift` — reads weight, height, and the vitals above
  from HealthKit (blood pressure via an `HKCorrelation`) for the import (needs the
  HealthKit entitlement in `LabTracker.entitlements` + the `NSHealth*` usage
  strings). Imports are idempotent (sample UUID → the server's `external_id`). The
  `syncDescriptors()` table (type → lab-tracker kind + unit conversion) is shared
  with the background sync.
- `LabTracker/HealthSync.swift` — automatic Apple Health sync (`HealthSync.shared`).
  Anchored queries (`HKAnchoredObjectQuery`, per-type anchors persisted in
  `UserDefaults`) upload only *new* samples to a chosen profile. Runs on app
  foreground (`scenePhase == .active`) and, where the entitlement allows, in the
  background via `HKObserverQuery` + `enableBackgroundDelivery` — the observer
  queries are registered from a tiny `UIApplicationDelegate` in `LabTrackerApp` so a
  background launch wires them up before any scene exists. Enabled from Settings →
  Apple Health, which also picks the target profile and shows last-synced /
  last-background-sync status. Logs via `os.Logger` (category `healthsync`) for
  Console.app. See **Apple Health background sync** below.
- `LabTracker/Views/AppLock.swift` — optional Face ID / Touch ID app lock
  (`LocalAuthentication`); `LockGate` covers content until auth succeeds, on
  launch and on return from the background. Toggle in Settings → Privacy.
- `LabTracker/Views/Theme.swift` — brand teal + the in-range/high/low status
  palette, and `LabResult.status`.
- `LabTracker/Views/RangeTrack.swift` — the reference-range gauge: a value's
  position within (or past) its normal band. Used on the dashboard rows and the
  analyte detail hero; echoed as the shaded band behind the trend chart.

## Tests & lint

```bash
swiftlint                              # SwiftLint (config in .swiftlint.yml)
xcodebuild test -project LabTracker.xcodeproj -scheme LabTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Unit tests (Swift Testing, in `LabTrackerTests/`) cover the pure logic:
`LabResult` flags/formatting, the PKCE helpers (incl. the RFC 7636 vector), the
`/config.js` parser, and the markdown renderer. Both run in CI
(`.github/workflows/ios.yaml`) on any `ios/**` change.

## Crash reporting (Sentry)

Crashes and traces go to the `lab-tracker-ios` project in Sentry, started from
`AppDelegate` in `LabTracker/LabTrackerApp.swift`. The SDK comes in as an SPM
package declared in [`project.yml`](project.yml), so `xcodegen generate`
resolves it — there is nothing to install by hand.

Debug builds are excluded (`#if !DEBUG`), so simulator runs and local device
builds never report; only Release builds — i.e. TestFlight — do. The DSN is
ingest-only and ships in the app binary, so it lives in source rather than a
secret.

Crash reports symbolicate only once the build's dSYMs reach Sentry, which the
TestFlight workflow does after each upload — but that step is skipped until the
repo has a `SENTRY_AUTH_TOKEN` secret (a Sentry auth token with
`project:releases`). Without it, builds still ship and crashes still report,
just with unsymbolicated stack traces.

## Not yet implemented

- **PDF upload** from the phone (share sheet / camera scan).
