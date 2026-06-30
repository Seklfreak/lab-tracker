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
/// signed in (refreshing + retrying once on a 401), else none (a local
/// AUTH_DISABLED backend).
struct APIClient {
    var baseURL: String
    var auth: AuthSession?

    private func bearer() async -> String? {
        guard let t = await auth?.validAccessToken(), !t.isEmpty else { return nil }
        return t
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

    /// Public health endpoint (no auth) — used by the About screen for the API version.
    func health() async throws -> Health {
        try await request("/health", as: Health.self)
    }

    func updateProfile(profileId: String, name: String, dateOfBirth: String?) async throws -> Profile {
        try await send("/api/profiles/\(profileId)", method: "PATCH",
                       body: ProfileUpdate(name: name, dateOfBirth: dateOfBirth), as: Profile.self)
    }

    func bodyMeasurements(profileId: String) async throws -> [BodyMeasurement] {
        try await request("/api/profiles/\(profileId)/body", as: [BodyMeasurement].self)
    }

    func addBody(profileId: String, kind: String, value: Double, measuredOn: String?,
                 source: String = "manual", externalId: String? = nil) async throws -> BodyMeasurement {
        try await send("/api/profiles/\(profileId)/body", method: "POST",
                       body: BodyAdd(kind: kind, value: value, measuredOn: measuredOn, source: source, externalId: externalId),
                       as: BodyMeasurement.self)
    }

    func deleteBody(profileId: String, measurementId: String) async throws {
        try await mutate("/api/profiles/\(profileId)/body/\(measurementId)", method: "DELETE", body: nil)
    }

    /// Request with a JSON body that decodes a response. Mirrors request()/mutate()
    /// auth + 401-refresh handling.
    private func send<B: Encodable, T: Decodable>(_ path: String, method: String, body: B, as _: T.Type) async throws -> T {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmed + path) else { throw APIError.badURL }
        let payload = try JSONEncoder().encode(body)

        func run(_ token: String?) async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = payload
            if let token, !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.http(0, "no response") }
            return (data, http)
        }

        var (data, http) = try await run(await bearer())
        if http.statusCode == 401, let auth {
            try? await auth.refresh()
            if let fresh = await auth.validAccessToken(), !fresh.isEmpty {
                (data, http) = try await run(fresh)
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
}

private struct ProfileUpdate: Encodable {
    let name: String
    let dateOfBirth: String?
}

private struct BodyAdd: Encodable {
    let kind: String
    let value: Double
    let measuredOn: String?
    let source: String
    let externalId: String?
}

extension APIClient {

    func addFavorite(profileId: String, analyteId: String) async throws {
        try await mutate("/api/profiles/\(profileId)/favorites", method: "POST", body: ["analyteId": analyteId])
    }

    func removeFavorite(profileId: String, analyteId: String) async throws {
        try await mutate("/api/profiles/\(profileId)/favorites/\(analyteId)", method: "DELETE", body: nil)
    }

    /// POST/DELETE with no decoded response. Mirrors request()'s auth + 401-refresh.
    private func mutate(_ path: String, method: String, body: [String: String]?) async throws {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmed + path) else { throw APIError.badURL }

        func send(_ token: String?) async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: url)
            req.httpMethod = method
            if let body {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONEncoder().encode(body)
            }
            if let token, !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.http(0, "no response") }
            return (data, http)
        }

        var (data, http) = try await send(await bearer())
        if http.statusCode == 401, let auth {
            try? await auth.refresh()
            if let fresh = await auth.validAccessToken(), !fresh.isEmpty {
                (data, http) = try await send(fresh)
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
