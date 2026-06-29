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
                    Section("Trend") { chart }
                }
                Section("Readings") { readings }
                Section("AI analysis") { analysisSection }
            }
        }
        .navigationTitle(analyteName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: analyteId) { await load() }
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

    @ViewBuilder private var chart: some View {
        Chart {
            if let lo = refLow, let hi = refHigh {
                RectangleMark(yStart: .value("Low", lo), yEnd: .value("High", hi))
                    .foregroundStyle(Color.statusInRange.opacity(0.12))
            } else if let hi = refHigh {
                RuleMark(y: .value("Upper limit", hi))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.statusInRange.opacity(0.5))
            } else if let lo = refLow {
                RuleMark(y: .value("Lower limit", lo))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.statusInRange.opacity(0.5))
            }
            ForEach(chartPoints) { p in
                AreaMark(x: .value("Date", p.date), y: .value("Value", p.value))
                    .foregroundStyle(.linearGradient(
                        colors: [Color.brandTeal.opacity(0.22), Color.brandTeal.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                    .foregroundStyle(Color.brandTeal)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                    .foregroundStyle(p.status == .unknown ? Color.brandTeal : p.status.tint)
                    .symbolSize(p.status == .high || p.status == .low ? 60 : 26)
            }
        }
        .frame(height: 220)
        .padding(.vertical, 6)
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
                return Point(id: r.id, date: date, value: v, status: r.status)
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
