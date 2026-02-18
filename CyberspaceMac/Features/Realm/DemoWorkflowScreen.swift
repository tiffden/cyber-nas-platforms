import SwiftUI

/// Demo Workflow — realm bootstrap and join phase.
///
/// Assumes machines are already set up (Machine Setup tab). Each step creates node
/// identity and realm membership at join time — no node identity exists before this.
struct DemoWorkflowScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var autoRefreshLog = false
    @State private var autoRefreshSeconds = 2
    @State private var useReadableLogLayout = true

    private var renderedHarnessLog: String {
        let raw = appState.harnessCurrentLog
        guard !raw.isEmpty else { return "No log loaded." }
        guard useReadableLogLayout else { return raw }

        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { formatLogLine(String($0)) }.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Join Protocol") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Join is pull-based: each candidate node dials a known member's host:port and requests enrollment. mDNS advertisement starts automatically when a node's join listener comes up — it is not a manual action.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !appState.harnessLaunchOutput.isEmpty {
                        Text(appState.harnessLaunchOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Workflow") {
                HStack {
                    Button("Bootstrap Realm on Machine 1") {
                        Task { await appState.selfJoinRealmHarness(nodeCount: appState.harnessNodeCount) }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Join Remaining Machines") {
                        Task { await appState.inviteOtherRealmHarnessNodes(nodeCount: appState.harnessNodeCount) }
                    }

                    Button("Status") {
                        Task {
                            await appState.refreshRealmHarnessNodes()
                            await appState.refreshRealmHarnessLog(nodeID: appState.selectedHarnessNodeID)
                        }
                    }

                    Button("Start UIs") {
                        Task { await appState.launchRealmHarnessUIs(nodeCount: appState.harnessNodeCount) }
                    }

                    Button("Stop UIs") {
                        Task { await appState.stopRealmHarnessUIs(nodeCount: appState.harnessNodeCount) }
                    }

                    if let err = appState.lastErrorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            GroupBox("Node Status") {
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
                            HStack {
                                // Join listener starts when a node is no longer standalone.
                                // mDNS advertisement fires automatically at that point.
                                let listenerUp = node.status != "standalone"
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

            GroupBox("Last Executed Backend Call") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.harnessLastBackendCommand.isEmpty ? "No command run yet." : appState.harnessLastBackendCommand)
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
                            Text("\(autoRefreshSeconds)s")
                                .monospacedDigit()
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
