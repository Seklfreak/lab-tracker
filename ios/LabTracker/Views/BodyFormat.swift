import Foundation

// Weight/height unit conversions for the Body sheet. Stored values are canonical
// (kg, cm); these convert to the chosen display unit, including feet+inches.
extension BodyView {
    /// Full display string for a canonical value in the chosen unit.
    func displayString(_ canonical: Double, kind: String, unit: String) -> String {
        switch (kind, unit) {
        case ("weight", "lb"): return String(format: "%.1f lb", canonical * 2.20462)
        case ("weight", _): return String(format: "%.1f kg", canonical)
        case ("height", "ftin"):
            let totalInches = canonical / 2.54
            let ft = Int(totalInches / 12)
            var inch = Int((totalInches - Double(ft) * 12).rounded())
            if inch == 12 { return "\(ft + 1)′ 0″" }
            if inch < 0 { inch = 0 }
            return "\(ft)′ \(inch)″"
        default: return String(format: "%.1f cm", canonical) // height cm
        }
    }

    /// Numeric value for the trend chart's y-axis.
    func displayNumeric(_ canonical: Double, kind: String, unit: String) -> Double {
        switch (kind, unit) {
        case ("weight", "lb"): return canonical * 2.20462
        case ("height", "ftin"), ("height", "in"): return canonical / 2.54 // inches
        default: return canonical
        }
    }

    /// Convert a single-field display value back to canonical (kg / cm).
    func toCanonical(_ display: Double, kind: String, unit: String) -> Double {
        switch (kind, unit) {
        case ("weight", "lb"): return display / 2.20462
        default: return display // weight kg, height cm
        }
    }
}
