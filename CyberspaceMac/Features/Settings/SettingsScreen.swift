import SwiftUI

struct SettingsScreen: View {
    @State private var enableNetworkFeatures = false
    @State private var verboseAuditView = false

    var body: some View {
        Form {
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
