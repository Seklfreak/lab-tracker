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
    var oidcIssuer: String {
        didSet { UserDefaults.standard.set(oidcIssuer, forKey: "oidcIssuer"); syncAuthConfig() }
    }
    var oidcClientID: String {
        didSet { UserDefaults.standard.set(oidcClientID, forKey: "oidcClientID"); syncAuthConfig() }
    }

    let auth: AuthSession

    init() {
        let d = UserDefaults.standard
        self.serverURL = d.string(forKey: "serverURL") ?? "http://localhost:8080"
        self.token = d.string(forKey: "token")
        self.selectedProfileId = d.string(forKey: "selectedProfileId")
        let issuer = d.string(forKey: "oidcIssuer") ?? "https://auth.wink8s.dev/application/o/lab-tracker/"
        let clientID = d.string(forKey: "oidcClientID") ?? "lab-tracker"
        self.oidcIssuer = issuer
        self.oidcClientID = clientID
        self.auth = AuthSession(config: OIDCConfig(issuer: issuer, clientID: clientID))
    }

    private func syncAuthConfig() {
        auth.config = OIDCConfig(issuer: oidcIssuer, clientID: oidcClientID)
    }

    var api: APIClient { APIClient(baseURL: serverURL, staticToken: token, auth: auth) }
}
