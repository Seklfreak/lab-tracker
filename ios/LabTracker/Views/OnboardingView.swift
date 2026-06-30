import SwiftUI

/// First run (no server configured yet): enter a server URL, which is live-tested
/// against /health, then Continue saves it and drops into the app.
struct OnboardingView: View {
    @Environment(Store.self) private var store

    @State private var url = ""
    @State private var check: ServerCheck = .idle
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Color.brandTeal)
                Text("Lab Tracker")
                    .font(.largeTitle.weight(.bold))
                Text("Connect to your Lab Tracker server to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("labs.example.com", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($focused)
                ServerStatusLabel(check: check)
                    .frame(minHeight: 18, alignment: .leading)
            }

            Spacer()

            Button {
                if let normalized = ServerProbe.normalize(url) { store.serverURL = normalized }
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!check.isOK)
        }
        .padding(28)
        .tint(.brandTeal)
        .task(id: url) { await validate() }
        .onAppear { focused = true }
    }

    private func validate() async {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { check = .idle; return }
        try? await Task.sleep(for: .milliseconds(600))
        if Task.isCancelled { return }
        check = .checking
        let result = await ServerProbe.validate(trimmed)
        if Task.isCancelled { return }
        check = result
    }
}
