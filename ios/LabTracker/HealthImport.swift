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

/// One row in the HealthKit debug screen: how many samples of a type Lab Tracker
/// can read, and the latest value.
struct HealthDiag: Identifiable {
    let id: String
    let label: String
    let count: Int
    let latest: String?
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
        // Blood pressure: request the components *and* the correlation type — some
        // iOS versions only surface "Blood Pressure" in the prompt with the latter.
        types.insert(HKQuantityType(.bloodPressureSystolic))
        types.insert(HKQuantityType(.bloodPressureDiastolic))
        types.insert(HKCorrelationType(.bloodPressure))
        try await store.requestAuthorization(toShare: [], read: types)
    }

    /// Scalar samples for one kind, newest first.
    func samples(kind: String) async throws -> [HealthSample] {
        guard let m = metric(for: kind) else { return [] }
        let raw = try await rawSamples(m.type)
        return raw.compactMap { sample in
            guard let q = sample as? HKQuantitySample else { return nil }
            return HealthSample(value: q.quantity.doubleValue(for: m.unit) * m.scale, value2: nil,
                                date: q.endDate, uuid: q.uuid.uuidString)
        }
    }

    /// Blood pressure → systolic in `value`, diastolic in `value2`. Most sources
    /// store readings as a correlation; some leave loose systolic/diastolic
    /// samples, so fall back to pairing those by timestamp.
    func bloodPressureSamples() async throws -> [HealthSample] {
        let viaCorrelation = try await correlationBP()
        if !viaCorrelation.isEmpty { return viaCorrelation }
        return try await pairedBP()
    }

    private func correlationBP() async throws -> [HealthSample] {
        let mmHg = HKUnit.millimeterOfMercury()
        let systolic = HKQuantityType(.bloodPressureSystolic)
        let diastolic = HKQuantityType(.bloodPressureDiastolic)
        let raw = try await rawSamples(HKCorrelationType(.bloodPressure))
        return raw.compactMap { sample in
            guard let reading = sample as? HKCorrelation,
                  let sys = (reading.objects(for: systolic).first as? HKQuantitySample)?.quantity.doubleValue(for: mmHg),
                  let dia = (reading.objects(for: diastolic).first as? HKQuantitySample)?.quantity.doubleValue(for: mmHg)
            else { return nil }
            return HealthSample(value: sys, value2: dia, date: reading.endDate, uuid: reading.uuid.uuidString)
        }
    }

    private func pairedBP() async throws -> [HealthSample] {
        let mmHg = HKUnit.millimeterOfMercury()
        let systolic = (try await rawSamples(HKQuantityType(.bloodPressureSystolic))).compactMap { $0 as? HKQuantitySample }
        let diastolic = (try await rawSamples(HKQuantityType(.bloodPressureDiastolic))).compactMap { $0 as? HKQuantitySample }
        // Systolic & diastolic of one reading share a timestamp — index diastolic by it.
        var diaByTime: [TimeInterval: HKQuantitySample] = [:]
        for d in diastolic { diaByTime[d.startDate.timeIntervalSince1970] = d }
        return systolic.compactMap { s in
            guard let d = diaByTime[s.startDate.timeIntervalSince1970] else { return nil }
            return HealthSample(value: s.quantity.doubleValue(for: mmHg), value2: d.quantity.doubleValue(for: mmHg),
                                date: s.endDate, uuid: s.uuid.uuidString)
        }
    }

    /// What Lab Tracker can actually read per type — powers the HealthKit debug
    /// screen. A count of 0 means the type is unshared (read denials are hidden
    /// from apps) or genuinely empty.
    func diagnostics() async -> [HealthDiag] {
        var out: [HealthDiag] = []
        for kind in scalarKinds {
            let s = (try? await samples(kind: kind)) ?? []
            out.append(HealthDiag(id: kind, label: BodyView.metricLabel(kind), count: s.count,
                                  latest: s.first.map { String(format: "%.1f", $0.value) }))
        }
        let sys = (try? await rawSamples(HKQuantityType(.bloodPressureSystolic)))?.count ?? 0
        let dia = (try? await rawSamples(HKQuantityType(.bloodPressureDiastolic)))?.count ?? 0
        out.append(HealthDiag(id: "bp_sys", label: "BP systolic (raw)", count: sys, latest: nil))
        out.append(HealthDiag(id: "bp_dia", label: "BP diastolic (raw)", count: dia, latest: nil))
        let corr = (try? await correlationBP()) ?? []
        out.append(HealthDiag(id: "bp_corr", label: "BP via correlation", count: corr.count,
                              latest: corr.first.map { String(format: "%.0f/%.0f", $0.value, $0.value2 ?? 0) }))
        let loose = (try? await pairedBP()) ?? []
        out.append(HealthDiag(id: "bp_loose", label: "BP via paired samples", count: loose.count,
                              latest: loose.first.map { String(format: "%.0f/%.0f", $0.value, $0.value2 ?? 0) }))
        return out
    }

    /// Most-recent samples for a type, newest first.
    private func rawSamples(_ type: HKSampleType) async throws -> [HKSample] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: limit, sortDescriptors: [sort]) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: results ?? [])
            }
            store.execute(query)
        }
    }
}
