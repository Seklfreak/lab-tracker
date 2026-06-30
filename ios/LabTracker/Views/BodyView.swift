import SwiftUI
import Charts

/// Per-profile body metrics: edit birthdate, track weight & height over time,
/// and see BMI. Weight/height are stored canonically (kg, cm); this view shows
/// and accepts them in the chosen unit — including feet+inches for height.
struct BodyView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let profile: Profile

    @State private var measurements: [BodyMeasurement] = []
    @State private var profileName = ""
    @State private var hasDOB = false
    @State private var dob = Date()
    @State private var loading = false
    @State private var saving = false
    @State private var importing = false
    @State private var expanded: Set<String> = [] // kinds whose full history is shown
    @State private var error: String?

    @AppStorage("weightUnit") private var weightUnit = "lb"   // kg | lb
    @AppStorage("heightUnit") private var heightUnit = "ftin" // cm | ftin

    private var latestWeightKg: Double? { measurements.first { $0.kind == "weight" }?.value }
    private var latestHeightCm: Double? { measurements.first { $0.kind == "height" }?.value }
    private var bmi: Double? {
        guard let w = latestWeightKg, let h = latestHeightCm, h > 0 else { return nil }
        let m = h / 100
        return w / (m * m)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Text(error).font(.caption).foregroundStyle(Color.statusHigh)
                }
                Section("Birthdate") {
                    Toggle("Set birthdate", isOn: $hasDOB)
                    if hasDOB {
                        DatePicker("Born", selection: $dob, in: ...Date(), displayedComponents: .date)
                    }
                }
                if let bmi {
                    Section("BMI") { bmiRow(bmi) }
                }
                if HealthImporter.isAvailable {
                    Section {
                        Button {
                            Task { await importFromHealth() }
                        } label: {
                            HStack {
                                Label("Import from Apple Health", systemImage: "heart.fill")
                                    .foregroundStyle(Color.statusHigh)
                                Spacer()
                                if importing { ProgressView() }
                            }
                        }
                        .disabled(importing)
                    } footer: {
                        Text("Pulls your recent weight, height, body fat, waist, resting heart rate, "
                            + "cardio fitness, blood oxygen, and blood pressure. Safe to re-run — duplicates are skipped.")
                    }
                }
                metricSection(kind: "weight", title: "Weight", unit: $weightUnit,
                              units: [("kg", "kg"), ("lb", "lb")])
                metricSection(kind: "height", title: "Height", unit: $heightUnit,
                              units: [("cm", "cm"), ("ftin", "ft / in")])
                vitalSection(kind: "blood_pressure", title: "Blood Pressure", format: Self.bp)
                vitalSection(kind: "resting_heart_rate", title: "Resting Heart Rate") {
                    String(format: "%.0f bpm", $0.value)
                }
                vitalSection(kind: "body_fat", title: "Body Fat") { String(format: "%.1f%%", $0.value) }
                vitalSection(kind: "waist", title: "Waist") { String(format: "%.0f cm", $0.value) }
                vitalSection(kind: "vo2max", title: "Cardio Fitness (VO₂max)") {
                    String(format: "%.1f mL/kg·min", $0.value)
                }
                vitalSection(kind: "oxygen", title: "Blood Oxygen") { String(format: "%.0f%%", $0.value) }
            }
            .navigationTitle("Body")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.brandTeal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveBirthdate() } }.disabled(saving)
                }
            }
            .onAppear { if heightUnit == "in" { heightUnit = "ftin" } } // migrate old total-inches
            .task { await load() }
        }
    }

    // MARK: BMI

    @ViewBuilder private func bmiRow(_ value: Double) -> some View {
        let (label, tint) = bmiCategory(value)
        HStack {
            Text(String(format: "%.1f", value))
                .font(.title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(tint)
            Spacer()
            Text(label).font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(0.15)))
        }
    }

    private func bmiCategory(_ v: Double) -> (String, Color) {
        switch v {
        case ..<18.5: return ("Underweight", .statusLow)
        case 18.5..<25: return ("Healthy", .statusInRange)
        case 25..<30: return ("Overweight", .statusHigh)
        default: return ("Obese", .statusHigh)
        }
    }

    // MARK: weight / height sections

    @ViewBuilder
    private func metricSection(kind: String, title: String, unit: Binding<String>, units: [(String, String)]) -> some View {
        let items = measurements.filter { $0.kind == kind }
        Section {
            if let latest = items.first {
                HStack {
                    Text(displayString(latest.value, kind: kind, unit: unit.wrappedValue))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Text(LabDate.pretty(latest.measuredOn) ?? latest.measuredOn)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if items.count >= 2 {
                trend(items, kind: kind, unit: unit.wrappedValue)
            }
            Picker("Unit", selection: unit) {
                ForEach(units, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            if kind == "height" && unit.wrappedValue == "ftin" {
                FeetInchesInput { cm in await add(kind: kind, canonical: cm) }
            } else {
                NumberInput(unitLabel: unit.wrappedValue) { value in
                    await add(kind: kind, canonical: toCanonical(value, kind: kind, unit: unit.wrappedValue))
                }
            }
            ForEach(expanded.contains(kind) ? items : Array(items.prefix(10))) { m in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LabDate.pretty(m.measuredOn) ?? m.measuredOn)
                        Text(Self.prettySource(m.source))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(displayString(m.value, kind: kind, unit: unit.wrappedValue))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
                .swipeActions {
                    Button("Delete", role: .destructive) { Task { await remove(m) } }
                }
            }
            if items.count > 10 {
                Button(expanded.contains(kind) ? "Show less" : "Show all \(items.count) readings") {
                    if expanded.contains(kind) { expanded.remove(kind) } else { expanded.insert(kind) }
                }
                .font(.callout)
            }
        } header: {
            Text(title)
        }
    }

    @ViewBuilder private func trend(_ items: [BodyMeasurement], kind: String, unit: String) -> some View {
        Chart(items) { m in
            LineMark(x: .value("Date", m.measuredOn), y: .value("Value", displayNumeric(m.value, kind: kind, unit: unit)))
                .foregroundStyle(Color.brandTeal)
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            // Dots crowd the line once there are many readings — show them only
            // when the series is sparse enough to be readable.
            if items.count <= 40 {
                PointMark(x: .value("Date", m.measuredOn), y: .value("Value", displayNumeric(m.value, kind: kind, unit: unit)))
                    .foregroundStyle(Color.brandTeal)
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 120)
        .padding(.vertical, 4)
    }

}

// Conversions + actions live in an extension to keep the main view body small.
extension BodyView {
    // MARK: vital sections (read-only; appear once imported)

    /// A read-only metric section (latest + trend + history), rendered only when
    /// the kind has data. Used for the Apple Health vitals.
    @ViewBuilder
    fileprivate func vitalSection(kind: String, title: String,
                                  format: @escaping (BodyMeasurement) -> String) -> some View {
        let items = measurements.filter { $0.kind == kind }
        if !items.isEmpty {
            Section(title) {
                if let latest = items.first {
                    HStack {
                        Text(format(latest)).font(.title3.weight(.semibold)).monospacedDigit()
                        Spacer()
                        Text(LabDate.pretty(latest.measuredOn) ?? latest.measuredOn)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if items.count >= 2 { vitalChart(items) }
                ForEach(expanded.contains(kind) ? items : Array(items.prefix(10))) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(LabDate.pretty(m.measuredOn) ?? m.measuredOn)
                            Text(Self.prettySource(m.source)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(format(m)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .swipeActions { Button("Delete", role: .destructive) { Task { await remove(m) } } }
                }
                if items.count > 10 {
                    Button(expanded.contains(kind) ? "Show less" : "Show all \(items.count) readings") {
                        if expanded.contains(kind) { expanded.remove(kind) } else { expanded.insert(kind) }
                    }
                    .font(.callout)
                }
            }
        }
    }

    @ViewBuilder
    private func vitalChart(_ items: [BodyMeasurement]) -> some View {
        Chart(items) { m in
            LineMark(x: .value("Date", m.measuredOn), y: .value("Value", m.value))
                .foregroundStyle(Color.brandTeal)
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            if items.count <= 40 {
                PointMark(x: .value("Date", m.measuredOn), y: .value("Value", m.value))
                    .foregroundStyle(Color.brandTeal)
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 120)
        .padding(.vertical, 4)
    }

    /// "120/80 mmHg" when diastolic is present.
    static func bp(_ m: BodyMeasurement) -> String {
        if let dia = m.value2 { return String(format: "%.0f/%.0f mmHg", m.value, dia) }
        return String(format: "%.0f mmHg", m.value)
    }

    // MARK: unit conversion

    /// Full display string for a canonical value in the chosen unit.
    private func displayString(_ canonical: Double, kind: String, unit: String) -> String {
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
    private func displayNumeric(_ canonical: Double, kind: String, unit: String) -> Double {
        switch (kind, unit) {
        case ("weight", "lb"): return canonical * 2.20462
        case ("height", "ftin"), ("height", "in"): return canonical / 2.54 // inches
        default: return canonical
        }
    }

    /// Convert a single-field display value back to canonical (kg / cm).
    private func toCanonical(_ display: Double, kind: String, unit: String) -> Double {
        switch (kind, unit) {
        case ("weight", "lb"): return display / 2.20462
        default: return display // weight kg, height cm
        }
    }

    // MARK: actions

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            // Re-fetch the profile so a just-saved birthdate shows on reopen — the
            // profile passed in from the dashboard can be stale after an edit.
            let current = try await store.api.profiles().first { $0.id == profile.id }
            profileName = current?.name ?? profile.name
            if let dobStr = current?.dateOfBirth, let parsed = Self.parse(dobStr) {
                dob = parsed
                hasDOB = true
            } else {
                hasDOB = false
            }
            measurements = try await store.api.bodyMeasurements(profileId: profile.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func add(kind: String, canonical: Double) async {
        do {
            _ = try await store.api.addBody(profileId: profile.id, kind: kind, value: canonical, measuredOn: nil)
            measurements = try await store.api.bodyMeasurements(profileId: profile.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importFromHealth() async {
        importing = true
        defer { importing = false }
        do {
            let importer = HealthImporter()
            try await importer.requestAuthorization()
            for kind in importer.scalarKinds {
                for sample in try await importer.samples(kind: kind) {
                    _ = try await store.api.addBody(
                        profileId: profile.id, kind: kind, value: sample.value, value2: sample.value2,
                        measuredOn: Self.format(sample.date), source: "apple_health", externalId: sample.uuid)
                }
            }
            for sample in try await importer.bloodPressureSamples() {
                _ = try await store.api.addBody(
                    profileId: profile.id, kind: "blood_pressure", value: sample.value, value2: sample.value2,
                    measuredOn: Self.format(sample.date), source: "apple_health", externalId: sample.uuid)
            }
            measurements = try await store.api.bodyMeasurements(profileId: profile.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ m: BodyMeasurement) async {
        do {
            try await store.api.deleteBody(profileId: profile.id, measurementId: m.id)
            measurements.removeAll { $0.id == m.id }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveBirthdate() async {
        saving = true
        defer { saving = false }
        do {
            _ = try await store.api.updateProfile(
                profileId: profile.id, name: profileName.isEmpty ? profile.name : profileName,
                dateOfBirth: hasDOB ? Self.format(dob) : nil)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func prettySource(_ s: String) -> String {
        switch s {
        case "apple_health": return "Apple Health"
        case "manual": return "Manual entry"
        default: return s.capitalized
        }
    }

    private static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .gmt
        return f.date(from: s)
    }

    private static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .gmt
        return f.string(from: d)
    }
}
