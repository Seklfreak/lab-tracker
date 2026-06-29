import Foundation
import CryptoKit
import AuthenticationServices
import UIKit
import Observation

struct OIDCConfig {
    var issuer: String        // e.g. https://auth.example.com/application/o/lab-tracker/
    var clientID: String
    var redirectURI = "dev.winkler.labtracker://auth/callback"
    var callbackScheme = "dev.winkler.labtracker"
    var scope = "openid profile email offline_access"

    var isConfigured: Bool { !issuer.trimmingCharacters(in: .whitespaces).isEmpty }
}

enum OIDCError: LocalizedError {
    case notConfigured, discovery, cancelled, noCode, stateMismatch, token(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "OIDC issuer / client ID not set."
        case .discovery: return "Couldn’t read the provider’s OpenID configuration."
        case .cancelled: return "Sign-in was cancelled."
        case .noCode: return "No authorization code was returned."
        case .stateMismatch: return "State mismatch — possible interference. Try again."
        case let .token(msg): return "Token request failed: \(msg)"
        }
    }
}

private struct DiscoveryDoc: Decodable {
    let authorizationEndpoint: String
    let tokenEndpoint: String
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
}

/// OIDC discovery/token responses are snake_case on the wire.
private let oidcDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()

/// Authorization Code + PKCE against an OIDC provider (Authentik). Holds the
/// tokens (Keychain-backed), runs the interactive sign-in via
/// ASWebAuthenticationSession, and refreshes the access token on demand.
@MainActor
@Observable
final class AuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// Discovered from the server (see signIn(serverURL:)) and cached so refreshes
    /// survive a restart.
    private(set) var config: OIDCConfig

    private(set) var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?
    private var webSession: ASWebAuthenticationSession?

    /// The in-flight refresh, if any. Concurrent callers (e.g. a screen that
    /// fans out several API requests at once) await this instead of each kicking
    /// off their own refresh — see refresh().
    private var refreshTask: Task<Void, Error>?

    var isSignedIn: Bool { refreshToken != nil || accessToken != nil }

    override init() {
        let d = UserDefaults.standard
        self.config = OIDCConfig(
            issuer: d.string(forKey: "oidc_issuer") ?? "",
            clientID: d.string(forKey: "oidc_client_id") ?? "lab-tracker"
        )
        super.init()
        accessToken = Keychain.get("access_token")
        refreshToken = Keychain.get("refresh_token")
        if let s = Keychain.get("expires_at"), let t = TimeInterval(s) {
            expiresAt = Date(timeIntervalSince1970: t)
        }
    }

    /// The only thing a user configures is the server URL: fetch the server's
    /// published OIDC config (`/config.js`), cache it, then run the flow.
    func signIn(serverURL: String) async throws {
        config = try await Self.fetchConfig(serverURL: serverURL)
        UserDefaults.standard.set(config.issuer, forKey: "oidc_issuer")
        UserDefaults.standard.set(config.clientID, forKey: "oidc_client_id")
        try await signIn()
    }

    private func signIn() async throws {
        guard config.isConfigured else { throw OIDCError.notConfigured }
        let disco = try await discover()

        let verifier = Self.randomURLSafe(64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafe(24)

        var comps = URLComponents(string: disco.authorizationEndpoint)
        comps?.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "scope", value: config.scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = comps?.url else { throw OIDCError.discovery }

        let callback = try await authenticate(url: authURL)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw OIDCError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw OIDCError.noCode }

        try await exchange(code: code, verifier: verifier, tokenEndpoint: disco.tokenEndpoint)
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        persist()
    }

    /// A non-expired access token, refreshing first if it's within 30s of expiry.
    func validAccessToken() async -> String? {
        if let exp = expiresAt, Date() < exp.addingTimeInterval(-30) { return accessToken }
        if refreshToken != nil { try? await refresh() }
        return accessToken
    }

    /// Refresh the access token, coalescing concurrent callers onto a single
    /// request. Authentik rotates the refresh token on every use, so two
    /// overlapping refreshes would each present the same token — the first
    /// rotates it, the second is rejected and signs the user out. Funnelling
    /// everyone through one in-flight task means the token is only ever spent
    /// once. (Reaching `refreshTask = task` involves no `await`, so on the main
    /// actor a second caller can't slip past the check before it's set.)
    func refresh() async throws {
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        guard refreshToken != nil, config.isConfigured else { return }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func performRefresh() async throws {
        guard let rt = refreshToken, config.isConfigured else { return }
        let disco = try await discover()
        let (data, resp) = try await post(disco.tokenEndpoint, form: [
            "grant_type": "refresh_token",
            "refresh_token": rt,
            "client_id": config.clientID,
        ])
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            signOut() // refresh token expired/revoked
            throw OIDCError.token("refresh rejected")
        }
        store(try oidcDecoder.decode(TokenResponse.self, from: data))
    }

    // MARK: - private

    private func exchange(code: String, verifier: String, tokenEndpoint: String) async throws {
        let (data, resp) = try await post(tokenEndpoint, form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientID,
            "code_verifier": verifier,
        ])
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw OIDCError.token(String(data: data, encoding: .utf8) ?? "status \( (resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        store(try oidcDecoder.decode(TokenResponse.self, from: data))
    }

    private func store(_ tr: TokenResponse) {
        accessToken = tr.accessToken
        if let rt = tr.refreshToken { refreshToken = rt } // rotation
        expiresAt = tr.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        persist()
    }

    private func persist() {
        Keychain.set(accessToken, for: "access_token")
        Keychain.set(refreshToken, for: "refresh_token")
        Keychain.set(expiresAt.map { String($0.timeIntervalSince1970) }, for: "expires_at")
    }

    /// Reads the OIDC authority + client id the server publishes for its web app
    /// at `{serverURL}/config.js` (a `window.__APP_CONFIG__ = { … }` snippet).
    static func fetchConfig(serverURL: String) async throws -> OIDCConfig {
        var base = serverURL.trimmingCharacters(in: .whitespaces)
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard let url = URL(string: base + "/config.js") else { throw OIDCError.notConfigured }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw OIDCError.discovery }
        let js = String(decoding: data, as: UTF8.self)
        guard let issuer = jsString("oidcAuthority", in: js), !issuer.isEmpty,
              let clientID = jsString("oidcClientId", in: js) else {
            throw OIDCError.token("the server didn’t publish an OIDC config (no auth configured?)")
        }
        return OIDCConfig(issuer: issuer, clientID: clientID)
    }

    nonisolated static func jsString(_ key: String, in js: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "\(key)\\s*:\\s*\"([^\"]*)\"") else { return nil }
        let range = NSRange(js.startIndex..., in: js)
        guard let m = re.firstMatch(in: js, range: range), let g = Range(m.range(at: 1), in: js) else { return nil }
        return String(js[g])
    }

    private func discover() async throws -> DiscoveryDoc {
        var base = config.issuer.trimmingCharacters(in: .whitespaces)
        if !base.hasSuffix("/") { base += "/" }
        guard let url = URL(string: base + ".well-known/openid-configuration") else { throw OIDCError.discovery }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let doc = try? oidcDecoder.decode(DiscoveryDoc.self, from: data) else { throw OIDCError.discovery }
        return doc
    }

    private func post(_ urlString: String, form: [String: String]) async throws -> (Data, URLResponse) {
        guard let url = URL(string: urlString) else { throw OIDCError.discovery }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form
            .map { "\($0.key)=\(Self.escape($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        return try await URLSession.shared.data(for: req)
    }

    /// Bridges the completion-handler web auth session to async/await.
    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: config.callbackScheme) { callbackURL, error in
                if let callbackURL {
                    cont.resume(returning: callbackURL)
                } else if let asError = error as? ASWebAuthenticationSessionError, asError.code == .canceledLogin {
                    cont.resume(throwing: OIDCError.cancelled)
                } else {
                    cont.resume(throwing: error ?? OIDCError.noCode)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }

    // MARK: PKCE helpers

    nonisolated static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64url(Data(bytes))
    }

    nonisolated static func codeChallenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Percent-encode a form value, escaping everything but RFC 3986 unreserved.
    nonisolated static func escape(_ s: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }
}
