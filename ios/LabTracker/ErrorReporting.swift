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

    /// Sends the error to Sentry (no-op in Debug, where the SDK isn't
    /// started) tagged with the call site, and returns the text to show the
    /// user. Sentry's automatic capture only covers crashes and failed HTTP
    /// requests; anything caught and rendered into the UI goes through here
    /// so it isn't invisible.
    @discardableResult
    func report(file: String = #fileID, function: String = #function) -> String {
        if !isCancellation {
            let flow = "\(file.split(separator: "/").last.map(String.init) ?? file):\(function)"
            SentrySDK.capture(error: self) { scope in
                scope.setTag(value: flow, key: "flow")
            }
        }
        return localizedDescription
    }
}
