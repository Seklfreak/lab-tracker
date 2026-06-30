import SwiftUI

/// Single number field + an Add button (for weight, and height in cm).
struct NumberInput: View {
    let unitLabel: String
    let onAdd: (Double) async -> Void

    @State private var text = ""
    @State private var busy = false

    var body: some View {
        HStack {
            TextField("Add reading", text: $text)
                .keyboardType(.decimalPad)
            Text(unitLabel).foregroundStyle(.secondary)
            Spacer()
            Button(action: submit) { Image(systemName: "plus.circle.fill") }
                .disabled(busy || Double(text) == nil)
        }
    }

    private func submit() {
        guard let v = Double(text), v > 0 else { return }
        busy = true
        Task {
            await onAdd(v)
            text = ""
            busy = false
        }
    }
}

/// Feet + inches fields for height; passes the canonical centimetres to `onAdd`.
struct FeetInchesInput: View {
    let onAdd: (Double) async -> Void

    @State private var feet = ""
    @State private var inches = ""
    @State private var busy = false

    var body: some View {
        HStack(spacing: 6) {
            TextField("ft", text: $feet).keyboardType(.numberPad).frame(width: 44)
            Text("′").foregroundStyle(.secondary)
            TextField("in", text: $inches).keyboardType(.numberPad).frame(width: 44)
            Text("″").foregroundStyle(.secondary)
            Spacer()
            Button(action: submit) { Image(systemName: "plus.circle.fill") }
                .disabled(busy || (feet.isEmpty && inches.isEmpty))
        }
    }

    private func submit() {
        let totalInches = (Double(feet) ?? 0) * 12 + (Double(inches) ?? 0)
        guard totalInches > 0 else { return }
        busy = true
        Task {
            await onAdd(totalInches * 2.54)
            feet = ""
            inches = ""
            busy = false
        }
    }
}
