import SwiftUI
import UIKit

/// A slim gauge showing where a value sits within (or past) its reference
/// interval: the normal band is highlighted and the marker is colored by status.
/// The signature element of the dashboard — only meaningful with a numeric value
/// and at least one bound, so callers gate on that.
struct RangeTrack: View {
    let value: Double
    let low: Double?
    let high: Double?
    let status: LabStatus

    var body: some View {
        let g = TrackGeometry(value: value, low: low, high: high)
        GeometryReader { proxy in
            let pad: CGFloat = 6
            let usable = max(1, proxy.size.width - pad * 2)
            let x = { (f: CGFloat) in pad + f * usable }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: 8)
                Capsule()
                    .fill(Color.statusInRange.opacity(0.40))
                    .frame(width: max(6, x(g.bandHighFrac) - x(g.bandLowFrac)), height: 8)
                    .offset(x: x(g.bandLowFrac))
                Circle()
                    .fill(status.tint)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 3))
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .offset(x: x(g.valueFrac) - 8)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

/// Maps a value and its reference bounds onto a 0…1 track. The normal band is
/// padded so in-range values sit mid-track and out-of-range values read outside;
/// an open-ended interval (only one bound) runs to the matching edge.
private struct TrackGeometry {
    let valueFrac: CGFloat
    let bandLowFrac: CGFloat
    let bandHighFrac: CGFloat

    init(value: Double, low: Double?, high: Double?) {
        let bandLo: Double
        let bandHi: Double
        var openLow = false
        var openHigh = false
        switch (low, high) {
        case let (lo?, hi?): bandLo = lo; bandHi = hi
        case let (nil, hi?): bandLo = min(0, value); bandHi = hi; openLow = true
        case let (lo?, nil): bandLo = lo; bandHi = max(value, lo); openHigh = true
        case (nil, nil): bandLo = value; bandHi = value
        }
        let core = max(bandHi - bandLo, max(abs(value), 1) * 0.2)
        let domainLo = bandLo - (openLow ? core * 0.12 : core * 1.1)
        let domainHi = bandHi + (openHigh ? core * 0.12 : core * 1.1)
        let width = max(domainHi - domainLo, 0.0001)
        func frac(_ v: Double) -> CGFloat { CGFloat(min(max((v - domainLo) / width, 0), 1)) }
        valueFrac = frac(value)
        bandLowFrac = openLow ? 0 : frac(bandLo)
        bandHighFrac = openHigh ? 1 : frac(bandHi)
    }
}
