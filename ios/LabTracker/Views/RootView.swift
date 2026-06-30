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
    @State private var showBody = false

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
                } else if canReauth {
                    // A 401 means we're not signed in (fresh from onboarding, or
                    // an expired/revoked session). That's not an error — prompt to
                    // sign in, not a scary failure with a raw status body.
                    ContentUnavailableView {
                        Label("Sign in", systemImage: "person.crop.circle")
                    } description: {
                        Text("Sign in to your Lab Tracker server to view your results.")
                    } actions: {
                        Button("Sign in") { Task { await reSignIn() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(signingIn)
                        Button("Settings") { showSettings = true }
                    }
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn’t load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
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
                    if selected != nil {
                        Button { showBody = true } label: {
                            Image(systemName: "figure")
                        }
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
            .sheet(isPresented: $showBody) {
                if let selected {
                    BodyView(profile: selected)
                }
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
