import SwiftUI

/// Server + auth configuration. The server URL is live-tested against /health as
/// you type; Save persists it. Auth is OIDC (Authorization Code + PKCE), or
/// nothing for a local AUTH_DISABLED backend.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var check: ServerCheck = .idle
    @State private var signingIn = false
    @State private var authError: String?
    @State private var lockUnavailable = false

    private var canSave: Bool {
        check.isOK || url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("labs.example.com", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    ServerStatusLabel(check: check)
                } header: {
                    Text("Server")
                } footer: {
                    Text("The base URL of your Lab Tracker server. The app reads its OIDC settings from there when you sign in.")
                }

                Section {
                    if store.auth.isSignedIn {
                        Label("Signed in", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Color.statusInRange)
                        Button("Sign out", role: .destructive) { store.auth.signOut() }
                    } else {
                        Button {
                            Task { await signIn() }
                        } label: {
                            if signingIn {
                                ProgressView()
                            } else {
                                Text("Sign in")
                            }
                        }
                        .disabled(signingIn || !check.isOK)
                    }
                    if let authError {
                        Text(authError).font(.caption).foregroundStyle(Color.statusHigh)
                    }
                } header: {
                    Text("Sign in")
                } footer: {
                    Text("Authenticate against the server's OpenID provider. Not needed for a local AUTH_DISABLED server.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { store.biometricLockEnabled },
                        set: { on in
                            if on && !Biometrics.isAvailable { lockUnavailable = true } else { store.biometricLockEnabled = on }
                        }
                    )) {
                        Label("Require \(Biometrics.name)", systemImage: "lock.fill")
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Ask for \(Biometrics.name) when the app opens or returns from the background.")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .alert("Can’t enable lock", isPresented: $lockUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Set up Face ID, Touch ID, or a device passcode in iOS Settings first.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onAppear { url = store.serverURL }
            .task(id: url) { await validate() }
        }
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

    private func save() {
        store.serverURL = ServerProbe.normalize(url) ?? url.trimmingCharacters(in: .whitespaces)
        dismiss()
    }

    private func signIn() async {
        // Persist the (normalized) server URL first so discovery + the flow use it.
        store.serverURL = ServerProbe.normalize(url) ?? url.trimmingCharacters(in: .whitespaces)
        signingIn = true
        authError = nil
        defer { signingIn = false }
        do {
            try await store.auth.signIn(serverURL: store.serverURL)
            dismiss()
        } catch {
            authError = error.localizedDescription
        }
    }
}
