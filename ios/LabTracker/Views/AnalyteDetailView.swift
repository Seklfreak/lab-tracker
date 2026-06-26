import SwiftUI
import Charts

/// One analyte's readings over time (Swift Charts) plus the stored AI analysis.
/// Chart points and the parsed analysis are computed once in `load()` so the
/// view body stays cheap (no per-render date parsing or markdown work) — that's
/// what keeps the push animation smooth.
struct AnalyteDetailView: View {
    @Environment(Store.self) private var store
    let profile: Profile
    let analyteId: String
    let analyteName: String

    @State private var points: [LabResult] = []
    @State private var chartPoints: [Point] = []
    @State private var analysis: Analysis?
    @State private var analysisBlocks: [MarkdownText.Block] = []
    @State private var analysisLoaded = false
    @State private var loading = false
    @State private var error: String?

    struct Point: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let abnormal: Bool
    }

    private var latest: LabResult? { points.last }
    private var unit: String? { points.last?.unit }

    var body: some View {
        List {
            if loading && points.isEmpty {
                ProgressView()
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else {
                if chartPoints.count >= 2 {
                    Section("Trend") { chart }
                } else if let latest {
                    Section("Latest") {
                        LabeledContent(latest.displayValue + (unit.map { " \($0)" } ?? "")) {
                            Text(latest.observedDate ?? "").foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Readings") {
                    ForEach(points.reversed()) { r in
                        HStack {
                            Text(r.observedDate ?? "—")
                            Spacer()
                            Text(r.displayValue + (r.unit.map { " \($0)" } ?? ""))
                                .foregroundStyle(r.isAbnormal ? .red : .primary)
                        }
                        .font(.callout)
                    }
                }

                Section("AI analysis") { analysisSection }
            }
        }
        .navigationTitle(analyteName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: analyteId) { await load() }
    }

    @ViewBuilder private var chart: some View {
        Chart(chartPoints) { p in
            LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .foregroundStyle(.blue)
            PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .foregroundStyle(p.abnormal ? .red : .blue)
        }
        .frame(height: 200)
        .padding(.vertical, 4)
    }

    @ViewBuilder private var analysisSection: some View {
        if analysis != nil {
            VStack(alignment: .leading, spacing: 6) {
                if analysis?.stale == true {
                    Label("New results since this was generated", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.orange)
                }
                MarkdownText(blocks: analysisBlocks)
            }
        } else if analysisLoaded {
            Text("No analysis generated yet.").foregroundStyle(.secondary)
        } else {
            ProgressView()
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
                return Point(id: r.id, date: date, value: v, abnormal: r.isAbnormal)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }

        let a = (try? await analysisTask) ?? nil
        analysis = a
        analysisBlocks = a.map { MarkdownText.parse($0.content) } ?? []
        analysisLoaded = true
    }

    /// Fast "yyyy-MM-dd" parse via DateComponents (DateFormatter is too slow to
    /// call per point on the render path).
    private static func parseDay(_ s: String) -> Date? {
        let parts = s.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d))
    }
}
