import SwiftUI

struct KeyringScreen: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Step 3: Generate Identity Keys")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") {
                    Task { await appState.loadBootstrapData() }
                }
            }

            GroupBox("Task Stub") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create one identity keypair per node: root-admin, editor, reporter, factcheck, legal.")
                    Text("Confirm each key has a unique fingerprint.")
                    Text("Do not continue to certificates until all required principals exist.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Why Keys Matter") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Think of each key as a diplomatic passport for a person, newsroom, or device.")
                    Text("Whoever controls that private key can sign approvals and delegation certificates.")
                    Text("For field reporting, separate keys per desk/role reduce blast radius if one device is seized.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if appState.keys.isEmpty {
                ContentUnavailableView("No keys", systemImage: "key.horizontal")
            } else {
                List(appState.keys) { key in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(key.name)
                            .font(.headline)
                        Text("\(key.algorithm)  •  \(key.fingerprint)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
    }
}
