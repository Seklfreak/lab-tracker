import SwiftUI

/// On-device viewer for the app's own logs (subsystem `dev.winktech.labtracker`),
/// so auth / sync issues can be diagnosed without a Mac + Console.app. Shows the
/// current process's entries (sign-in, token refresh, Health sync); pull to
/// refresh, and share to export the text.
struct LogViewerView: View {
    @State private var entries: [AppLog.Entry] = []
    @State private var category = "all"

    private var categories: [String] {
        ["all"] + Set(entries.map(\.category)).sorted()
    }

    private var filtered: [AppLog.Entry] {
        category == "all" ? entries : entries.filter { $0.category == category }
    }

    var body: some View {
        List {
            if categories.count > 2 {
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
            }

            if filtered.isEmpty {
                Text("No logs yet. Sign-in, token refresh, and Health sync events will appear here.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(filtered) { entry in
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
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: exportText) { Image(systemName: "square.and.arrow.up") }
                    .disabled(entries.isEmpty)
            }
        }
        .task { entries = AppLog.recent() }
        .refreshable { entries = AppLog.recent() }
    }

    private var exportText: String {
        filtered.map { "\(Self.time($0.date)) [\($0.category)] \($0.level): \($0.message)" }
            .joined(separator: "\n")
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
