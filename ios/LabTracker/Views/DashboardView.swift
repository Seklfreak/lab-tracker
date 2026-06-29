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
                    Section {
                        SummaryHeader(results: results)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
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

/// One analyte: name + value on top, the reference-range track below, then the
/// reference interval as a quiet caption. Value is tabular and tinted by status.
struct ResultRow: View {
    let result: LabResult

    var body: some View {
        let status = result.status
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(result.analyteName)
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
                if let symbol = status.directionSymbol {
                    Image(systemName: symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(status.tint)
                }
                Text(result.displayValue)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(status == .unknown ? Color.primary : status.tint)
                if let unit = result.unit {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let v = result.valueNumeric, result.referenceLow != nil || result.referenceHigh != nil {
                RangeTrack(value: v, low: result.referenceLow, high: result.referenceHigh, status: status)
            }
            if let ref = result.referenceLabel {
                Text("Reference \(ref)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Opens the dashboard with a verdict, not just a list: total markers, how many
/// are out of range, and when the panel was last updated.
struct SummaryHeader: View {
    let results: [LabResult]

    private var outOfRange: Int { results.filter(\.isAbnormal).count }
    private var latest: String? { results.compactMap(\.observedDate).max() }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(results.count) markers")
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            chip
        }
    }

    private var subtitle: String {
        var parts = [outOfRange == 0 ? "All in range" : "\(outOfRange) out of range"]
        if let pretty = LabDate.pretty(latest) { parts.append("updated \(pretty)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var chip: some View {
        if outOfRange == 0 {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(Color.statusInRange)
        } else {
            Text("\(outOfRange)")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.statusHigh))
        }
    }

}
