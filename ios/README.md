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

The only thing you configure is the **server URL** (gear → Settings):

- **Local dev:** `http://localhost:8080` (the default). Run the backend with
  `AUTH_DISABLED=true`; the simulator reaches the host's localhost and no auth is
  needed.
- **A real server:** its https URL, then tap **Sign in**. The app reads the
  server's published OIDC config from `{serverURL}/config.js` (the same one the
  web app uses — nothing hardcoded), runs Authorization Code + PKCE via
  `ASWebAuthenticationSession`, and stores the tokens in the Keychain (auto-
  refresh). A pasted Bearer token works as an alternative.

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

- **PDF upload** from the phone (share sheet / camera scan).
