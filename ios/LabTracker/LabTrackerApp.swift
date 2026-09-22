import Sentry
import SwiftUI

@main
struct LabTrackerApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    // Registers HealthKit observer queries on every launch — including a launch
    // that HealthKit triggers in the background — so pending updates get delivered.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            LockGate {
                RootView()
            }
            .environment(store)
            .environment(HealthSync.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            // Auto-sync on open / return to foreground (no-ops unless enabled).
            if phase == .active { Task { await HealthSync.shared.syncNow() } }
        }
    }
}

/// Minimal app delegate: HealthKit background delivery re-launches the app and
/// expects its observer queries to be registered from `didFinishLaunching`, before
/// any SwiftUI scene exists. Everything else stays in SwiftUI.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Crash reporting + tracing (winktech/lab-tracker-ios). The DSN is
        // ingest-only — it ships in the app binary regardless. Debug builds
        // stay off so simulator noise never reaches the project.
        #if !DEBUG
        SentrySDK.start { options in
            options.dsn = "https://bd2cd6d13ad4af70856bd356ed8e4673@o4511866040811520.ingest.us.sentry.io/4511937415544832"
            // Household-scale traffic: trace everything rather than sample.
            options.tracesSampleRate = 1.0
            // Off, not narrowed. Capturing failed requests here was cut back
            // from 4xx to the 5xx default once already, because a handled 401
            // was arriving twice — once from the swizzle and once through
            // `Error.report()` at the catch site. The 5xx default kept doing
            // it: LAB-TRACKER-IOS-1 and -7 are one 502 from the IdP's
            // discovery endpoint, filed as two issues a millisecond apart off
            // the same trace and span id.
            //
            // Narrowing was treating the symptom. `report()` is meant to be
            // the only place client errors are captured, and it is the better
            // report either way — it knows the call site, tags the flow, and
            // can tell a blip from a fault, where the swizzle's stack is
            // nothing but the SDK's own frames.
            options.enableCaptureFailedRequests = false
        }
        #endif
        MainActor.assumeIsolated {
            HealthSync.shared.startObservers()
            Task { await HealthSync.shared.enableBackgroundDelivery() }
        }
        return true
    }
}
