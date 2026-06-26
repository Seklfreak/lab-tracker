import Foundation
import Observation

/// App-wide state: server config + the selected profile. Persisted to
/// UserDefaults so the app reopens where you left off.
@Observable
final class Store {
    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    var token: String? {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }
    var selectedProfileId: String? {
        didSet { UserDefaults.standard.set(selectedProfileId, forKey: "selectedProfileId") }
    }

    init() {
        let d = UserDefaults.standard
        self.serverURL = d.string(forKey: "serverURL") ?? "http://localhost:8080"
        self.token = d.string(forKey: "token")
        self.selectedProfileId = d.string(forKey: "selectedProfileId")
    }

    var api: APIClient { APIClient(baseURL: serverURL, token: token) }

    var isConfigured: Bool { !serverURL.trimmingCharacters(in: .whitespaces).isEmpty }
}
