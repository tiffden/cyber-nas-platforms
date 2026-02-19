import SwiftUI

/// Demo Workflow — realm bootstrap and join phase.
///
/// Assumes machines are already set up (Machine Setup tab). The bootstrap path
/// creates node identity and realm membership on Machine 1; remaining nodes
/// then join via its listener.
struct DemoWorkflowScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var realmNameDraft = ""
    @State private var autoRefreshLog = false
    @State private var autoRefreshSeconds = 2
    @State private var useReadableLogLayout = true
    @State private var didInitialize = false

    private var renderedHarnessLog: String {
        let raw = appState.harnessCurrentLog
        guard !raw.isEmpty else { return "No log loaded." }
        guard useReadableLogLayout else { return raw }
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { formatLogLine(String($0)) }.joined(separator: "\n")
    }

    private var masterBootstrapped: Bool {
        guard let master = appState.harnessNodes.first(where: { $0.id == 1 })
                        ?? appState.harnessNodes.first else { return false }
        return master.status != "standalone"
    }

    private var bootstrapMachineLabel: String {
        if let m = appState.harnessMachines.first {
            return "\(m.machineLabel) (\(m.host):\(m.port))"
        }
        if let n = appState.harnessNodes.first {
            return "\(n.nodeName) (\(n.host):\(n.port))"
        }
        return "Machine 1 (not yet configured)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── 1. Realm Setup ────────────────────────────────────────────
            GroupBox("Realm Setup") {
                VStack(alignment: .leading, spacing: 8) {
                    if appState.harnessPhase == .notSetup {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .imageScale(.small)
                            Text("Complete Machine Setup first — machines must exist before bootstrapping a realm.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Realm name")
                            .frame(width: 130, alignment: .leading)
                        TextField("local-realm", text: $realmNameDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                    }

                    HStack {
                        Text("Bootstrap machine")
                            .frame(width: 130, alignment: .leading)
                        Text(bootstrapMachineLabel)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Join policy")
                            .frame(width: 130, alignment: .leading)
                        Text("open")
                            .font(.system(.caption, design: .monospaced))
                        Text("(policy API not yet bridged)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                    }

                    HStack {
                        Button("Bootstrap Realm (Self-Join)") {
                            Task {
                                appState.harnessRealmName = realmNameDraft
                                await appState.selfJoinRealmHarness(nodeCount: appState.harnessNodeCount)
                                await appState.refreshRealmHarnessNodes()
                                await appState.refreshRealmHarnessLog(nodeID: appState.selectedHarnessNodeID)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.harnessPhase == .notSetup)

                        if let err = appState.lastErrorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // ── 2. Bootstrap Result ───────────────────────────────────────
            if !appState.harnessNodes.isEmpty {
                bootstrapResultSection()
            }

            // ── 3. Join Remaining Nodes ───────────────────────────────────
            if appState.harnessNodeCount > 1 {
                GroupBox("Join Remaining Nodes") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Each candidate node dials Machine 1's join listener and requests enrollment. mDNS advertisement starts automatically at that point.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Join Remaining Nodes") {
                            Task {
                                await appState.inviteOtherRealmHarnessNodes(nodeCount: appState.harnessNodeCount)
                                await appState.refreshRealmHarnessNodes()
                                await appState.refreshRealmHarnessLog(nodeID: appState.selectedHarnessNodeID)
                            }
                        }
                        .disabled(!masterBootstrapped)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // ── 4. Node Status ────────────────────────────────────────────
            GroupBox("Node Status") {
                VStack(alignment: .leading, spacing: 6) {
                    Button("Refresh") {
                        Task {
                            await appState.refreshRealmHarnessNodes()
                            await appState.refreshRealmHarnessLog(nodeID: appState.selectedHarnessNodeID)
                        }
                    }

                    if appState.harnessNodes.isEmpty {
                        Text("No nodes yet. Complete Machine Setup first, then Bootstrap Realm.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Node").frame(width: 44, alignment: .leading)
                                Text("Name").frame(width: 120, alignment: .leading)
                                Text("Status").frame(width: 100, alignment: .leading)
                                Text("Members").frame(width: 70, alignment: .leading)
                                Text("Listener").frame(width: 70, alignment: .leading)
                                Text("Advertised").frame(width: 80, alignment: .leading)
                                Text("Host:Port").frame(width: 140, alignment: .leading)
                                Text("Workdir").frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                            ForEach(appState.harnessNodes) { node in
                                let listenerUp = node.status != "standalone"
                                HStack {
                                    Text("#\(node.id)").frame(width: 44, alignment: .leading)
                                    Text(node.nodeName).frame(width: 120, alignment: .leading)
                                    Text(node.status).frame(width: 100, alignment: .leading)
                                    Text("\(node.memberCount)").frame(width: 70, alignment: .leading)
                                    Text(listenerUp ? "up" : "—").frame(width: 70, alignment: .leading)
                                    Text(listenerUp ? "mDNS" : "—").frame(width: 80, alignment: .leading)
                                    Text("\(node.host):\(node.port)").frame(width: 140, alignment: .leading)
                                    Text(node.workdir).lineLimit(1).truncationMode(.middle)
                                }
                                .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
            }

            // ── 5. Last Executed Backend Call ─────────────────────────────
            GroupBox("Last Executed Backend Call") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.harnessLastBackendCommand.isEmpty
                         ? "No command run yet."
                         : appState.harnessLastBackendCommand)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !appState.harnessLastBackendResult.isEmpty {
                        Text(appState.harnessLastBackendResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // ── 6. Current Log (fills remaining vertical space) ───────────
            GroupBox("Current Log") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if appState.harnessNodes.isEmpty {
                            Text("No nodes —")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Node:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Node", selection: $appState.selectedHarnessNodeID) {
                                ForEach(appState.harnessNodes) { node in
                                    Text("Node \(node.id) (\(node.nodeName))").tag(node.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 140)
                        }
                        Button("Refresh Log") {
                            Task { await appState.refreshRealmHarnessLog(nodeID: appState.selectedHarnessNodeID) }
                        }
                        Toggle("Auto-refresh every:", isOn: $autoRefreshLog)
                        Stepper(value: $autoRefreshSeconds, in: 1...10) {
                            Text("\(autoRefreshSeconds)s").monospacedDigit()
                        }
                        .frame(width: 90)
                        .disabled(!autoRefreshLog)
                        Toggle("Readable", isOn: $useReadableLogLayout)
                    }

                    ScrollView {
                        Text(renderedHarnessLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            guard !didInitialize else { return }
            realmNameDraft = appState.harnessRealmName
            didInitialize = true
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

    // MARK: - Bootstrap Result

    @ViewBuilder
    private func bootstrapResultSection() -> some View {
        let masterNode = appState.harnessNodes.first(where: { $0.id == 1 })
                      ?? appState.harnessNodes[0]
        let bootstrapped = masterNode.status != "standalone"

        GroupBox("Bootstrap Result — \(masterNode.nodeName)") {
            VStack(alignment: .leading, spacing: 4) {
                resultRow(label: "Node identity",   active: bootstrapped,
                          trueLabel: "created",  falseLabel: "not yet")
                resultRow(label: "Membership cert", active: bootstrapped,
                          trueLabel: "issued",   falseLabel: "not yet")
                resultRow(label: "Join listener",   active: bootstrapped,
                          trueLabel: "active",   falseLabel: "inactive")
                resultRow(label: "Discovery",       active: bootstrapped,
                          trueLabel: "mDNS",     falseLabel: "inactive")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func resultRow(label: String, active: Bool,
                           trueLabel: String, falseLabel: String) -> some View {
        HStack(spacing: 8) {
            Text(active ? "✓" : "—")
                .foregroundStyle(active ? .green : .secondary)
                .frame(width: 16, alignment: .center)
                .font(.system(.caption, design: .monospaced))
            Text(label)
                .frame(width: 140, alignment: .leading)
                .font(.caption)
            Text(active ? trueLabel : falseLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(active ? .primary : .secondary)
        }
    }

    // MARK: - Log Formatting

    private func formatLogLine(_ rawLine: String) -> String {
        guard let data = rawLine.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let component = object["component"] as? String,
              let action = object["action"] as? String else {
            return rawLine
        }

        let timestamp = shortTimestamp(object["ts"] as? String)
        let level = (object["level"] as? String ?? "info").uppercased()
        let result = object["result"] as? String ?? "ok"

        var detailParts: [String] = []
        if let nodeID = object["node_id"] as? String, !nodeID.isEmpty {
            detailParts.append("node \(nodeID)")
        }
        if let duration = object["duration_ms"] as? String, !duration.isEmpty {
            detailParts.append("\(duration)ms")
        }
        if let message = object["message"] as? String, !message.isEmpty {
            detailParts.append(message)
        }
        if let requestID = object["request_id"] as? String,
           !requestID.isEmpty,
           requestID != "n/a" {
            detailParts.append("req \(requestID.prefix(12))")
        }

        var line = "[\(timestamp)] [\(level)] \(component) \(action) -> \(result)"
        if !detailParts.isEmpty {
            line += " | " + detailParts.joined(separator: " | ")
        }
        return line
    }

    private func shortTimestamp(_ iso8601: String?) -> String {
        guard let iso8601, !iso8601.isEmpty else { return "--:--:--" }
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso8601) else { return iso8601 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
