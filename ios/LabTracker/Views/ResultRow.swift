import SwiftUI

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
