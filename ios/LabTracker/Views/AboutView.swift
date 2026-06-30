import SwiftUI
import UIKit

/// Diagnostics: app build, the server it's talking to and that server's API
/// version (fetched live from /health), account state, and device info.
struct AboutView: View {
    @Environment(Store.self) private var store

    @State private var apiVersion: String?
    @State private var apiReachable = true
    @State private var loading = false

    private var appVersion: String { Self.info("CFBundleShortVersionString") ?? "—" }
    private var appBuild: String { Self.info("CFBundleVersion") ?? "—" }
    private var bundleID: String { Bundle.main.bundleIdentifier ?? "—" }

    var body: some View {
        Form {
            Section("App") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: appBuild)
                LabeledContent("Bundle ID", value: bundleID)
            }

            Section("Server") {
                LabeledContent("URL", value: store.serverURL)
                LabeledContent("API version") {
                    if loading {
                        ProgressView()
                    } else if let apiVersion {
                        Text(apiVersion)
                    } else {
                        Text(apiReachable ? "—" : "Unreachable")
                            .foregroundStyle(apiReachable ? Color.secondary : Color.statusHigh)
                    }
                }
                LabeledContent("Account") {
                    Text(store.auth.isSignedIn ? "Signed in" : "Not signed in")
                        .foregroundStyle(store.auth.isSignedIn ? Color.statusInRange : Color.secondary)
                }
            }

            Section("Device") {
                LabeledContent("System", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                LabeledContent("Model", value: UIDevice.current.model)
            }

            Section {
                if let url = URL(string: "https://github.com/Seklfreak/lab-tracker") {
                    Link(destination: url) {
                        Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHealth() }
        .refreshable { await loadHealth() }
    }

    private func loadHealth() async {
        loading = true
        defer { loading = false }
        do {
            apiVersion = try await store.api.health().version
            apiReachable = true
        } catch {
            apiVersion = nil
            apiReachable = false
        }
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
