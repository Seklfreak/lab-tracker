import SwiftUI

/// Loads profiles, lets you pick one, and shows its dashboard. A gear opens
/// server settings.
struct RootView: View {
    @Environment(Store.self) private var store

    @State private var profiles: [Profile] = []
    @State private var loading = false
    @State private var error: String?
    @State private var canReauth = false
    @State private var signingIn = false
    @State private var showSettings = false

    private var selected: Profile? {
        profiles.first { $0.id == store.selectedProfileId } ?? profiles.first
    }

    var body: some View {
        if store.serverURL.isEmpty {
            OnboardingView()
        } else {
            navigationContent
        }
    }

    private var navigationContent: some View {
        NavigationStack {
            Group {
                if loading && profiles.isEmpty {
                    ProgressView("Loading…")
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn’t load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        // An expired/revoked token (or a wiped session) shows up
                        // as a 401 — let the user re-auth right here instead of
                        // hunting through Settings for sign out + sign in.
                        if canReauth {
                            Button("Sign in") { Task { await reSignIn() } }
                                .disabled(signingIn)
                        }
                        Button("Retry") { Task { await load() } }
                        Button("Settings") { showSettings = true }
                    }
                } else if let selected {
                    DashboardView(profile: selected)
                } else {
                    ContentUnavailableView {
                        Label("No profiles", systemImage: "person.crop.circle.badge.questionmark")
                    } description: {
                        Text("This account has no profiles, or the server URL is wrong.")
                    } actions: {
                        Button("Settings") { showSettings = true }
                    }
                }
            }
            .navigationTitle("Lab Tracker")
            .tint(.brandTeal)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if profiles.count > 1, let selected {
                        Picker("Profile", selection: Binding(
                            get: { selected.id },
                            set: { store.selectedProfileId = $0 }
                        )) {
                            ForEach(profiles) { p in Text(p.name).tag(p.id) }
                        }
                        .pickerStyle(.menu)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task(id: store.serverURL) { await load() }
            .onChange(of: store.auth.isSignedIn) { _, _ in Task { await load() } }
            .refreshable { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            profiles = try await store.api.profiles()
            error = nil
            canReauth = false
            if store.selectedProfileId == nil { store.selectedProfileId = profiles.first?.id }
        } catch {
            self.error = error.localizedDescription
            canReauth = (error as? APIError)?.isUnauthorized ?? false
        }
    }

    /// Re-run the OIDC sign-in flow to mint a fresh token pair. Works whether the
    /// old session was expired, revoked, or wiped — no sign-out needed first.
    private func reSignIn() async {
        signingIn = true
        defer { signingIn = false }
        do {
            try await store.auth.signIn(serverURL: store.serverURL)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
