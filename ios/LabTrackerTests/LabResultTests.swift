import Testing
@testable import LabTracker

struct LabResultTests {
    private func make(
        numeric: Double? = nil,
        text: String? = nil,
        low: Double? = nil,
        high: Double? = nil,
        refText: String? = nil,
        unit: String? = nil
    ) -> LabResult {
        LabResult(
            id: "1", reportId: "r", analyteId: "a", analyteName: "X", category: nil,
            rawTestName: "x", valueText: text, valueNumeric: numeric, unit: unit,
            referenceLow: low, referenceHigh: high, referenceText: refText, note: nil,
            observedDate: "2026-01-01", sourceLab: nil, count: nil, isFavorite: nil
        )
    }

    @Test func displayValuePrefersNumericThenText() {
        #expect(make(numeric: 5.5).displayValue == "5.5")
        #expect(make(numeric: 5.0).displayValue == "5")        // whole numbers drop the .0
        #expect(make(text: "Negative").displayValue == "Negative")
        #expect(make().displayValue == "—")
    }

    @Test func abnormalUsesTheReferenceBand() {
        #expect(make(numeric: 5, low: 1, high: 10).isAbnormal == false)
        #expect(make(numeric: 0.5, low: 1, high: 10).isAbnormal == true)   // below low
        #expect(make(numeric: 11, low: 1, high: 10).isAbnormal == true)    // above high
        #expect(make(numeric: 11, high: 10).isAbnormal == true)            // only a high bound
        #expect(make(text: "Negative").isAbnormal == false)               // no numeric → never abnormal
    }

    @Test func referenceLabelFormatting() {
        #expect(make(low: 1, high: 10).referenceLabel == "1–10")
        #expect(make(high: 10).referenceLabel == "<10")
        #expect(make(low: 1).referenceLabel == ">1")
        #expect(make(refText: "Negative").referenceLabel == "Negative")    // text wins
        #expect(make().referenceLabel == nil)
    }

    @Test func trimNumberDropsTrailingZeros() {
        #expect(LabResult.trimNumber(5.0) == "5")
        #expect(LabResult.trimNumber(5.5) == "5.5")
        #expect(LabResult.trimNumber(-3.0) == "-3")
    }
}
