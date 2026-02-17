import SwiftUI

struct OnboardingScreen: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Cyberspace")
                .font(.largeTitle.weight(.bold))

            Text("Cyberspace helps you prove identity, delegate access safely, and verify what happened.")
                .foregroundStyle(.secondary)

            GroupBox("Core Ideas (Plain Language)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Identity key: your cryptographic passport.")
                    Text("2. Capability certificate: a signed keycard with specific permissions.")
                    Text("3. Audit trail: a tamper-evident flight recorder for decisions and actions.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Why Journalists Use This") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You can grant a fixer upload-only rights to one story folder without giving full archive access.")
                    Text("You can prove a source package came from a trusted desk key before publication.")
                    Text("You can show editors and legal exactly who approved access, and when.")
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
