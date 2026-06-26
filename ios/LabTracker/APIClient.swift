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
}

/// Thin REST client for the lab-tracker API. Sends a Bearer token when one is
/// present (OIDC); against a local AUTH_DISABLED backend none is needed.
struct APIClient {
    var baseURL: String
    var token: String?

    private func request<T: Decodable>(_ path: String, as _: T.Type) async throws -> T {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmed + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.http(0, "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, body)
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
