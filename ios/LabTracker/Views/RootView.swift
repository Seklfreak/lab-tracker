import SwiftUI

/// Loads profiles, lets you pick one, and shows its dashboard. A gear opens
/// server settings.
struct RootView: View {
    @Environment(Store.self) private var store

    @State private var profiles: [Profile] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showSettings = false

    private var selected: Profile? {
        profiles.first { $0.id == store.selectedProfileId } ?? profiles.first
    }

    var body: some View {
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
            .refreshable { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            profiles = try await store.api.profiles()
            error = nil
            if store.selectedProfileId == nil { store.selectedProfileId = profiles.first?.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
