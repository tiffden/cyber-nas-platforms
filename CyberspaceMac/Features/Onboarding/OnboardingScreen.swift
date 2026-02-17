import SwiftUI

struct OnboardingScreen: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Cyberspace")
                .font(.largeTitle.weight(.bold))

            Text("This app helps you manage cryptographic identity, authorization, and audit trails.")
                .foregroundStyle(.secondary)

            GroupBox("Trust Model (Simple)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Principals are cryptographic identities.")
                    Text("2. Certificates delegate capabilities.")
                    Text("3. Audit logs are tamper-evident.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Live Status") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("System: \(appState.systemStatus.status)")
                    Text("Uptime: \(appState.systemStatus.uptime)")
                    Text("Keys loaded: \(appState.keys.count)")
                    if let err = appState.lastErrorMessage {
                        Text("Last error: \(err)")
                            .foregroundStyle(.red)
                    }
                    Button("Refresh") {
                        Task { await appState.loadBootstrapData() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await appState.loadBootstrapDataIfNeeded()
        }
    }
}
