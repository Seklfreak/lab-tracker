import SwiftUI

/// Result of probing a candidate server URL for a Lab Tracker backend.
enum ServerCheck: Equatable {
    case idle
    case checking
    case ok(version: String)
    case unreachable
    case notLabTracker

    var isOK: Bool {
        if case .ok = self { return true }
        return false
    }
}

enum ServerProbe {
    /// Normalize user input into a base URL: trim, default the scheme to https,
    /// drop a trailing slash. Returns nil for empty/unparseable input.
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return s
    }

    /// Probe `{url}/health`. A Lab Tracker server answers with `{status, version}`;
    /// a reachable server with any other shape is "not a Lab Tracker server", and
    /// a connection failure is "unreachable".
    static func validate(_ raw: String) async -> ServerCheck {
        guard let base = normalize(raw) else { return .idle }
        do {
            let health = try await APIClient(baseURL: base, auth: nil).health()
            return health.status.isEmpty ? .notLabTracker : .ok(version: health.version)
        } catch let error as APIError {
            switch error {
            case .decoding, .http: return .notLabTracker
            case .badURL: return .idle
            }
        } catch {
            return .unreachable
        }
    }
}

/// Inline validation feedback for a server URL field.
struct ServerStatusLabel: View {
    let check: ServerCheck

    var body: some View {
        switch check {
        case .idle:
            EmptyView()
        case .checking:
            Label { Text("Checking…") } icon: { ProgressView() }
                .font(.caption).foregroundStyle(.secondary)
        case let .ok(version):
            Label("Lab Tracker · v\(version)", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(Color.statusInRange)
        case .unreachable:
            Label("Couldn’t reach that server", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(Color.statusHigh)
        case .notLabTracker:
            Label("Not a Lab Tracker server", systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(Color.statusHigh)
        }
    }
}
