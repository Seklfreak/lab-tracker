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
    var selectedProfileId: String? {
        didSet { UserDefaults.standard.set(selectedProfileId, forKey: "selectedProfileId") }
    }

    /// OIDC issuer + client id are discovered from the server (not hardcoded), so
    /// the only thing configured here is the server URL.
    let auth = AuthSession()

    init() {
        let d = UserDefaults.standard
        // No default: an unset server URL drives the first-run onboarding flow.
        self.serverURL = d.string(forKey: "serverURL") ?? ""
        self.selectedProfileId = d.string(forKey: "selectedProfileId")
    }

    var api: APIClient { APIClient(baseURL: serverURL, auth: auth) }
}
