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
    // Seed from the persisted flag so a locked launch never flashes content.
    @State private var locked = UserDefaults.standard.bool(forKey: "biometricLock")
    @State private var authenticating = false
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    private var enabled: Bool { store.biometricLockEnabled }

    var body: some View {
        content
            .overlay {
                if enabled && locked {
                    // Lock screen visibility is driven only by `locked`, which
                    // clears the instant auth succeeds — not by scenePhase, which
                    // lags behind the Face ID prompt and left the screen (and its
                    // tappable button) up for a beat after a successful unlock.
                    LockScreen(authenticating: authenticating) { Task { await authenticate() } }
                } else if enabled && scenePhase == .inactive && !authenticating {
                    PrivacyCover()
                }
            }
            .task {
                if enabled && locked { await authenticate() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard enabled else { return }
                if phase == .background { locked = true }
                if phase == .active && locked && !authenticating { Task { await authenticate() } }
            }
    }

    private func authenticate() async {
        guard !authenticating else { return }
        authenticating = true
        if await Biometrics.authenticate(reason: "Unlock Lab Tracker") { locked = false }
        authenticating = false
    }
}

/// Opaque cover for the app-switcher snapshot (scenePhase .inactive) so results
/// aren't visible there. Separate from the lock screen so it never blocks the
/// unlock transition.
private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.brandTeal)
        }
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
