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
}
