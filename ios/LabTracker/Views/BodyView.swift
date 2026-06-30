import SwiftUI
import Charts

/// Per-profile body metrics: edit birthdate, track weight & height over time,
/// and see BMI. Weight/height are stored canonically (kg, cm); this view shows
/// and accepts them in the user's preferred unit.
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
    @State private var error: String?

    @AppStorage("weightUnit") private var weightUnit = "kg" // kg | lb
    @AppStorage("heightUnit") private var heightUnit = "cm" // cm | in

    private var weights: [BodyMeasurement] { measurements.filter { $0.kind == "weight" } }
    private var heights: [BodyMeasurement] { measurements.filter { $0.kind == "height" } }
    private var latestWeightKg: Double? { weights.first?.value }
    private var latestHeightCm: Double? { heights.first?.value }
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
                metricSection(kind: "weight", title: "Weight", unit: $weightUnit, units: ["kg", "lb"])
                metricSection(kind: "height", title: "Height", unit: $heightUnit, units: ["cm", "in"])
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
    private func metricSection(kind: String, title: String, unit: Binding<String>, units: [String]) -> some View {
        let items = measurements.filter { $0.kind == kind }
        Section {
            if let latest = items.first {
                HStack {
                    Text(format(latest.value, kind: kind, unit: unit.wrappedValue))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    Text(unit.wrappedValue).foregroundStyle(.secondary)
                    Spacer()
                    Text(LabDate.pretty(latest.measuredOn) ?? latest.measuredOn)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if items.count >= 2 {
                trend(items, kind: kind, unit: unit.wrappedValue)
            }
            AddRow(unit: unit, units: units) { value in
                await add(kind: kind, displayValue: value, unit: unit.wrappedValue)
            }
            ForEach(items) { m in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LabDate.pretty(m.measuredOn) ?? m.measuredOn)
                        Text(Self.prettySource(m.source))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(format(m.value, kind: kind, unit: unit.wrappedValue) + " " + unit.wrappedValue)
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
                .swipeActions {
                    Button("Delete", role: .destructive) { Task { await remove(m) } }
                }
            }
        } header: {
            Text(title)
        }
    }

    @ViewBuilder private func trend(_ items: [BodyMeasurement], kind: String, unit: String) -> some View {
        Chart(items) { m in
            LineMark(x: .value("Date", m.measuredOn), y: .value(unit, displayValue(m.value, kind: kind, unit: unit)))
                .foregroundStyle(Color.brandTeal)
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 3))
            PointMark(x: .value("Date", m.measuredOn), y: .value(unit, displayValue(m.value, kind: kind, unit: unit)))
                .foregroundStyle(Color.brandTeal)
        }
        .chartXAxis(.hidden)
        .frame(height: 120)
        .padding(.vertical, 4)
    }

    // MARK: unit conversion

    private func displayValue(_ canonical: Double, kind: String, unit: String) -> Double {
        switch (kind, unit) {
        case ("weight", "lb"): return canonical * 2.20462
        case ("height", "in"): return canonical / 2.54
        default: return canonical
        }
    }

    private func canonicalValue(_ display: Double, kind: String, unit: String) -> Double {
        switch (kind, unit) {
        case ("weight", "lb"): return display / 2.20462
        case ("height", "in"): return display * 2.54
        default: return display
        }
    }

    private func format(_ canonical: Double, kind: String, unit: String) -> String {
        String(format: "%.1f", displayValue(canonical, kind: kind, unit: unit))
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

    private func add(kind: String, displayValue value: Double, unit: String) async {
        do {
            let canonical = canonicalValue(value, kind: kind, unit: unit)
            _ = try await store.api.addBody(profileId: profile.id, kind: kind, value: canonical, measuredOn: nil)
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

    static func prettySource(_ s: String?) -> String {
        switch s ?? "manual" {
        case "apple_health": return "Apple Health"
        case "manual": return "Manual entry"
        default: return (s ?? "manual").capitalized
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

/// Inline "add a reading" row: a number field, a unit picker, and an Add button.
private struct AddRow: View {
    @Binding var unit: String
    let units: [String]
    let onAdd: (Double) async -> Void

    @State private var text = ""
    @State private var busy = false

    var body: some View {
        HStack {
            TextField("Add reading", text: $text)
                .keyboardType(.decimalPad)
            Picker("", selection: $unit) {
                ForEach(units, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
            Button {
                guard let v = Double(text), v > 0 else { return }
                busy = true
                Task {
                    await onAdd(v)
                    text = ""
                    busy = false
                }
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .disabled(busy || Double(text) == nil)
        }
    }
}
