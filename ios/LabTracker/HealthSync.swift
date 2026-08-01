import Foundation
import HealthKit

/// Background/foreground sync of Apple Health body metrics into Lab Tracker.
///
/// Two layers, both driven by `HKAnchoredObjectQuery` so only *new* samples are
/// uploaded (the per-type anchor is persisted between runs):
///
///  1. **Auto-sync on open** — `syncNow()` runs when the app becomes active. Needs
///     no special entitlement; works in the Simulator.
///  2. **True background delivery** — `HKObserverQuery` + `enableBackgroundDelivery`
///     wake the app when Health gets new data, even when it's closed. This needs
///     the `com.apple.developer.healthkit.background-delivery` entitlement in the
///     App ID + provisioning profile; without it those calls simply no-op, so the
///     app still works with layer 1 only.
///
/// State (enabled flag, target profile, anchors) lives in `UserDefaults` so a
/// background launch — which has no `Store` or SwiftUI scene — can sync on its own.
/// It reuses `AuthSession.shared` for tokens, so refreshes stay coalesced with the
/// UI. Uploads are idempotent (sample UUID → the server's `external_id`), which
/// makes a not-yet-advanced anchor safe to retry.
@MainActor
@Observable
final class HealthSync {
    static let shared = HealthSync()

    private enum Key {
        static let enabled = "healthSyncEnabled"
        static let profile = "healthSyncProfileId"
        static func anchor(_ id: String) -> String { "healthSyncAnchor.\(id)" }
    }

    /// Whether new Health data is imported automatically. Persisted.
    private(set) var isEnabled: Bool
    /// The profile background-synced data is written to. Persisted.
    private(set) var targetProfileId: String?
    /// Set after the last sync attempt so Settings can surface failures.
    var lastError: String?

    private let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []
    private var observersStarted = false

    private init() {
        let d = UserDefaults.standard
        isEnabled = d.bool(forKey: Key.enabled)
        targetProfileId = d.string(forKey: Key.profile)
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Enable / disable (from Settings)

    /// Turn on syncing for a profile: request read access, register observers, ask
    /// for background delivery (a no-op without the entitlement), and pull now.
    func enable(profileId: String) async throws {
        try await HealthImporter().requestAuthorization()
        targetProfileId = profileId
        UserDefaults.standard.set(profileId, forKey: Key.profile)
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Key.enabled)
        startObservers()
        await enableBackgroundDelivery()
        await syncNow()
    }

    func disable() async {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Key.enabled)
        stopObservers()
        try? await store.disableAllBackgroundDelivery()
        // Anchors are kept so re-enabling doesn't re-import the whole history.
    }

    /// Change the destination profile without re-prompting for access.
    func setTargetProfile(_ profileId: String) {
        targetProfileId = profileId
        UserDefaults.standard.set(profileId, forKey: Key.profile)
    }

    // MARK: - Launch wiring (called from the app delegate, every launch)

    /// Register observer queries so a background launch can receive Health updates.
    /// Idempotent and cheap; only does anything when syncing is enabled.
    func startObservers() {
        guard isEnabled, Self.isAvailable, !observersStarted else { return }
        observersStarted = true
        for desc in HealthImporter.syncDescriptors() {
            let query = HKObserverQuery(sampleType: desc.sampleType, predicate: nil) { [weak self] _, completion, _ in
                // The completion handler MUST be called (even on failure) or iOS
                // throttles/stops delivery. Sync, then always signal done.
                Task { @MainActor in
                    await self?.syncNow()
                    completion()
                }
            }
            store.execute(query)
            observers.append(query)
        }
    }

    private func stopObservers() {
        for q in observers { store.stop(q) }
        observers.removeAll()
        observersStarted = false
    }

    func enableBackgroundDelivery() async {
        guard isEnabled, Self.isAvailable else { return }
        for desc in HealthImporter.syncDescriptors() {
            // `.hourly` is the finest cadence HealthKit allows for body metrics.
            try? await store.enableBackgroundDelivery(for: desc.sampleType, frequency: .hourly)
        }
    }

    // MARK: - The actual sync

    /// Pull new samples for every synced type and upload them. Safe to call often:
    /// it no-ops unless enabled, targeted at a profile, and reachable; anchors mean
    /// each run only sees samples added since the last one.
    func syncNow() async {
        guard isEnabled, let profileId = targetProfileId, let api = Self.makeAPI() else { return }
        var failed = false
        for desc in HealthImporter.syncDescriptors() {
            do {
                let (added, newAnchor) = try await fetchNew(desc.sampleType)
                for sample in added {
                    guard let s = desc.convert(sample) else { continue }
                    _ = try await api.addBody(profileId: profileId, kind: desc.kind, value: s.value,
                                              value2: s.value2, measuredOn: Self.day(s.date),
                                              source: "apple_health", externalId: s.uuid)
                }
                // Advance the anchor only after every upload for this type landed,
                // so a mid-batch failure just retries (idempotently) next time.
                if let newAnchor { saveAnchor(newAnchor, desc.sampleType.identifier) }
            } catch {
                failed = true
            }
        }
        lastError = failed ? "Some Health data couldn’t be synced; will retry." : nil
    }

    /// New samples for a type since its stored anchor, plus the anchor to persist.
    private func fetchNew(_ type: HKSampleType) async throws -> (added: [HKSample], anchor: HKQueryAnchor?) {
        let anchor = loadAnchor(type.identifier)
        return try await withCheckedThrowingContinuation { cont in
            let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor,
                                              limit: HKObjectQueryNoLimit) { _, samples, _, newAnchor, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples ?? [], newAnchor))
            }
            store.execute(query)
        }
    }

    // MARK: - Anchors

    private func loadAnchor(_ id: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: Key.anchor(id)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor, _ id: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: Key.anchor(id))
        }
    }

    // MARK: - Helpers

    /// Build an API client from persisted config, for the no-UI background path.
    /// Nil until a server is set; auth is the shared session (nil token on a local
    /// AUTH_DISABLED server is fine).
    private static func makeAPI() -> APIClient? {
        let url = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        guard !url.isEmpty else { return nil }
        return APIClient(baseURL: url, auth: AuthSession.shared)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
}
