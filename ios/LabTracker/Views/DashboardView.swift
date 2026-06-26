import SwiftUI

/// Latest value per analyte for a profile, grouped by category, with a tap-through
/// to the trend + AI analysis.
struct DashboardView: View {
    @Environment(Store.self) private var store
    let profile: Profile

    @State private var results: [LabResult] = []
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""

    private var filtered: [LabResult] {
        guard !search.isEmpty else { return results }
        return results.filter { $0.analyteName.localizedCaseInsensitiveContains(search) }
    }

    /// (category, results) sorted; favorites first within "Favorites".
    private var groups: [(String, [LabResult])] {
        var byCat: [String: [LabResult]] = [:]
        for r in filtered {
            byCat[r.category ?? "Other", default: []].append(r)
        }
        return byCat
            .map { ($0.key, $0.value.sorted { $0.analyteName < $1.analyteName }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        Group {
            if loading && results.isEmpty {
                ProgressView()
            } else if let error {
                ContentUnavailableView("Couldn’t load results", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if results.isEmpty {
                ContentUnavailableView("No results yet", systemImage: "doc.text.magnifyingglass")
            } else {
                List {
                    ForEach(groups, id: \.0) { category, rows in
                        Section(category) {
                            ForEach(rows) { r in
                                NavigationLink(value: r) {
                                    ResultRow(result: r)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $search, prompt: "Search analytes")
            }
        }
        .navigationDestination(for: LabResult.self) { r in
            AnalyteDetailView(profile: profile, analyteId: r.analyteId, analyteName: r.analyteName)
        }
        .task(id: profile.id) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            results = try await store.api.latestResults(profileId: profile.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ResultRow: View {
    let result: LabResult

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.analyteName).font(.body)
                if let ref = result.referenceLabel {
                    Text("Ref: \(ref)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(result.displayValue)
                    .font(.headline)
                    .foregroundStyle(result.isAbnormal ? .red : .primary)
                if let unit = result.unit {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
