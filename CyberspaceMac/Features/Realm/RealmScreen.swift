import SwiftUI

struct RealmScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var realmName = "library-realm"
    @State private var host = "127.0.0.1"
    @State private var port = 7780
    @State private var autoRefreshLog = false
    @State private var autoRefreshSeconds = 2

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

            GroupBox("Local Test Environment") {
                VStack(alignment: .leading, spacing: 10) {
                    // Node count drives local harness creation (isolated workdir/keydir/env per node).
                    HStack {
                        Text("Nodes")
                        Stepper(value: $appState.harnessNodeCount, in: 1...10) {
                            Text("\(appState.harnessNodeCount)")
                                .monospacedDigit()
                        }
                        .frame(width: 180)
                        Button("Create Test Environment") {
                            Task {
                                await appState.createRealmTestEnvironment(nodeCount: appState.harnessNodeCount)
                                await appState.refreshRealmHarnessNodes()
                            }
                        }
                        Button("Refresh Metadata") {
                            Task { await appState.refreshRealmHarnessNodes() }
                        }
                        Button("Launch All UIs (bg)") {
                            Task { await appState.launchRealmHarnessUIs(nodeCount: appState.harnessNodeCount) }
                        }
                        Button("Stop All UIs") {
                            Task { await appState.stopRealmHarnessUIs(nodeCount: appState.harnessNodeCount) }
                        }
                    }

                    if !appState.harnessLaunchOutput.isEmpty {
                        Text(appState.harnessLaunchOutput)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if appState.harnessNodes.isEmpty {
                        Text("No local harness nodes loaded yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Node").frame(width: 44, alignment: .leading)
                                Text("Status").frame(width: 100, alignment: .leading)
                                Text("Members").frame(width: 70, alignment: .leading)
                                Text("Host:Port").frame(width: 140, alignment: .leading)
                                Text("Workdir").frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                            ForEach(appState.harnessNodes) { node in
                                HStack {
                                    Text("#\(node.id)").frame(width: 44, alignment: .leading)
                                    Text(node.status).frame(width: 100, alignment: .leading)
                                    Text("\(node.memberCount)").frame(width: 70, alignment: .leading)
                                    Text("\(node.host):\(node.port)").frame(width: 140, alignment: .leading)
                                    Text(node.workdir).lineLimit(1).truncationMode(.middle)
                                }
                                .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }

                    HStack {
                        Text("Current Log")
                            .font(.headline)
                        if appState.harnessNodes.isEmpty {
                            Text("No nodes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Node", selection: $appState.selectedHarnessNodeID) {
                                ForEach(appState.harnessNodes) { node in
                                    Text("Node \(node.id)").tag(node.id)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 260)
                        }
                        Button("Refresh Log") {
                            Task { await appState.refreshRealmHarnessLog(nodeID: appState.selectedHarnessNodeID) }
                        }
                    }
                    HStack {
                        Toggle("Auto-refresh log", isOn: $autoRefreshLog)
                        Stepper(value: $autoRefreshSeconds, in: 1...10) {
                            Text("Every \(autoRefreshSeconds)s")
                                .monospacedDigit()
                        }
                        .frame(width: 150)
                    }

                    // Display a bounded tail from node<id>/logs/ui.log to keep refresh readable and fast.
                    ScrollView {
                        Text(appState.harnessCurrentLog.isEmpty ? "No log loaded." : appState.harnessCurrentLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(minHeight: 150, maxHeight: 220)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            await appState.refreshRealmHarnessNodes()
            if appState.selectedHarnessNodeID > 0 {
                await appState.refreshRealmHarnessLog(nodeID: appState.selectedHarnessNodeID)
            }
        }
        .onChange(of: appState.selectedHarnessNodeID) { _, newID in
            Task { await appState.refreshRealmHarnessLog(nodeID: newID) }
        }
        .task(id: "\(autoRefreshLog)-\(autoRefreshSeconds)-\(appState.selectedHarnessNodeID)") {
            guard autoRefreshLog else { return }
            while autoRefreshLog, !Task.isCancelled {
                await appState.refreshRealmHarnessLog(nodeID: appState.selectedHarnessNodeID)
                let nanos = UInt64(autoRefreshSeconds) * 1_000_000_000
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }
}
