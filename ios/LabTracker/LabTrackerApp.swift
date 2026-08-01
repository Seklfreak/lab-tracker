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
        MainActor.assumeIsolated {
            HealthSync.shared.startObservers()
            Task { await HealthSync.shared.enableBackgroundDelivery() }
        }
        return true
    }
}
