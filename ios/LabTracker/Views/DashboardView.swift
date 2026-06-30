import SwiftUI

/// How the dashboard orders analytes. Mirrors the web app's options. Category
/// keeps the grouped-by-panel layout; the others flatten into a single list.
enum SortKey: String, CaseIterable, Identifiable {
    case category, name, count, recent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .category: return "Category"
        case .name: return "Name"
        case .count: return "Most readings"
        case .recent: return "Most recent"
        }
    }
}

/// Latest value per analyte for a profile, with favorites pinned on top, a sort
/// menu, an out-of-range filter, and a tap-through to the trend + AI analysis.
struct DashboardView: View {
    @Environment(Store.self) private var store
    let profile: Profile

    @State private var results: [LabResult] = []
    @State private var bodyMeasurements: [BodyMeasurement] = []
    @State private var showBody = false
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    @State private var onlyOutOfRange = false
    @AppStorage("dashboardSort") private var sort: SortKey = .category
    @AppStorage("weightUnit") private var weightUnit = "lb"

    private var filtered: [LabResult] {
        var rows = results
        if onlyOutOfRange { rows = rows.filter(\.isAbnormal) }
        if !search.isEmpty { rows = rows.filter { $0.analyteName.localizedCaseInsensitiveContains(search) } }
        return rows
    }

    private var favorites: [LabResult] { sorted(filtered.filter { $0.isFavorite == true }) }
    private var rest: [LabResult] { filtered.filter { $0.isFavorite != true } }

    /// Category-grouped `rest`, used only for the Category sort.
    private var restGroups: [(String, [LabResult])] {
        var byCat: [String: [LabResult]] = [:]
        for r in rest { byCat[r.category ?? "Other", default: []].append(r) }
        return byCat.map { ($0.key, sorted($0.value)) }.sorted { $0.0 < $1.0 }
    }

    private func sorted(_ rows: [LabResult]) -> [LabResult] {
        let byName: (LabResult, LabResult) -> Bool = {
            $0.analyteName.localizedCaseInsensitiveCompare($1.analyteName) == .orderedAscending
        }
        switch sort {
        case .name, .category:
            return rows.sorted(by: byName)
        case .count:
            return rows.sorted {
                let c0 = $0.count ?? 1, c1 = $1.count ?? 1
                return c0 == c1 ? byName($0, $1) : c0 > c1
            }
        case .recent:
            return rows.sorted {
                let d0 = $0.observedDate ?? "", d1 = $1.observedDate ?? ""
                return d0 == d1 ? byName($0, $1) : d0 > d1
            }
        }
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
                list
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(SortKey.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .navigationDestination(for: LabResult.self) { r in
            AnalyteDetailView(profile: profile, analyteId: r.analyteId, analyteName: r.analyteName)
        }
        .task(id: profile.id) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showBody, onDismiss: { Task { await load() } }, content: {
            BodyView(profile: profile)
        })
    }

