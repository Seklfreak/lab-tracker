import SwiftUI

/// The dashboard's **Health snapshot** — an on-demand, whole-panel AI summary of
/// the profile's latest results. The server doesn't store it, so the last result
/// is cached per profile in `UserDefaults` (mirroring the web app's localStorage),
/// with a staleness hint when the number of latest results has changed since it
/// was generated. Rendered as a collapsible `List` section, collapsed by default
/// since it's a big block.
struct HealthSnapshotSection: View {
    @Environment(Store.self) private var store
    let profile: Profile
    let currentCount: Int

    @State private var summary: PanelSummary?
    @State private var blocks: [MarkdownText.Block] = []
    @State private var open = false
    @State private var generating = false
    @State private var error: String?

    private var stale: Bool {
        guard let summary else { return false }
        return summary.basedOnCount != currentCount
    }

    var body: some View {
        Section {
            Button {
                withAnimation { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.brandTeal)
                    Text("Health snapshot")
                        .font(.subheadline.weight(.semibold))
                    if !open && stale {
                        Circle().fill(Color.statusWarn).frame(width: 7, height: 7)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open { content }
        }
        // Reload this profile's cached snapshot when the shown profile changes.
        .task(id: profile.id) { load() }
    }

    @ViewBuilder private var content: some View {
        if generating {
            HStack(spacing: 10) {
                ProgressView()
                Text("Summarizing your latest panel…")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if let summary {
            VStack(alignment: .leading, spacing: 10) {
                if stale {
                    Label("Your results have changed since this snapshot. Regenerate to refresh.",
                          systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(Color.statusWarn)
                }
                MarkdownText(blocks: blocks)
                HStack {
                    Text("Generated \(LabDate.prettyTimestamp(summary.generatedAt))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await generate() } } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("An AI overview of your latest panel — what's out of range, what looks good, and what to keep an eye on.")
                    .font(.callout).foregroundStyle(.secondary)
                Button { Task { await generate() } } label: {
                    Label("Generate health snapshot", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandTeal)
            }
            .padding(.vertical, 2)
        }

        if let error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private func load() {
        summary = Self.cached(profile.id)
        blocks = summary.map { MarkdownText.parse($0.content) } ?? []
        error = nil
    }

    private func generate() async {
        generating = true
        error = nil
        defer { generating = false }
        do {
            let s = try await store.api.generatePanelSummary(profileId: profile.id)
            summary = s
            blocks = MarkdownText.parse(s.content)
            Self.cache(s, for: profile.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Per-profile cache (mirrors the web app's `panel-summary:{id}` key)

    private static func key(_ profileId: String) -> String { "panel-summary:\(profileId)" }

    private static func cached(_ profileId: String) -> PanelSummary? {
        guard let data = UserDefaults.standard.data(forKey: key(profileId)) else { return nil }
        return try? JSONDecoder().decode(PanelSummary.self, from: data)
    }

    private static func cache(_ s: PanelSummary, for profileId: String) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key(profileId))
        }
    }
}
