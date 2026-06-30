import Foundation
import HealthKit

/// Reads weight & height from Apple Health for import into Lab Tracker. Values
/// come back in canonical units (kg, cm) with each sample's stable UUID so the
/// import is idempotent (the server dedupes on source + external id).
struct HealthSample {
    let value: Double
    let date: Date
    let uuid: String
}

enum HealthImportError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Health isn’t available on this device."
        }
    }
}

@MainActor
final class HealthImporter {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Most recent samples to pull per kind — enough history without flooding.
    private let limit = 365

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthImportError.unavailable }
        let types: Set<HKObjectType> = [HKQuantityType(.bodyMass), HKQuantityType(.height)]
        try await store.requestAuthorization(toShare: [], read: types)
    }

    /// Samples for "weight" or "height" in canonical units (kg / cm), newest first.
    func samples(kind: String) async throws -> [HealthSample] {
        let type: HKQuantityType
        let unit: HKUnit
        switch kind {
        case "weight": type = HKQuantityType(.bodyMass); unit = .gramUnit(with: .kilo)
        case "height": type = HKQuantityType(.height); unit = .meterUnit(with: .centi)
        default: return []
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: limit, sortDescriptors: [sort]) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
        return samples.map {
            HealthSample(value: $0.quantity.doubleValue(for: unit), date: $0.endDate, uuid: $0.uuid.uuidString)
        }
    }
}
