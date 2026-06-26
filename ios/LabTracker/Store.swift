import Foundation
import Observation

/// App-wide state: server config, OIDC config, the selected profile, and the
/// auth session. Persisted to UserDefaults (tokens live in the Keychain).
@MainActor
@Observable
final class Store {
    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    /// Manually-pasted bearer token, used when not signed in via OIDC.
    var token: String? {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }
    var selectedProfileId: String? {
        didSet { UserDefaults.standard.set(selectedProfileId, forKey: "selectedProfileId") }
    }

    /// OIDC issuer + client id are discovered from the server (not hardcoded), so
    /// the only thing configured here is the server URL.
    let auth = AuthSession()

    init() {
        let d = UserDefaults.standard
        self.serverURL = d.string(forKey: "serverURL") ?? "http://localhost:8080"
        self.token = d.string(forKey: "token")
        self.selectedProfileId = d.string(forKey: "selectedProfileId")
    }

    var api: APIClient { APIClient(baseURL: serverURL, staticToken: token, auth: auth) }
}
