import Testing
import HealthKit
@testable import LabTracker

/// The sync descriptor table is the single source of truth for what the manual
/// import and the background sync pull from Apple Health. Guard its coverage and
/// the type/kind wiring so a refactor can't silently drop a metric.
@MainActor
struct HealthSyncTests {
    @Test func descriptorsCoverEveryScalarKindPlusBloodPressure() {
        let descriptors = HealthImporter.syncDescriptors()
        let kinds = descriptors.map(\.kind)

        // Every scalar kind, exactly once, in order, plus blood pressure at the end.
        #expect(kinds == HealthImporter.scalarKinds + ["blood_pressure"])
        #expect(Set(kinds).count == kinds.count) // no duplicates
    }

    @Test func bloodPressureSyncsFromTheCorrelationType() {
        let bp = HealthImporter.syncDescriptors().first { $0.kind == "blood_pressure" }
        #expect(bp?.sampleType == HKCorrelationType(.bloodPressure))
    }

    @Test func weightMapsToBodyMass() {
        let weight = HealthImporter.syncDescriptors().first { $0.kind == "weight" }
        #expect(weight?.sampleType == HKQuantityType(.bodyMass))
    }
}
