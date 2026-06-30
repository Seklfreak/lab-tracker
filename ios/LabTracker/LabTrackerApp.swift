import SwiftUI

@main
struct LabTrackerApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            LockGate {
                RootView()
            }
            .environment(store)
        }
    }
}
