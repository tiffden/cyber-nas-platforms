import SwiftUI
import AppKit

struct LocalHarnessScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var autoRefreshLog = false
    @State private var autoRefreshSeconds = 2
    @State private var useReadableLogLayout = true
    @State private var realmNameDraft = ""
    @State private var harnessHostDraft = ""
    @State private var harnessRootDraft = ""
    @State private var nodeNamesDraft = ""
    @State private var didInitializeActionDrafts = false
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case realmName
    }

    private var joinedMembers: Int {
        appState.harnessNodes.map(\.memberCount).max() ?? 0
    }

    private var testbedRootHint: String {
        appState.harnessNodes.first?.workdir
            .components(separatedBy: "/node")
            .first ?? "~/.cyberspace/testbed"
    }

    private var renderedHarnessLog: String {
        let raw = appState.harnessCurrentLog
        guard !raw.isEmpty else { return "No log loaded." }
        guard useReadableLogLayout else { return raw }

        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { formatLogLine(String($0)) }.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Harness (Builder Mode)")
                .font(.title2.weight(.semibold))
            Text("UI Version: \(appState.uiVersionLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox("Testbed Summary") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nodes configured: \(appState.harnessNodeCount)")
                    Text("Highest reported member count: \(joinedMembers)")
                    Text("Selected log node: #\(appState.selectedHarnessNodeID)")
                    Text("Test data root: \(testbedRootHint)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Testbed data is isolated from normal runtime keys/vault state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Actions") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Realm name")
                            .frame(width: 110, alignment: .leading)
                        TextField("local-realm", text: $realmNameDraft)
                            .focused($focusedField, equals: .realmName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)

                        Text("Host")
                            .frame(width: 50, alignment: .leading)
                        TextField("127.0.0.1", text: $harnessHostDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)

                        Text("Port")
                            .frame(width: 40, alignment: .leading)
                        Stepper(value: $appState.harnessPort, in: 1...65535) {
                            Text("\(appState.harnessPort)")
                                .monospacedDigit()
                        }
                        .frame(width: 130)
                    }

                    HStack {
                        Text("Nodes")
                            .frame(width: 110, alignment: .leading)
                        Stepper(value: $appState.harnessNodeCount, in: 1...10) {
                            Text("\(appState.harnessNodeCount)")
                                .monospacedDigit()
                        }
                        .frame(width: 130)

                        Text("Harness root")
                            .frame(width: 90, alignment: .leading)
                        TextField("~/.cyberspace/testbed (optional override)", text: $harnessRootDraft)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Node names")
                            .frame(width: 110, alignment: .leading)
                        TextField("node1,node2,node3", text: $nodeNamesDraft)
                            .textFieldStyle(.roundedBorder)
                        Text("comma-separated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Create Test Realm") {
                            Task {
                                applyHarnessDrafts()
                                await appState.createRealmTestEnvironment(nodeCount: appState.harnessNodeCount)
                                await appState.refreshRealmHarnessNodes()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Status") {
                            Task {
                                applyHarnessDrafts()
                                await appState.refreshRealmHarnessNodes()
                                await appState.refreshRealmHarnessLog(nodeID: appState.selectedHarnessNodeID)
                            }
                        }
                        Button("Self-Join") {
                            Task {
                                applyHarnessDrafts()
                                await appState.selfJoinRealmHarness(nodeCount: appState.harnessNodeCount)
                            }
                        }
                        Button("Invite Others") {
                            Task {
                                applyHarnessDrafts()
                                await appState.inviteOtherRealmHarnessNodes(nodeCount: appState.harnessNodeCount)
                            }
                        }
                        Button("Start UIs") {
                            Task {
                                applyHarnessDrafts()
                                await appState.launchRealmHarnessUIs(nodeCount: appState.harnessNodeCount)
                            }
                        }
                        Button("Stop UIs") {
                            Task {
                                applyHarnessDrafts()
                                await appState.stopRealmHarnessUIs(nodeCount: appState.harnessNodeCount)
                            }
                        }
                    }
                }
            }

            if !appState.harnessLaunchOutput.isEmpty {
                Text(appState.harnessLaunchOutput)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            GroupBox("Backend Call") {
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

            GroupBox("Node Metadata") {
                if appState.harnessNodes.isEmpty {
                    Text("No local harness nodes loaded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Node").frame(width: 44, alignment: .leading)
                            Text("Name").frame(width: 120, alignment: .leading)
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
                                Text(node.nodeName).frame(width: 120, alignment: .leading)
                                Text(node.status).frame(width: 100, alignment: .leading)
                                Text("\(node.memberCount)").frame(width: 70, alignment: .leading)
                                Text("\(node.host):\(node.port)").frame(width: 140, alignment: .leading)
                                Text(node.workdir).lineLimit(1).truncationMode(.middle)
                            }
                            .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }

            GroupBox("Current Log") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if appState.harnessNodes.isEmpty {
                            Text("No nodes -")
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
                    .frame(minHeight: 220, maxHeight: 260)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            guard !didInitializeActionDrafts else { return }
            realmNameDraft = appState.harnessRealmName
            harnessHostDraft = appState.harnessHost
            harnessRootDraft = appState.harnessRootOverride
            nodeNamesDraft = appState.harnessNodeNamesCSV
            activateWindowAndFocusRealmName()
            didInitializeActionDrafts = true
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

    private func applyHarnessDrafts() {
        appState.harnessRealmName = realmNameDraft
        appState.harnessHost = harnessHostDraft
        appState.harnessRootOverride = harnessRootDraft
        appState.harnessNodeNamesCSV = nodeNamesDraft
    }

    private func activateWindowAndFocusRealmName() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first(where: { $0.canBecomeKey }) {
            // orderFrontRegardless promotes the window even when the app is
            // not yet the active application (e.g. shell-launched binary).
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            focusedField = .realmName
        }
    }
}
