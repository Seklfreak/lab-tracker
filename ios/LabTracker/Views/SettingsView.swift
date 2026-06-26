import SwiftUI

/// Server + auth configuration. Sign in via OIDC (Authorization Code + PKCE)
/// against a provider, or paste a token, or — for a local AUTH_DISABLED backend
/// — leave auth blank.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var token = ""
    @State private var signingIn = false
    @State private var authError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://labs.example.com", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Server")
                } footer: {
                    Text("Just the base URL of your lab-tracker server. The app reads its OIDC settings from there when you sign in.")
                }

                Section {
                    if store.auth.isSignedIn {
                        Label("Signed in", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
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
                        .disabled(signingIn || url.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let authError {
                        Text(authError).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Sign in")
                } footer: {
                    Text("Authenticate against the server's OpenID provider via PKCE. Not needed for a local AUTH_DISABLED server.")
                }

                Section {
                    SecureField("Bearer token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Access token (manual)")
                } footer: {
                    Text("An alternative to signing in: paste an access token directly.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                url = store.serverURL
                token = store.token ?? ""
            }
        }
    }

    private func save() {
        store.serverURL = url.trimmingCharacters(in: .whitespaces)
        store.token = token.isEmpty ? nil : token
        dismiss()
    }

    private func signIn() async {
        // Persist the server URL first so discovery + the flow use it.
        store.serverURL = url.trimmingCharacters(in: .whitespaces)
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
