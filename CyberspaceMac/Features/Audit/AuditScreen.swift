import SwiftUI

struct AuditScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var filter = ""
    @State private var limit = 50
    @State private var vaultPath = "/library/demo.txt"
    @State private var vaultData = Data("hello-from-ui".utf8).base64EncodedString()
    @State private var commitMessage = "UI commit"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 7: Test Access")
                .font(.title2.weight(.semibold))

            GroupBox("Task Stub") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Run representative actions for each node role and confirm expected allow/deny behavior.")
                    Text("Use vault.put/get/commit as practical permission checks.")
                    Text("Query audit entries to prove each decision and action is recorded.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Audit as Flight Recorder") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Audit entries are your cryptographic chain-of-custody log.")
                    Text("Like a flight recorder, it helps reconstruct what changed, by whom, and in what order.")
                    Text("Journalism example: prove an unpublished source file was never modified after legal review.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Query") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Filter", text: $filter)
                    Stepper("Limit: \(limit)", value: $limit, in: 1...200)
                    Button("Run query") {
                        Task { await appState.queryAudit(filter: filter, limit: limit) }
                    }
                }
            }

            GroupBox("Vault Flow") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Path", text: $vaultPath)
                    TextField("Data (base64)", text: $vaultData)
                    HStack {
                        Button("vault.put") {
                            Task { await appState.vaultPut(path: vaultPath, dataBase64: vaultData) }
                        }
                        Button("vault.get") {
                            Task { await appState.vaultGet(path: vaultPath) }
                        }
                    }
                    TextField("Commit message", text: $commitMessage)
                    Button("vault.commit") {
                        Task { await appState.vaultCommit(message: commitMessage) }
                    }
                }
            }

            List(appState.auditEntries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.actor) • \(entry.action)")
                        .font(.headline)
                    Text(entry.timestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.context)
                        .font(.caption)
                }
            }

            if let commit = appState.vaultCommitResult {
                Text("Last commit ID: \(commit.commitID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
