import SwiftUI

extension Color {
    /// Brand teal — matches the app icon / web favicon gradient (#15B8A6).
    static let brandTeal = Color(red: 0.082, green: 0.722, blue: 0.651)

    /// Status palette. Direction is encoded, not just "abnormal = red": a high
    /// value reads differently from a low one.
    static let statusInRange = Color(red: 0.059, green: 0.620, blue: 0.557) // #0F9E8E
    static let statusHigh = Color(red: 0.878, green: 0.404, blue: 0.227)    // #E0673A
    static let statusLow = Color(red: 0.357, green: 0.424, blue: 0.878)     // #5B6CE0
}

/// Where a reading sits relative to its reference interval.
enum LabStatus {
    case low, inRange, high, unknown

    var tint: Color {
        switch self {
        case .low: return .statusLow
        case .high: return .statusHigh
        case .inRange: return .statusInRange
        case .unknown: return .secondary
        }
    }

    /// Arrow for the out-of-range direction; nil when in range or unknown.
    var directionSymbol: String? {
        switch self {
        case .high: return "arrow.up"
        case .low: return "arrow.down"
        default: return nil
        }
    }

    /// Short status label for the detail-screen badge.
    var label: String {
        switch self {
        case .high: return "Above range"
        case .low: return "Below range"
        case .inRange: return "In range"
        case .unknown: return ""
        }
    }
}

/// Formats the API's "yyyy-MM-dd" observed dates for display. Centralized so the
/// dashboard header and the detail screen read the same way.
enum LabDate {
    static func pretty(_ s: String?) -> String? {
        guard let s else { return nil }
        let parts = s.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              let date = Calendar.current.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

extension LabResult {
    var status: LabStatus {
        guard let v = valueNumeric else { return .unknown }
        if let lo = referenceLow, v < lo { return .low }
        if let hi = referenceHigh, v > hi { return .high }
        if referenceLow != nil || referenceHigh != nil { return .inRange }
        return .unknown
    }
}
