import SwiftUI

struct RealmScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var realmName = "library-realm"
    @State private var host = "127.0.0.1"
    @State private var port = 7780

    private var isInviteJoinStep: Bool {
        appState.selectedRoute == .inviteJoinRealm
    }

    private var stepTitle: String {
        isInviteJoinStep ? "Step 6: Invite & Join Realm" : "Step 4: Create Initial Realm"
    }

    private var taskLines: [String] {
        if isInviteJoinStep {
            return [
                "Use invite parameters from the realm operator and join as the target node identity.",
                "Repeat join for nodes 2-5 and verify member count reaches expected value.",
                "Record join success/failure in audit before moving to access testing."
            ]
        }
        return [
            "Bootstrap the first realm endpoint using Node 1 (root-admin).",
            "Set canonical realm name, host, and port for all participant nodes.",
            "Confirm status is stable before issuing invitations or certificates."
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(stepTitle)
                .font(.title2.weight(.semibold))

            GroupBox("Task Stub") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(taskLines, id: \.self) { line in
                        Text(line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Trust Domain (Realm)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A realm is a trust domain: a shared policy boundary for identities, permissions, and data.")
                    Text("Analogy: a secure international bureau where each desk has explicit, signed access rules.")
                    Text("Journalism example: EU, LATAM, and MENA desks can collaborate without sharing full global vault rights.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Status: \(appState.realmStatusValue.status)")
                    Text("Node: \(appState.realmStatusValue.nodeName)")
                    Text("Policy: \(appState.realmStatusValue.policy)")
                    Text("Members: \(appState.realmStatusValue.memberCount)")
                    Button("Refresh status") {
                        Task { await appState.refreshRealmStatus() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Join Realm") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Realm name", text: $realmName)
                    TextField("Host", text: $host)
                    HStack {
                        Text("Port")
                        Spacer()
                        Stepper(value: $port, in: 1...65535) {
                            Text("\(port)")
                        }
                        .frame(width: 180)
                    }
                    Button("Join") {
                        Task {
                            await appState.joinRealm(name: realmName, host: host, port: port)
                            await appState.refreshRealmStatus()
                        }
                    }
                }
            }

            if let result = appState.realmJoinResult {
                Text("Join result: \(result.joined ? "success" : "failed") - \(result.message)")
                    .font(.caption)
                    .foregroundStyle(result.joined ? .green : .red)
            }

            Spacer()
        }
        .padding()
        .task {
            await appState.refreshRealmStatus()
        }
    }
}
