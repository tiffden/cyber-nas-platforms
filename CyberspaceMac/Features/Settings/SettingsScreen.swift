import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var enableNetworkFeatures = false
    @State private var verboseAuditView = false

    var body: some View {
        Form {
            Section("Audience") {
                Picker("UI mode", selection: $appState.audienceMode) {
                    ForEach(AudienceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("Builder mode exposes Local Harness controls and testbed orchestration tools.")
                    .foregroundStyle(.secondary)
            }

            Section("Security Defaults") {
                Toggle("Enable federation/network features", isOn: $enableNetworkFeatures)
                Toggle("Show verbose audit details", isOn: $verboseAuditView)
            }

            Section("Notes") {
                Text("Keep network features disabled unless explicitly needed.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 520)
    }
}
