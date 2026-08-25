import SwiftUI

/// Server + auth configuration. The server URL is live-tested against /health as
/// you type; Save persists it. Auth is OIDC (Authorization Code + PKCE), or
/// nothing for a local AUTH_DISABLED backend.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(HealthSync.self) private var healthSync
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var check: ServerCheck = .idle
    @State private var signingIn = false
    @State private var authError: String?
    @State private var lockUnavailable = false
    @State private var profiles: [Profile] = []
    @State private var healthOn = false     // optimistic mirror of healthSync.isEnabled
    @State private var healthBusy = false
    @State private var healthError: String?

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
                        if !store.auth.hasRefreshToken {
                            let msg = "The server didn’t issue a refresh token, so you’ll be signed out when the "
                                + "session expires. Enable **offline_access** on the OIDC provider to stay signed in."
                            Label(msg, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(Color.statusWarn)
                        }
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

                if HealthSync.isAvailable {
                    healthSection
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
            .task {
                if HealthSync.isAvailable {
                    healthOn = healthSync.isEnabled
                    await loadProfiles()
                }
            }
        }
    }

    // Default sync target: a profile the user owns (the common case), else the
    // one currently selected on the dashboard.
    private var defaultTargetProfileId: String? {
        profiles.first(where: \.isOwner)?.id ?? store.selectedProfileId ?? profiles.first?.id
    }

    @ViewBuilder private var healthSection: some View {
        Section {
            Toggle(isOn: $healthOn) {
                Label("Sync from Apple Health", systemImage: "heart.fill")
            }
            .disabled(healthBusy)
            .onChange(of: healthOn) { _, on in
                if on != healthSync.isEnabled { Task { await toggleHealthSync(on) } }
            }

            if healthSync.isEnabled, !profiles.isEmpty {
                Picker("Save to profile", selection: Binding(
                    get: { healthSync.targetProfileId ?? defaultTargetProfileId },
                    set: { if let id = $0 { healthSync.setTargetProfile(id) } }
                )) {
                    ForEach(profiles) { Text($0.name).tag(Optional($0.id)) }
                }
            }

            if healthSync.isEnabled {
                healthStatusRows
            }

            if let healthError {
                Text(healthError).font(.caption).foregroundStyle(Color.statusHigh)
            } else if let syncError = healthSync.lastError, healthSync.isEnabled {
                Text(syncError).font(.caption).foregroundStyle(Color.statusWarn)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Automatically import new weight, vitals, and blood-pressure readings. "
                + "Syncs when you open the app; on a signed build with the background-delivery "
                + "entitlement it also syncs in the background.")
        }
    }

    @ViewBuilder private var healthStatusRows: some View {
        if let last = healthSync.lastSyncAt {
            LabeledContent("Last synced") {
                Text(Self.relative(last) + (healthSync.lastSyncNewCount > 0 ? " · \(healthSync.lastSyncNewCount) new" : ""))
            }
            .font(.caption)
        } else {
            Text("Waiting for first sync…").font(.caption).foregroundStyle(.secondary)
        }
        // Updates only when an observer fires with the app closed — the signal that
        // true background delivery is working.
        if let bg = healthSync.lastBackgroundSyncAt {
            LabeledContent("Last background sync", value: Self.relative(bg)).font(.caption)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func toggleHealthSync(_ on: Bool) async {
        healthBusy = true
        healthError = nil
        defer {
            healthBusy = false
            healthOn = healthSync.isEnabled   // reconcile the toggle with reality
        }
        if on {
            guard let target = healthSync.targetProfileId ?? defaultTargetProfileId else {
                healthError = "Add or select a profile first, then enable syncing."
                return
            }
            do {
                try await healthSync.enable(profileId: target)
            } catch {
                healthError = error.report()
            }
        } else {
            await healthSync.disable()
        }
    }

    private func loadProfiles() async {
        profiles = (try? await store.api.profiles()) ?? []
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
            authError = error.report()
        }
    }
}
