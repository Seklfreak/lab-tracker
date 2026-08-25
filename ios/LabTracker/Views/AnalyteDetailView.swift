import SwiftUI
import Charts

/// One analyte's readings over time (Swift Charts) plus the stored AI analysis.
/// A hero shows the latest value + where it sits in range; the trend chart draws
/// the reference band behind the line so out-of-range stretches are visible.
/// Chart points and the parsed analysis are computed once in `load()` so the
/// view body stays cheap (no per-render date parsing or markdown work) — that's
/// what keeps the push animation smooth.
struct AnalyteDetailView: View {
    @Environment(Store.self) private var store
    let profile: Profile
    let analyteId: String
    let analyteName: String
    /// Called after a successful toggle so the pushing view (the dashboard) can
    /// update its own copy of this analyte instead of refetching on pop.
    var onFavoriteChange: ((Bool) -> Void)?

    @State private var isFavorite = false
    @State private var favoriteBusy = false
    @State private var favoriteError: String?
    @State private var points: [LabResult] = []
    @State private var chartPoints: [Point] = []
    @State private var analysis: Analysis?
    @State private var analysisBlocks: [MarkdownText.Block] = []
    @State private var analysisLoaded = false
    @State private var generating = false
    @State private var analysisError: String?
    @State private var loading = false
    @State private var error: String?

    struct Point: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let status: LabStatus
    }

    private var latest: LabResult? { points.last }
    private var unit: String? { points.last?.unit }
    private var refLow: Double? { points.last?.referenceLow }
    private var refHigh: Double? { points.last?.referenceHigh }

    var body: some View {
        List {
            if loading && points.isEmpty {
                ProgressView()
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else {
                if let latest {
                    Section {
                        hero(latest)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
                }
                if chartPoints.count >= 2 {
                    Section("Trend") {
                        AnalyteTrendChart(points: chartPoints, refLow: refLow, refHigh: refHigh)
                        if refLow != nil || refHigh != nil {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.statusInRange.opacity(0.25))
                                    .frame(width: 18, height: 11)
                                Text("Shaded band = normal range")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Readings") { readings }
                Section("AI analysis") { analysisSection }
            }
        }
        .navigationTitle(analyteName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await toggleFavorite() }
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Color.yellow : Color.accentColor)
                }
                .disabled(favoriteBusy || points.isEmpty)
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
        }
        .task(id: analyteId) { await load() }
        // A failed toggle must not replace the chart and analysis with the
        // full-screen error state, so it surfaces as an alert.
        .alert("Couldn’t update favorite", isPresented: .constant(favoriteError != nil), presenting: favoriteError) { _ in
            Button("OK") { favoriteError = nil }
        } message: { Text($0) }
    }

    @ViewBuilder private func hero(_ latest: LabResult) -> some View {
        let status = latest.status
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(latest.displayValue)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(status == .unknown ? Color.primary : status.tint)
                if let unit { Text(unit).font(.title3).foregroundStyle(.secondary) }
                Spacer()
                if !status.label.isEmpty {
                    Text(status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(status.tint.opacity(0.15)))
                }
            }
            if let v = latest.valueNumeric, refLow != nil || refHigh != nil {
                RangeTrack(value: v, low: refLow, high: refHigh, status: status)
            }
            if let ref = latest.referenceLabel {
                Text("Reference \(ref)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var readings: some View {
        ForEach(points.reversed()) { r in
            HStack {
                Text(LabDate.pretty(r.observedDate) ?? r.observedDate ?? "—")
                Spacer()
                Text(r.displayValue + (r.unit.map { " \($0)" } ?? ""))
                    .monospacedDigit()
                    .foregroundStyle(r.status == .unknown ? Color.primary : r.status.tint)
            }
            .font(.callout)
        }
    }

    @ViewBuilder private var analysisSection: some View {
        if generating {
            HStack(spacing: 10) {
                ProgressView()
                Text("Analyzing your results…").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if let analysis {
            VStack(alignment: .leading, spacing: 10) {
                if analysis.stale {
                    let msg = "New results since this was generated "
                        + "(\(analysis.basedOnCount) → \(analysis.currentCount) readings). Regenerate to include them."
                    Label(msg, systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(Color.statusWarn)
                }
                MarkdownText(blocks: analysisBlocks)
                HStack {
                    Text("Generated \(LabDate.prettyTimestamp(analysis.generatedAt))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await generate() } } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 2)
        } else if analysisLoaded {
            VStack(alignment: .leading, spacing: 10) {
                Text("Get a plain-language explanation of this analyte, your trend over time, and how related results connect.")
                    .font(.callout).foregroundStyle(.secondary)
                Button { Task { await generate() } } label: {
                    Label("Generate AI analysis", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandTeal)
            }
            .padding(.vertical, 2)
        } else {
            ProgressView()
        }

        if let analysisError {
            Text(analysisError).font(.caption).foregroundStyle(.red)
        }
    }

    private func generate() async {
        generating = true
        analysisError = nil
        defer { generating = false }
        do {
            let a = try await store.api.generateAnalysis(profileId: profile.id, analyteId: analyteId)
            analysis = a
            analysisBlocks = MarkdownText.parse(a.content)
        } catch {
            analysisError = error.report()
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }

        // Fetch the trend and the (optional) analysis concurrently.
        async let trendTask = store.api.trend(profileId: profile.id, analyteId: analyteId)
        async let analysisTask = store.api.analysis(profileId: profile.id, analyteId: analyteId)

        do {
            let rows = try await trendTask
            points = rows
            chartPoints = rows.compactMap { r in
                guard let v = r.valueNumeric, let day = r.observedDate, let date = Self.parseDay(day) else { return nil }
                return Point(id: r.id, date: date, value: v, status: r.status)
            }
            // Favorite state is per-analyte, so every row carries the same flag.
            isFavorite = rows.last?.isFavorite == true
            error = nil
        } catch {
            self.error = error.report()
        }

        let a = (try? await analysisTask) ?? nil
        analysis = a
        analysisBlocks = a.map { MarkdownText.parse($0.content) } ?? []
        analysisLoaded = true
    }

    /// Optimistic: the star fills immediately and reverts if the call fails.
    /// `favoriteBusy` keeps a double-tap from firing an add and a remove that
    /// can land out of order.
    private func toggleFavorite() async {
        guard !favoriteBusy else { return }
        favoriteBusy = true
        defer { favoriteBusy = false }

        let target = !isFavorite
        isFavorite = target
        do {
            if target {
                try await store.api.addFavorite(profileId: profile.id, analyteId: analyteId)
            } else {
                try await store.api.removeFavorite(profileId: profile.id, analyteId: analyteId)
            }
            onFavoriteChange?(target)
        } catch {
            isFavorite = !target
            favoriteError = error.report()
        }
    }

    /// Fast "yyyy-MM-dd" parse via DateComponents (DateFormatter is too slow to
    /// call per point on the render path).
    private static func parseDay(_ s: String) -> Date? {
        let parts = s.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d))
    }
}
