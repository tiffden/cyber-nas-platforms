import SwiftUI

struct KeyringScreen: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Keyring")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") {
                    Task { await appState.loadBootstrapData() }
                }
            }

            if appState.keys.isEmpty {
                if #available(macOS 14.0, *) {
                    ContentUnavailableView("No keys", systemImage: "key.horizontal")
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "key.horizontal")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("No keys")
                            .font(.headline)
                        Text("Import or generate a key to populate your keyring.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