    private var list: some View {
        List {
            Section {
                SummaryHeader(results: results, filtering: onlyOutOfRange) {
                    withAnimation { onlyOutOfRange.toggle() }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            let bodyItems = bodyDashItems(bodyMeasurements, weightUnit: weightUnit)
            if !bodyItems.isEmpty {
                Section("Body") {
                    ForEach(bodyItems) { item in
                        Button { showBody = true } label: {
                            HStack(spacing: 8) {
                                Text(item.label).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if let status = item.status {
                                    Text(status)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(item.tint ?? .secondary)
                                }
                                Text(item.value).monospacedDigit()
                                    .foregroundStyle(item.tint ?? .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites) { row($0) }
                }
            }

            if sort == .category {
                ForEach(restGroups, id: \.0) { category, rows in
                    Section(category) {
                        ForEach(rows) { row($0) }
                    }
                }
            } else {
                Section {
                    ForEach(sorted(rest)) { row($0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "Search analytes")
    }

    @ViewBuilder private func row(_ r: LabResult) -> some View {
        NavigationLink(value: r) {
            ResultRow(result: r)
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await toggleFavorite(r) }
            } label: {
                let fav = r.isFavorite == true
                Label(fav ? "Unfavorite" : "Favorite", systemImage: fav ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
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
        // Body stats are supplementary — don't fail the dashboard if they error.
        bodyMeasurements = (try? await store.api.bodyMeasurements(profileId: profile.id)) ?? []
    }

    private func toggleFavorite(_ r: LabResult) async {
        do {
            if r.isFavorite == true {
                try await store.api.removeFavorite(profileId: profile.id, analyteId: r.analyteId)
            } else {
                try await store.api.addFavorite(profileId: profile.id, analyteId: r.analyteId)
            }
            await load()
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
                if result.isFavorite == true {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
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

/// A changing body stat for the dashboard's Body section (excludes height + age).
struct BodyDashItem: Identifiable {
    let id: String
    let label: String
    let value: String
    var tint: Color?    // value/status color for graded metrics (BMI, blood pressure)
    var status: String? // category label, e.g. "Healthy", "Stage 2"
}

/// BMI category + color (WHO bands).
func bmiStatus(_ bmi: Double) -> (label: String, tint: Color) {
    switch bmi {
    case ..<18.5: return ("Underweight", .statusWarn)
    case ..<25: return ("Healthy", .statusInRange)
    case ..<30: return ("Overweight", .statusWarn)
    default: return ("Obese", .statusHigh)
    }
}

/// Blood-pressure category + color (ACC/AHA bands).
func bpStatus(systolic sys: Double, diastolic dia: Double) -> (label: String, tint: Color) {
    if sys >= 140 || dia >= 90 { return ("Stage 2", .statusHigh) }
    if sys >= 130 || dia >= 80 { return ("Stage 1", .statusWarn) }
    if sys >= 120 { return ("Elevated", .statusWarn) }
    return ("Normal", .statusInRange)
}

/// Latest changing body stats in display order; empty metrics are skipped.
func bodyDashItems(_ rows: [BodyMeasurement], weightUnit: String) -> [BodyDashItem] {
    func latest(_ kind: String) -> BodyMeasurement? { rows.first { $0.kind == kind } }
    var items: [BodyDashItem] = []
    if let w = latest("weight") {
        let value = weightUnit == "lb"
            ? String(format: "%.1f lb", w.value * 2.20462)
            : String(format: "%.1f kg", w.value)
        items.append(BodyDashItem(id: "weight", label: "Weight", value: value))
    }
    if let w = latest("weight"), let h = latest("height"), h.value > 0 {
        let m = h.value / 100
        let bmi = w.value / (m * m)
        let s = bmiStatus(bmi)
        items.append(BodyDashItem(id: "bmi", label: "BMI", value: String(format: "%.1f", bmi),
                                  tint: s.tint, status: s.label))
    }
    if let bp = latest("blood_pressure") {
        let value = bp.value2.map { String(format: "%.0f/%.0f mmHg", bp.value, $0) }
            ?? String(format: "%.0f mmHg", bp.value)
        let s = bp.value2.map { bpStatus(systolic: bp.value, diastolic: $0) }
        items.append(BodyDashItem(id: "bp", label: "Blood Pressure", value: value,
                                  tint: s?.tint, status: s?.label))
    }
    if let m = latest("resting_heart_rate") {
        items.append(BodyDashItem(id: "rhr", label: "Resting Heart Rate", value: String(format: "%.0f bpm", m.value)))
    }
    if let m = latest("body_fat") {
        items.append(BodyDashItem(id: "bf", label: "Body Fat", value: String(format: "%.1f%%", m.value)))
    }
    if let m = latest("waist") {
        items.append(BodyDashItem(id: "waist", label: "Waist", value: String(format: "%.0f cm", m.value)))
    }
    if let m = latest("vo2max") {
        items.append(BodyDashItem(id: "vo2", label: "Cardio Fitness", value: String(format: "%.1f mL/kg·min", m.value)))
    }
    if let m = latest("oxygen") {
        items.append(BodyDashItem(id: "spo2", label: "Blood Oxygen", value: String(format: "%.0f%%", m.value)))
    }
    return items
}

/// Opens the dashboard with a verdict, not just a list: total markers, how many
/// are out of range (tap to filter), and when the panel was last updated.
struct SummaryHeader: View {
    let results: [LabResult]
    let filtering: Bool
    let onToggle: () -> Void

    private var outOfRange: Int { results.filter(\.isAbnormal).count }
    private var latest: String? { results.compactMap(\.observedDate).max() }

    var body: some View {
        // The out-of-range count toggles a filter; with nothing out of range
        // there's nothing to filter, so it's just a static "all clear" badge.
        if outOfRange > 0 {
            Button(action: onToggle) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(results.count) markers")
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(filtering ? Color.statusHigh : .secondary)
            }
            Spacer()
            chip
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if filtering { return "Showing out of range · tap to clear" }
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
                .overlay {
                    if filtering {
                        Circle().strokeBorder(Color.statusHigh, lineWidth: 2).padding(-3)
                    }
                }
        }
    }
}
