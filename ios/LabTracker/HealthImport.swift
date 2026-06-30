import Foundation
import HealthKit

/// Reads body metrics from Apple Health for import into Lab Tracker. Scalar
/// values come back in the units Lab Tracker stores (kg, cm, %, bpm, mmHg,
/// mL/kg·min); blood pressure carries both systolic (`value`) and diastolic
/// (`value2`). Each sample's stable UUID makes the import idempotent.
struct HealthSample {
    let value: Double
    let value2: Double?
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

    /// Scalar body-metric kinds we import, in display order.
    let scalarKinds = ["weight", "height", "body_fat", "waist", "resting_heart_rate", "vo2max", "oxygen"]

    private struct Metric {
        let type: HKQuantityType
        let unit: HKUnit
        let scale: Double // applied to the raw HealthKit value (e.g. fraction → %)
    }

    private func metric(for kind: String) -> Metric? {
        switch kind {
        case "weight": return Metric(type: HKQuantityType(.bodyMass), unit: .gramUnit(with: .kilo), scale: 1)
        case "height": return Metric(type: HKQuantityType(.height), unit: .meterUnit(with: .centi), scale: 1)
        case "waist": return Metric(type: HKQuantityType(.waistCircumference), unit: .meterUnit(with: .centi), scale: 1)
        case "body_fat": return Metric(type: HKQuantityType(.bodyFatPercentage), unit: .percent(), scale: 100)
        case "oxygen": return Metric(type: HKQuantityType(.oxygenSaturation), unit: .percent(), scale: 100)
        case "resting_heart_rate":
            return Metric(type: HKQuantityType(.restingHeartRate), unit: .count().unitDivided(by: .minute()), scale: 1)
        case "vo2max": return Metric(type: HKQuantityType(.vo2Max), unit: HKUnit(from: "ml/kg*min"), scale: 1)
        default: return nil
        }
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthImportError.unavailable }
        var types = Set<HKObjectType>()
        for kind in scalarKinds { if let m = metric(for: kind) { types.insert(m.type) } }
        types.insert(HKQuantityType(.bloodPressureSystolic))
        types.insert(HKQuantityType(.bloodPressureDiastolic))
        try await store.requestAuthorization(toShare: [], read: types)
    }

    /// Scalar samples for one kind, newest first.
    func samples(kind: String) async throws -> [HealthSample] {
        guard let m = metric(for: kind) else { return [] }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: m.type, predicate: nil, limit: limit, sortDescriptors: [sort]) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
        return samples.map {
            HealthSample(value: $0.quantity.doubleValue(for: m.unit) * m.scale, value2: nil,
                         date: $0.endDate, uuid: $0.uuid.uuidString)
        }
    }

    /// Blood pressure correlations → systolic in `value`, diastolic in `value2`.
    func bloodPressureSamples() async throws -> [HealthSample] {
        let correlation = HKCorrelationType(.bloodPressure)
        let systolic = HKQuantityType(.bloodPressureSystolic)
        let diastolic = HKQuantityType(.bloodPressureDiastolic)
        let mmHg = HKUnit.millimeterOfMercury()
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let samples: [HKCorrelation] = try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: correlation, predicate: nil, limit: limit, sortDescriptors: [sort]) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (results as? [HKCorrelation]) ?? [])
            }
            store.execute(query)
        }
        return samples.compactMap { reading in
            guard let sys = (reading.objects(for: systolic).first as? HKQuantitySample)?.quantity.doubleValue(for: mmHg),
                  let dia = (reading.objects(for: diastolic).first as? HKQuantitySample)?.quantity.doubleValue(for: mmHg)
            else { return nil }
            return HealthSample(value: sys, value2: dia, date: reading.endDate, uuid: reading.uuid.uuidString)
        }
    }
}
