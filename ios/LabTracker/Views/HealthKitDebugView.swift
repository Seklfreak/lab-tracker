import SwiftUI

/// Diagnoses Apple Health imports: shows how many samples Lab Tracker can read
/// per type. Because iOS hides read-permission denials from apps, a count of 0
/// is the only signal that a type is unshared (or empty) — this screen surfaces
/// it directly so blood pressure (etc.) not importing is no longer a mystery.
struct HealthKitDebugView: View {
    @State private var diags: [HealthDiag] = []
    @State private var loading = false

    var body: some View {
        List {
            Section {
                LabeledContent("HealthKit available", value: HealthImporter.isAvailable ? "Yes" : "No")
            }

            Section {
                if loading && diags.isEmpty {
                    ProgressView()
                }
                ForEach(diags) { d in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.label)
                            if let latest = d.latest {
                                Text("latest \(latest)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(d.count)")
                            .monospacedDigit()
                            .foregroundStyle(d.count == 0 ? Color.statusHigh : Color.statusInRange)
                    }
                }
            } header: {
                Text("Readable samples")
            } footer: {
                Text("0 means the type isn’t shared with Lab Tracker (iOS hides read access from apps) "
                    + "or has no data. Turn it on in Settings → Health → Data Access & Devices → Lab Tracker.")
            }

            Section {
                Button("Request Health access") { Task { await request() } }
                Button("Open Settings") { openSettings() }
            }
        }
        .navigationTitle("HealthKit")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        diags = await HealthImporter().diagnostics()
    }

    private func request() async {
        try? await HealthImporter().requestAuthorization()
        await reload()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
