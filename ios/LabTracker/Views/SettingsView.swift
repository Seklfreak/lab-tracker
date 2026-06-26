import SwiftUI

/// Server + auth configuration. Sign in via OIDC (Authorization Code + PKCE)
/// against a provider, or paste a token, or — for a local AUTH_DISABLED backend
/// — leave auth blank.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var issuer = ""
    @State private var clientID = ""
    @State private var token = ""
    @State private var signingIn = false
    @State private var authError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("https://labs.example.com", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section {
                    if store.auth.isSignedIn {
                        Label("Signed in", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Sign out", role: .destructive) { store.auth.signOut() }
                    } else {
                        TextField("Issuer URL", text: $issuer)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        TextField("Client ID", text: $clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task { await signIn() }
                        } label: {
                            if signingIn {
                                ProgressView()
                            } else {
                                Text("Sign in")
                            }
                        }
                        .disabled(signingIn || issuer.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let authError {
                        Text(authError).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Sign in (OIDC)")
                } footer: {
                    Text("Authenticate against your OpenID provider via PKCE. Not needed for a local AUTH_DISABLED server.")
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
                issuer = store.oidcIssuer
                clientID = store.oidcClientID
                token = store.token ?? ""
            }
        }
    }

    private func save() {
        store.serverURL = url.trimmingCharacters(in: .whitespaces)
        store.oidcIssuer = issuer.trimmingCharacters(in: .whitespaces)
        store.oidcClientID = clientID.trimmingCharacters(in: .whitespaces)
        store.token = token.isEmpty ? nil : token
        dismiss()
    }

    private func signIn() async {
        // Persist config first so the auth session uses the current issuer/client.
        store.oidcIssuer = issuer.trimmingCharacters(in: .whitespaces)
        store.oidcClientID = clientID.trimmingCharacters(in: .whitespaces)
        signingIn = true
        authError = nil
        defer { signingIn = false }
        do {
            try await store.auth.signIn()
            dismiss()
        } catch {
            authError = error.localizedDescription
        }
    }
}
