import SwiftUI

/// Server configuration. The base URL points the app at a lab-tracker backend;
/// a token is only needed for an auth-enabled (prod) server. Local dev runs with
/// AUTH_DISABLED, so the token can be left blank.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var token = ""

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
                    SecureField("Bearer token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Access token (optional)")
                } footer: {
                    Text("Only needed for a server with OIDC auth enabled. Leave blank for a local AUTH_DISABLED backend.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.serverURL = url.trimmingCharacters(in: .whitespaces)
                        store.token = token.isEmpty ? nil : token
                        dismiss()
                    }
                }
            }
            .onAppear {
                url = store.serverURL
                token = store.token ?? ""
            }
        }
    }
}
