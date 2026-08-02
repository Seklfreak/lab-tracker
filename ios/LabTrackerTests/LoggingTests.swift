import Testing
import Foundation
@testable import LabTracker

/// The persistent auth trail is what surfaces a background-process sign-out in the
/// in-app log viewer, so guard its store/parse round-trip (it hand-splits on a tab).
struct LoggingTests {
    private let key = "authEventTrail"

    @Test func persistThenReadRoundTrips() {
        let backup = UserDefaults.standard.stringArray(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.set(backup, forKey: key) }

        let when = Date(timeIntervalSince1970: 1_000_000)
        AppLog.persistAuth("refresh REVOKED (status 400)", at: when)

        let trail = AppLog.authTrail()
        #expect(trail.count == 1)
        #expect(trail.first?.message == "refresh REVOKED (status 400)")
        #expect(trail.first?.category == "auth")
        #expect(trail.first?.date == when)
    }

    @Test func newestEntryComesFirst() {
        let backup = UserDefaults.standard.stringArray(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.set(backup, forKey: key) }

        AppLog.persistAuth("older", at: Date(timeIntervalSince1970: 100))
        AppLog.persistAuth("newer", at: Date(timeIntervalSince1970: 200))

        #expect(AppLog.authTrail().map(\.message) == ["newer", "older"])
    }
}
