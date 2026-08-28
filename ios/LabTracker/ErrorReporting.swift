import Foundation
import Sentry

extension Error {
    /// Errors that only mean the user backed out or the task was cancelled —
    /// worth showing (or not) in the UI, never worth a Sentry issue.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let oidc = self as? OIDCError, case .cancelled = oidc { return true }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    /// The device couldn't reach the network — backgrounded mid-request, no
    /// signal, DNS or the connection dropped. Worth showing the user (the load
    /// really did fail) but never worth a Sentry issue: there is no defect to
    /// find, and one issue per blip is how a project fills with noise. Most of
    /// these arrive with `in_foreground: false` — iOS tearing down a request
    /// after a HealthKit background relaunch.
    var isTransientNetwork: Bool {
        let nsError = self as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            NSURLErrorDataNotAllowed,
        ].contains(nsError.code)
    }

    /// Sends the error to Sentry (no-op in Debug, where the SDK isn't
    /// started) tagged with the call site, and returns the text to show the
    /// user. Sentry's automatic capture only covers crashes and 5xx responses;
    /// anything caught and rendered into the UI goes through here so it isn't
    /// invisible — and this is the only place client errors are captured, so
    /// one failed request cannot open two issues.
    ///
    /// Cancellations and transient network failures are dropped here but their
    /// text is still returned: what the user sees and what Sentry keeps are
    /// separate decisions.
    @discardableResult
    func report(file: String = #fileID, function: String = #function) -> String {
        if !isCancellation && !isTransientNetwork {
            let flow = "\(file.split(separator: "/").last.map(String.init) ?? file):\(function)"
            SentrySDK.capture(error: self) { scope in
                scope.setTag(value: flow, key: "flow")
            }
        }
        return localizedDescription
    }
}
