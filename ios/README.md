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

In the app, tap the gear → set the **server URL**:

- **Local dev:** `http://localhost:8080` (the default). Run the backend with
  `AUTH_DISABLED=true`; the simulator reaches the host's localhost and no token
  is needed.
- **A real server:** its https URL. Until OIDC sign-in lands (below), paste a
  Bearer access token in Settings.

CLI build + run on a simulator:

```bash
xcodegen generate
xcodebuild -project LabTracker.xcodeproj -target LabTracker \
  -sdk iphonesimulator -configuration Debug -arch arm64 \
  CODE_SIGNING_ALLOWED=NO SYMROOT="$PWD/build" build
xcrun simctl boot "iPhone 17"
xcrun simctl install booted build/Debug-iphonesimulator/LabTracker.app
xcrun simctl launch booted dev.winkler.labtracker
```

## Layout

- `LabTracker/Models.swift` — Codable mirrors of the API DTOs.
- `LabTracker/APIClient.swift` — async REST client (sends a Bearer token if set).
- `LabTracker/Store.swift` — `@Observable` app state (server URL, token,
  selected profile), persisted to `UserDefaults`.
- `LabTracker/Views/` — `RootView` (profiles + settings), `DashboardView`
  (latest per analyte), `AnalyteDetailView` (Swift Charts trend + AI analysis),
  `SettingsView`, `MarkdownText`.

## Not yet implemented

- **OIDC sign-in** — Authorization Code + PKCE via `ASWebAuthenticationSession`
  against Authentik. The `labtracker://auth/callback` redirect URI (URL scheme
  already declared in `Info.plist`) must be registered on the `lab-tracker` OIDC
  client. Until then, use a pasted Bearer token (or a local AUTH_DISABLED server).
- **PDF upload** from the phone (share sheet / camera scan).
