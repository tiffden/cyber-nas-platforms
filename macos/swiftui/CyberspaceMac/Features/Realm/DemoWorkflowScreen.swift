import SwiftUI

/// Demo Workflow — realm bootstrap and join phase.
///
/// Assumes machines are already set up (Machine Setup tab). The bootstrap path
/// creates node identity and realm membership on Machine 1; remaining nodes
/// then join via its listener.
struct DemoWorkflowScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var realmNameDraft = ""
    @State private var nodeNameDraft = ""
    @State private var autoRefreshLog = false
    @State private var autoRefreshSeconds = 2
    @State private var useReadableLogLayout = true
    @State private var didInitialize = false

    private var renderedHarnessLog: String {
        let raw = appState.harnessCurrentLog
        let formatted: String
        if raw.isEmpty {
            formatted = "No log loaded."
        } else if useReadableLogLayout {
            let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            formatted = lines.map { formatLogLine(String($0)) }.joined(separator: "\n")
        } else {
            formatted = raw
        }
        let trace = appState.harnessBackendTraceBlock
        if trace.isEmpty { return formatted }
        return "\(trace)\n\n\(formatted)"
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
                        Text("Realm Name")
                            .frame(width: 130, alignment: .leading)
                        TextField("local-realm", text: $realmNameDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                    }

                    HStack {
                        Text("Node Name")
                            .frame(width: 130, alignment: .leading)
                        TextField("node1", text: $nodeNameDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        Text("(bootstrap node identity)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    HStack {
                        Text("Bootstrap Machine")
                            .frame(width: 130, alignment: .leading)
                        Text(bootstrapMachineLabel)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Join Policy")
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
                                await appState.selfJoinRealmHarness(
                                    nodeNameOverride: nodeNameDraft
                                )
                                // Stop here if self-join failed — preserve the error message and
                                // avoid masking it with a spurious "Node environment file not found".
                                guard appState.lastErrorMessage == nil else { return }
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
            GroupBox(appState.harnessRealmName.isEmpty
                        ? "Node Status"
                        : "Node Status for Realm \(appState.harnessRealmName)") {
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
                                    Text("\(node.host):\(String(node.port))").frame(width: 140, alignment: .leading)
                                    Text(node.workdir).lineLimit(1).truncationMode(.middle)
                                }
                                .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
            }

            // ── 5. Node Log (fills remaining vertical space) ──────────────
            GroupBox("Node Log") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if appState.harnessNodes.isEmpty {
                            Text("No nodes —")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("View:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Log view", selection: $appState.selectedHarnessNodeID) {
                                Text("Realm (All)").tag(0)
                                ForEach(appState.harnessNodes) { node in
                                    Text("Node \(node.id) (\(node.nodeName))").tag(node.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 160)
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
            nodeNameDraft = appState.harnessMachines.first?.machineLabel ?? ""
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
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return rawLine }
            if trimmed.hasPrefix("[") { return rawLine }
            if let data = rawLine.data(using: .utf8),
               let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               object["kind"] != nil {
                return "[debug] \(rawLine)"
            }
            return "[info] \(rawLine)"
        }

        let timestamp = shortTimestamp(object["ts"] as? String)
        let rawLevel = object["level"] as? String ?? "info"
        let levelLabel = normalizedLogLevel(rawLevel)
        let result = object["result"] as? String ?? "ok"
        let subsystem = "\(component):\(action)"

        var messageParts: [String] = [result]
        if let nodeID = object["node_id"] as? String, !nodeID.isEmpty {
            messageParts.append("node \(nodeID)")
        }
        if let duration = object["duration_ms"] as? String, !duration.isEmpty {
            messageParts.append("\(duration)ms")
        }
        if let message = object["message"] as? String, !message.isEmpty {
            messageParts.append(message)
        }
        if let requestID = object["request_id"] as? String,
           !requestID.isEmpty,
           requestID != "n/a" {
            messageParts.append("req \(requestID.prefix(12))")
        }

        let typeCol = "[\(levelLabel)]".padding(toLength: 8, withPad: " ", startingAt: 0)
        let subsystemCol = subsystem.padding(toLength: 34, withPad: " ", startingAt: 0)
        return "\(timestamp)  \(typeCol)  \(subsystemCol)  \(messageParts.joined(separator: " | "))"
    }

    private func normalizedLogLevel(_ level: String) -> String {
        switch level.lowercased() {
        case "debug": return "debug"
        case "warn": return "warn"
        case "error", "fault", "crit", "critical": return "crit"
        default: return "info"
        }
    }

    private func shortTimestamp(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "--:--:--.---" }
        // Unix epoch seconds emitted by spki-realm.sps (all-digit, > 1 billion).
        if let secs = TimeInterval(raw), secs > 1_000_000_000 {
            let date = Date(timeIntervalSince1970: secs)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm:ss.SSS"
            return f.string(from: date)
        }
        // ISO 8601 (with or without fractional seconds) from other log sources.
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: raw) ?? {
            let fallback = ISO8601DateFormatter()
            return fallback.date(from: raw)
        }()
        guard let date else { return raw }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }
}
