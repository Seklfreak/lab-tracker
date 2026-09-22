import Foundation

/// What can go wrong in the OIDC flow. Split out of `OIDC.swift` so that file
/// stays under the 400-line limit.
enum OIDCError: LocalizedError {
    case notConfigured, cancelled, noCode, stateMismatch, token(String)
    /// The provider's configuration couldn't be read. Carries the HTTP status
    /// when the request got one, because a 502 from the gateway in front of
    /// the IdP is an outage nothing here can fix, while a 404 or unreadable
    /// body is a configuration fault worth reporting. Nil when it never
    /// became a request — a URL we built that won't parse.
    case discovery(status: Int?)
    /// The token endpoint couldn't be reached or answered with something other
    /// than a definitive rejection. The session is still good — distinct from
    /// `.token`, which is a refusal that has already signed the user out.
    case refreshUnavailable(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "OIDC issuer / client ID not set."
        case .discovery: return "Couldn’t read the provider’s OpenID configuration."
        case .cancelled: return "Sign-in was cancelled."
        case .noCode: return "No authorization code was returned."
        case .stateMismatch: return "State mismatch — possible interference. Try again."
        case let .token(msg): return "Token request failed: \(msg)"
        case .refreshUnavailable:
            return "Couldn’t reach the sign-in server. Check your connection and try again."
        }
    }
}
