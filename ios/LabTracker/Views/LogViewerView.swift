import SwiftUI

/// On-device viewer for the app's own logs (subsystem `dev.winktech.labtracker`),
/// so auth / sync issues can be diagnosed without a Mac + Console.app. Shows the
/// current process's entries (sign-in, token refresh, Health sync); pull to
/// refresh, and share to export the text.
struct LogViewerView: View {
    @State private var entries: [AppLog.Entry] = []
    @State private var trail: [AppLog.Entry] = []
    @State private var category = "all"
    @State private var isLoading = true

    private var categories: [String] {
        ["all"] + Set(entries.map(\.category)).sorted()
    }

    private var filtered: [AppLog.Entry] {
        category == "all" ? entries : entries.filter { $0.category == category }
    }

    var body: some View {
        List {
            // Persisted auth events — survive restarts, so a sign-out that happened
            // in a background process shows up here even though the live log below
            // only covers the current session.
            if !trail.isEmpty {
                Section("Auth history (saved)") {
                    ForEach(trail) { row($0) }
                }
            }

            Section {
                if categories.count > 2 {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading logs…").font(.callout).foregroundStyle(.secondary)
                    }
                } else if filtered.isEmpty {
                    Text("No logs this session. Sign-in, token refresh, and Health sync events appear here.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { row($0) }
                }
            } header: {
                Text("This session")
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: exportText) { Image(systemName: "square.and.arrow.up") }
                    .disabled(entries.isEmpty && trail.isEmpty)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    @ViewBuilder private func row(_ entry: AppLog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(Self.time(entry.date)).monospaced().foregroundStyle(.secondary)
                Text(entry.category).fontWeight(.semibold).foregroundStyle(Color.brandTeal)
                Text(entry.level).foregroundStyle(color(entry.level))
            }
            .font(.caption2)
            Text(entry.message).font(.caption.monospaced())
        }
        .padding(.vertical, 1)
    }

    // OSLogStore.getEntries can take seconds — read it off the main actor so
    // opening the Logs screen doesn't freeze the app.
    private func reload() async {
        let (recent, authTrail) = await Task.detached(priority: .userInitiated) {
            (AppLog.recent(), AppLog.authTrail())
        }.value
        entries = recent
        trail = authTrail
        isLoading = false
    }

    private var exportText: String {
        let all = trail.map { "\(Self.time($0.date)) [saved:\($0.category)] \($0.message)" }
            + filtered.map { "\(Self.time($0.date)) [\($0.category)] \($0.level): \($0.message)" }
        return all.joined(separator: "\n")
    }

    private func color(_ level: String) -> Color {
        switch level {
        case "error", "fault": return .statusHigh
        case "notice": return .statusInRange
        default: return .secondary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
}
