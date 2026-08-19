import SwiftUI
import Charts

/// One analyte's readings over time, with the reference band shaded behind the
/// line so out-of-range stretches read at a glance. Split out of
/// `AnalyteDetailView` to keep that view's body focused on layout.
struct AnalyteTrendChart: View {
    let points: [AnalyteDetailView.Point]
    let refLow: Double?
    let refHigh: Double?

    /// Y-axis range covering the readings and the reference bounds, padded a bit.
    /// Pinned explicitly so a one-sided band can extend to the chart edge.
    private var yDomain: ClosedRange<Double> {
        var vals = points.map(\.value)
        if let lo = refLow { vals.append(lo) }
        if let hi = refHigh { vals.append(hi) }
        guard let mn = vals.min(), let mx = vals.max() else { return 0...1 }
        let pad = max((mx - mn) * 0.12, 1)
        return (mn - pad)...(mx + pad)
    }

    var body: some View {
        Chart {
            // The shaded "good" zone. A one-sided range (> x / < x) shades from
            // the bound to the edge of the chart, so the healthy region is always
            // filled — not just marked with a line.
            if let lo = refLow, let hi = refHigh {
                band(from: lo, to: hi)
                bound(lo)
                bound(hi)
            } else if let hi = refHigh {
                band(from: yDomain.lowerBound, to: hi)
                bound(hi)
            } else if let lo = refLow {
                band(from: lo, to: yDomain.upperBound)
                bound(lo)
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                    .foregroundStyle(Color.brandTeal)
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                    .foregroundStyle(p.status == .unknown ? Color.brandTeal : p.status.tint)
                    .symbolSize(p.status == .high || p.status == .low ? 70 : 30)
            }
        }
        .chartYScale(domain: yDomain)
        .frame(height: 220)
        .padding(.vertical, 6)
    }

    /// The shaded normal-range band between two y-values.
    private func band(from lo: Double, to hi: Double) -> some ChartContent {
        RectangleMark(yStart: .value("From", lo), yEnd: .value("To", hi))
            .foregroundStyle(Color.statusInRange.opacity(0.20))
    }

    /// A dashed edge line marking a reference bound.
    private func bound(_ value: Double) -> some ChartContent {
        RuleMark(y: .value("Reference", value))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(Color.statusInRange.opacity(0.6))
    }
}
