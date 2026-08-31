import Foundation

/// The `{ "error": "…" }` shape of an OAuth2 token-endpoint error (RFC 6749 §5.2).
private struct OAuthError: Decodable {
    let error: String
}

/// The decisions the OIDC session makes, separated from the machinery that
/// makes them: no I/O, no state, no provider — so each one can be unit-tested
/// on its own, which is the point. Every rule here was written because getting
/// it wrong signed somebody out.
extension AuthSession {
    /// A short, token-free snippet of a token-endpoint error body for logging
    /// (error responses are `{"error":"…"}` — no secrets). Internal rather
    /// than private: the refresh paths that log it live in OIDC.swift.
    static func bodySnippet(_ data: Data) -> String {
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count > 200 ? String(s.prefix(200)) + "…" : s
    }

    /// What the token endpoint's refresh response means for our stored tokens:
    /// store the new ones, sign out, or keep the current token and retry later.
    /// Only a definitively revoked/expired refresh token signs the user out —
    /// per RFC 6749 §5.2 that's HTTP 400 `invalid_grant`. Everything else (5xx
    /// from an Authentik restart/redeploy, gateway 502/503, other 4xx) preserves
    /// the refresh token so a transient blip doesn't force a re-login.
    enum RefreshOutcome: Equatable {
        case refreshed
        case revoked
        case keepRetry(Int)
    }

    /// Whether a screen should ask for sign-in rather than call the API: the
    /// server uses OIDC and we have no session. Kept explicit because the
    /// obvious shortening — prompt whenever not signed in — silently breaks
    /// the other deployment: a server publishing no OIDC config serves its
    /// API openly, and those installs must go on loading without a prompt.
    ///
    /// Pure (no I/O) so it can be unit-tested.
    nonisolated static func needsSignIn(configured: Bool, signedIn: Bool) -> Bool {
        configured && !signedIn
    }

    /// Pure (no I/O) so it can be unit-tested without a live IdP.
    nonisolated static func classifyRefresh(status: Int, body: Data) -> RefreshOutcome {
        if status == 200 { return .refreshed }
        if status == 400,
           let err = try? oidcDecoder.decode(OAuthError.self, from: body),
           err.error == "invalid_grant" {
            return .revoked
        }
        return .keepRetry(status)
    }
}
