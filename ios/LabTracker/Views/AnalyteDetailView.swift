import SwiftUI
import Charts

/// One analyte's readings over time (Swift Charts) plus the stored AI analysis.
struct AnalyteDetailView: View {
    @Environment(Store.self) private var store
    let profile: Profile
    let analyteId: String
    let analyteName: String

    @State private var points: [LabResult] = []
    @State private var loading = false
    @State private var error: String?

    @State private var analysis: Analysis?
    @State private var analysisLoaded = false

    private struct Point: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let abnormal: Bool
    }

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var chartData: [Point] {
        points.compactMap { r in
            guard let v = r.valueNumeric,
                  let ds = r.observedDate,
                  let d = Self.dateParser.date(from: ds) else { return nil }
            return Point(id: r.id, date: d, value: v, abnormal: r.isAbnormal)
        }
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
                if chartData.count >= 2 {
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
        Chart(chartData) { p in
            LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .foregroundStyle(.blue)
            PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .foregroundStyle(p.abnormal ? .red : .blue)
        }
        .frame(height: 200)
        .padding(.vertical, 4)
    }

    @ViewBuilder private var analysisSection: some View {
        if let analysis {
            VStack(alignment: .leading, spacing: 6) {
                if analysis.stale {
                    Label("New results since this was generated", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.orange)
                }
                MarkdownText(text: analysis.content)
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
        do {
            points = try await store.api.trend(profileId: profile.id, analyteId: analyteId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        // Best-effort: analysis may not exist.
        analysis = try? await store.api.analysis(profileId: profile.id, analyteId: analyteId)
        analysisLoaded = true
    }
}
