import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid server URL."
        case let .http(code, msg): return "Server error \(code): \(msg)"
        case let .decoding(msg): return "Could not read response: \(msg)"
        }
    }

    /// A 401 — the token is missing, expired, or otherwise rejected. The UI
    /// offers a re-sign-in to recover when it sees this.
    var isUnauthorized: Bool {
        if case .http(401, _) = self { return true }
        return false
    }
}

/// Thin REST client for the lab-tracker API. Uses the OIDC access token when
/// signed in (refreshing + retrying once on a 401), else a manually-pasted
/// token, else none (a local AUTH_DISABLED backend).
struct APIClient {
    var baseURL: String
    var staticToken: String?
    var auth: AuthSession?

    private func bearer() async -> String? {
        if let t = await auth?.validAccessToken(), !t.isEmpty { return t }
        return staticToken
    }

    private func request<T: Decodable>(_ path: String, as _: T.Type) async throws -> T {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmed + path) else { throw APIError.badURL }

        func send(_ token: String?) async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: url)
            if let token, !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.http(0, "no response") }
            return (data, http)
        }

        var (data, http) = try await send(await bearer())

        // Token may have just expired — refresh once and retry.
        if http.statusCode == 401, let auth {
            try? await auth.refresh()
            if let fresh = await auth.validAccessToken(), !fresh.isEmpty {
                (data, http) = try await send(fresh)
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    func profiles() async throws -> [Profile] {
        try await request("/api/profiles", as: [Profile].self)
    }

    /// Latest value per analyte (the dashboard view).
    func latestResults(profileId: String) async throws -> [LabResult] {
        try await request("/api/profiles/\(profileId)/results", as: [LabResult].self)
    }

    /// All readings for one analyte over time, oldest first.
    func trend(profileId: String, analyteId: String) async throws -> [LabResult] {
        try await request("/api/profiles/\(profileId)/results?analyte_id=\(analyteId)", as: [LabResult].self)
    }

    func analysis(profileId: String, analyteId: String) async throws -> Analysis? {
        try await request("/api/profiles/\(profileId)/analytes/\(analyteId)/analysis", as: AnalysisEnvelope.self).analysis
    }
}
