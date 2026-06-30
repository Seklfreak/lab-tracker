import SwiftUI
import LocalAuthentication

/// Biometric / passcode unlock via LocalAuthentication. Uses
/// `.deviceOwnerAuthentication` so there's always a passcode fallback — enabling
/// the lock can never strand the user if Face ID fails.
enum Biometrics {
    /// Human name for the enrolled biometry ("Face ID" / "Touch ID"), for labels.
    static var name: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "device unlock"
        }
    }

    /// Whether the device can authenticate at all (biometrics or a passcode set).
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return await withCheckedContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }
}

/// Wraps the app: when the lock is enabled, covers content with a lock screen
/// until biometric/passcode auth succeeds — on launch and whenever the app
/// returns from the background. The cover also stands in for the app-switcher
/// snapshot (scenePhase != .active) so results aren't visible there.
struct LockGate<Content: View>: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked = false
    @State private var authenticating = false
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    private var enabled: Bool { store.biometricLockEnabled }
    private var covered: Bool { enabled && (!unlocked || scenePhase != .active) }

    var body: some View {
        content
            .overlay {
                if covered {
                    LockScreen(authenticating: authenticating) { Task { await authenticate() } }
                }
            }
            .task {
                if enabled && !unlocked { await authenticate() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard enabled else { return }
                if phase == .background { unlocked = false }
                if phase == .active && !unlocked && !authenticating { Task { await authenticate() } }
            }
    }

    private func authenticate() async {
        guard !authenticating else { return }
        authenticating = true
        let ok = await Biometrics.authenticate(reason: "Unlock Lab Tracker")
        unlocked = ok
        authenticating = false
    }
}

private struct LockScreen: View {
    let authenticating: Bool
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.brandTeal)
                Text("Lab Tracker").font(.title2.weight(.bold))
                Button(action: unlock) {
                    if authenticating {
                        ProgressView()
                    } else {
                        Text("Unlock")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.brandTeal)
                .disabled(authenticating)
            }
        }
    }
}
