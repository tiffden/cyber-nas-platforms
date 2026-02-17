import SwiftUI

struct CurrentStatusScreen: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 2: Current Status")
                .font(.title2.weight(.semibold))

            GroupBox("Task Stub") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal: confirm local node is healthy before provisioning identities.")
                    Text("Check system status, key count, and realm state.")
                    Text("If status is not healthy, stop and fix environment paths first.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("System") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("System: \(appState.systemStatus.status)")
                    Text("Uptime: \(appState.systemStatus.uptime)")
                    Text("Keys loaded: \(appState.keys.count)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Realm") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status: \(appState.realmStatusValue.status)")
                    Text("Node: \(appState.realmStatusValue.nodeName)")
                    Text("Policy: \(appState.realmStatusValue.policy)")
                    Text("Members: \(appState.realmStatusValue.memberCount)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Latest Results") {
                VStack(alignment: .leading, spacing: 8) {
                    if let cert = appState.certificateVerifyResult {
                        Text("Certificate verify: \(cert.valid ? "valid" : "invalid") (\(cert.reason))")
                    }
                    if let authz = appState.authzVerifyResult {
                        Text("Authz chain: \(authz.allowed ? "allowed" : "denied") (\(authz.reason))")
                    }
                    if let commit = appState.vaultCommitResult {
                        Text("Vault commit: \(commit.commitID)")
                    }
                    if let join = appState.realmJoinResult {
                        Text("Realm join: \(join.joined ? "success" : "failed") (\(join.message))")
                    }
                    if appState.certificateVerifyResult == nil &&
                        appState.authzVerifyResult == nil &&
                        appState.vaultCommitResult == nil &&
                        appState.realmJoinResult == nil {
                        Text("No recent operation results yet.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let err = appState.lastErrorMessage {
                Text("Last error: \(err)")
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Refresh System") {
                    Task { await appState.loadBootstrapData() }
                }
                Button("Refresh Realm") {
                    Task { await appState.refreshRealmStatus() }
                }
            }

            Spacer()
        }
        .padding()
        .task {
            await appState.loadBootstrapDataIfNeeded()
        }
    }
}
