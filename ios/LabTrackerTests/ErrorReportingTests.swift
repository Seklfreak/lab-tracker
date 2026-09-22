import Testing
import Foundation
@testable import LabTracker

/// Which errors are worth a Sentry issue. The regression these guard against:
/// a phone that briefly loses the network — most often when iOS relaunches the
/// app in the background for a HealthKit sync — filed one issue per blip, for a
/// fault that does not exist in the app.
struct ErrorReportingTests {
    private func urlError(_ code: Int) -> Error {
        NSError(domain: NSURLErrorDomain, code: code)
    }

    @Test(arguments: [
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorNotConnectedToInternet,
        NSURLErrorInternationalRoamingOff,
        NSURLErrorCallIsActive,
        NSURLErrorDataNotAllowed,
    ])
    func reachabilityFailuresAreTransient(code: Int) {
        #expect(urlError(code).isTransientNetwork)
    }

    /// A URL error that means the *server* misbehaved is a real signal and has
    /// to keep reaching Sentry — the filter is about reachability, not about
    /// silencing NSURLErrorDomain wholesale.
    @Test(arguments: [NSURLErrorBadServerResponse, NSURLErrorSecureConnectionFailed])
    func serverSideURLErrorsStillReport(code: Int) {
        #expect(!urlError(code).isTransientNetwork)
    }

    @Test func appErrorsAreNotTransient() {
        #expect(!APIError.decoding("bad json").isTransientNetwork)
        #expect(!APIError.http(500, "boom").isTransientNetwork)
    }

    /// Cancellation stays its own concept: it is filtered from the *UI* too,
    /// while a transient network failure is still shown to the user — they
    /// asked for something and it did not load.
    @Test func transientNetworkIsNotCancellation() {
        #expect(!urlError(NSURLErrorNetworkConnectionLost).isCancellation)
        #expect(urlError(NSURLErrorCancelled).isCancellation)
    }

    /// LAB-TRACKER-IOS-1 and -7: one 502 from the gateway in front of the IdP,
    /// filed as two issues a millisecond apart off the same trace id. A
    /// gateway with nothing behind it is the same event as a refused
    /// connection, seen from one layer further away.
    @Test(arguments: [502, 503, 504])
    func aGatewayWithNothingBehindItIsNotAFault(status: Int) {
        #expect(OIDCError.discovery(status: status).isUnreachableGateway)
        #expect(APIError.http(status, "").isUnreachableGateway)
    }

    /// Something answered and was wrong. That is a fault, and it reports.
    @Test(arguments: [500, 501, 400, 401, 404])
    func ananswerThatIsWrongStillReports(status: Int) {
        #expect(!OIDCError.discovery(status: status).isUnreachableGateway)
        #expect(!APIError.http(status, "").isUnreachableGateway)
    }

    /// Discovery that never became a request — a URL we built that will not
    /// parse — is ours to fix, so it keeps reporting.
    @Test func discoveryThatNeverReachedTheNetworkStillReports() {
        #expect(!OIDCError.discovery(status: nil).isUnreachableGateway)
    }

    /// The gateway filter is about one shape of failure, not about silencing
    /// these error types wholesale.
    @Test func otherErrorsAreUntouchedByTheGatewayFilter() {
        #expect(!APIError.decoding("bad json").isUnreachableGateway)
        #expect(!APIError.badURL.isUnreachableGateway)
        #expect(!OIDCError.cancelled.isUnreachableGateway)
        #expect(!OIDCError.notConfigured.isUnreachableGateway)
        #expect(!urlError(NSURLErrorTimedOut).isUnreachableGateway)
    }
}
