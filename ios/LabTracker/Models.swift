import Foundation

// Mirrors the backend JSON DTOs (see backend/internal/api/dto.go).

struct Profile: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let dateOfBirth: String?
    let isOwner: Bool
}

struct LabResult: Codable, Identifiable, Hashable {
    let id: String
    let reportId: String
    let analyteId: String
    let analyteName: String
    let category: String?
    let rawTestName: String
    let valueText: String?
    let valueNumeric: Double?
    let unit: String?
    let referenceLow: Double?
    let referenceHigh: Double?
    let referenceText: String?
    let note: String?
    let observedDate: String?
    let sourceLab: String?
    let count: Int?
    let isFavorite: Bool?

    /// Display string for the value (numeric preferred, else qualitative text).
    var displayValue: String {
        if let v = valueNumeric { return Self.trimNumber(v) }
        return valueText ?? "—"
    }

    /// out-of-range / abnormal flag derived from the numeric reference band.
    var isAbnormal: Bool {
        guard let v = valueNumeric else { return false }
        if let lo = referenceLow, v < lo { return true }
        if let hi = referenceHigh, v > hi { return true }
        return false
    }

    var referenceLabel: String? {
        if let t = referenceText, !t.isEmpty { return t }
        switch (referenceLow, referenceHigh) {
        case let (lo?, hi?): return "\(Self.trimNumber(lo))–\(Self.trimNumber(hi))"
        case let (nil, hi?): return "<\(Self.trimNumber(hi))"
        case let (lo?, nil): return ">\(Self.trimNumber(lo))"
        default: return nil
        }
    }

    static func trimNumber(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e15 {
            return String(Int(v))
        }
        return String(format: "%g", v)
    }
}

struct Analysis: Codable, Hashable {
    let content: String
    let generatedAt: String
    let basedOnCount: Int
    let currentCount: Int
    let stale: Bool
}

struct AnalysisEnvelope: Codable {
    let analysis: Analysis?
}

/// Public /health payload — carries the running server's build version.
struct Health: Codable {
    let status: String
    let version: String
}

/// A self-entered body metric. Value is canonical: weight in kilograms, height
/// in centimetres (the UI converts for display).
struct BodyMeasurement: Codable, Identifiable, Hashable {
    let id: String
    let kind: String // "weight" | "height"
    let value: Double
    let measuredOn: String // YYYY-MM-DD
    let source: String // "manual" | "apple_health" | …
}
