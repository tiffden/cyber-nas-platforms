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
    @State private var joinSelections: [Int: Bool] = [:]
    @State private var joinNodeNames: [Int: String] = [:]

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
        // "listening" is the expected final status once the bootstrap node's listener is up.
        // Any non-standalone status means the realm was at least partially bootstrapped.
        return master.status != "standalone"
    }

    private var allNodesListening: Bool {
        guard appState.harnessNodes.count >= appState.harnessNodeCount else { return false }
        // All nodes reach "listening" once their TCP listener + mDNS advertisement is active.
        return appState.harnessNodes.allSatisfy { $0.status == "listening" }
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

    private var unjoinedMachines: [HarnessLocalMachine] {
        appState.harnessMachines.filter { machine in
            guard machine.id != 1 else { return false }
            let node = appState.harnessNodes.first(where: { $0.id == machine.id })
            return node == nil || node?.status == "standalone"
        }
    }

    private var anyMachineSelected: Bool {
        let unjoinedIDs = Set(unjoinedMachines.map(\.id))
        return joinSelections.contains { id, isSelected in
            isSelected && unjoinedIDs.contains(id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── 1. Bootstrap Realm ────────────────────────────────────────
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
                .disabled(appState.harnessPhase == .notSetup || masterBootstrapped)

                if let err = appState.lastErrorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // ── 2. Realm Setup ────────────────────────────────────────────
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // ── 3. Join Remaining Machines to Realm ───────────────────────────────────
            if appState.harnessNodeCount > 1 {
                GroupBox("Join Remaining Machines to Realm") {
                    VStack(alignment: .leading, spacing: 8) {
                        // ── Action buttons ──────────────────────────────
                        HStack(spacing: 8) {
                            Button("Select All") {
                                for machine in unjoinedMachines {
                                    joinSelections[machine.id] = true
                                }
                            }
                            .disabled(unjoinedMachines.isEmpty)

                            Button("Join Realm") {
                                Task {
                                    let unjoinedIDs = Set(unjoinedMachines.map(\.id))
                                    let selectedIDs = joinSelections
                                        .filter { unjoinedIDs.contains($0.key) && $0.value }
                                        .map(\.key)
                                        .sorted()
                                    // Always supply a name: typed input or the "node<id>" placeholder default.
                                    let overrides = selectedIDs.reduce(into: [Int: String]()) { dict, id in
                                        let typed = joinNodeNames[id] ?? ""
                                        dict[id] = typed.isEmpty ? "node\(id)" : typed
                                    }
                                    await appState.joinSelectedRealmHarnessNodes(
                                        nodeIDs: selectedIDs,
                                        nodeNameOverrides: overrides
                                    )
                                    await appState.refreshRealmHarnessLog(nodeID: appState.selectedHarnessNodeID)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!masterBootstrapped || !anyMachineSelected)
                        }

                        // ── Machine list ────────────────────────────────
                        if unjoinedMachines.isEmpty {
                            Text(masterBootstrapped ? "All machines are listening in the realm." : "Bootstrap Realm first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 0) {
                                Text("").frame(width: 24)
                                Text("#").frame(width: 36, alignment: .leading)
                                Text("Machine").frame(width: 110, alignment: .leading)
                                Text("Node Name").frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                            ForEach(unjoinedMachines) { machine in
                                HStack(spacing: 0) {
                                    Toggle("", isOn: Binding(
                                        get: { joinSelections[machine.id] ?? false },
                                        set: { joinSelections[machine.id] = $0 }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    .frame(width: 24)

                                    Text("#\(machine.id)")
                                        .frame(width: 36, alignment: .leading)
                                        .font(.system(.caption, design: .monospaced))

                                    Text(machine.machineLabel)
                                        .frame(width: 110, alignment: .leading)
                                        .font(.system(.caption, design: .monospaced))

                                    TextField("node\(machine.id)", text: Binding(
                                        get: { joinNodeNames[machine.id] ?? "" },
                                        set: { joinNodeNames[machine.id] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.caption, design: .monospaced))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // ── 4. Realm Status ───────────────────────────────────────────
            if !appState.harnessNodes.isEmpty {
                realmStatusSection()
            }

            // ── 5. Node Status ────────────────────────────────────────────
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
                                Text("Discovery").frame(width: 80, alignment: .leading)
                                Text("Host:Port").frame(width: 140, alignment: .leading)
                                Text("UUID").frame(width: 270, alignment: .leading)
                                Text("Workdir").frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                            ForEach(appState.harnessNodes) { node in
                                let isListening = node.status == "listening"
                                HStack {
                                    Text("#\(node.id)").frame(width: 44, alignment: .leading)
                                    Text(node.nodeName).frame(width: 120, alignment: .leading)
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(isListening ? Color.green : Color.secondary)
                                            .frame(width: 6, height: 6)
                                        Text(node.status)
                                            .foregroundStyle(isListening ? Color.green : Color.primary)
                                    }
                                    .frame(width: 100, alignment: .leading)
                                    Text(isListening ? "mDNS" : "—").frame(width: 80, alignment: .leading)
                                    Text("\(node.host):\(String(node.port))").frame(width: 140, alignment: .leading)
                                    Text(node.uuid.isEmpty ? "—" : node.uuid)
                                        .frame(width: 270, alignment: .leading)
                                        .textSelection(.enabled)
                                    Text(node.workdir).lineLimit(1).truncationMode(.middle)
                                }
                                .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
            }

            // ── 6. Node Log (fills remaining vertical space) ──────────────
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
            nodeNameDraft = "node1"
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

    // MARK: - Realm Status

    @ViewBuilder
    private func realmStatusSection() -> some View {
        let master = appState.harnessNodes.first(where: { $0.id == 1 })
                  ?? appState.harnessNodes[0]
        GroupBox("Realm") {
            VStack(alignment: .leading, spacing: 6) {
                realmInfoRow(label: "Name",   value: appState.harnessRealmName.isEmpty ? "—" : appState.harnessRealmName)
                realmInfoRow(label: "Nodes",  value: "\(appState.harnessNodes.count)")
                realmInfoRow(label: "UUID",   value: master.uuid.isEmpty ? "—" : master.uuid)
                realmInfoRow(label: "Policy", value: master.policy.isEmpty ? "—" : master.policy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func realmInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 130, alignment: .leading)
                .font(.caption)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
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

// MARK: - Demo Vaults Tab

struct DemoVaultsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var vaultPathDraft = ".vault/demo.txt"
    @State private var vaultValueDraft = "hello-realm"
    @State private var didRunVaultPut = false
    @State private var didRunVaultGet = false
    @State private var vaultActionStatus = "Run Vault Put, then Get, then Commit."
    @State private var isVaultActionRunning = false

    private var vaultTargetNodeID: Int {
        appState.selectedHarnessNodeID > 0 ? appState.selectedHarnessNodeID : 1
    }

    private var realmBootstrapped: Bool {
        appState.harnessNodes.contains(where: { $0.status != "standalone" })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !realmBootstrapped {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                    Text("Bootstrap a realm in Demo Workflow first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Vault Target") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Node")
                            .frame(width: 56, alignment: .leading)
                        Picker("", selection: $appState.selectedHarnessNodeID) {
                            Text("Node 1 (default)").tag(0)
                            ForEach(appState.harnessNodes) { node in
                                Text("Node \(node.id) (\(node.nodeName))").tag(node.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }

                    HStack {
                        Text("Path")
                            .frame(width: 56, alignment: .leading)
                        TextField(".vault/demo.txt", text: $vaultPathDraft)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Value")
                            .frame(width: 56, alignment: .leading)
                        TextField("hello-realm", text: $vaultValueDraft)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Actions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Validation flow: Put → Get → Commit. Buttons are gated to verify sequence and node readiness.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("Vault Put") {
                            Task {
                                isVaultActionRunning = true
                                let out = await appState.vaultPut(
                                    nodeID: vaultTargetNodeID,
                                    path: vaultPathDraft,
                                    value: vaultValueDraft
                                )
                                if appState.lastErrorMessage == nil {
                                    didRunVaultPut = true
                                    didRunVaultGet = false
                                    vaultActionStatus = out?.isEmpty == false
                                        ? out!
                                        : "Vault Put completed for node \(vaultTargetNodeID): \(vaultPathDraft)"
                                } else {
                                    didRunVaultPut = false
                                    didRunVaultGet = false
                                    vaultActionStatus = appState.lastErrorMessage ?? "Vault Put failed."
                                }
                                isVaultActionRunning = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!realmBootstrapped || isVaultActionRunning || vaultPathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Vault Get") {
                            Task {
                                isVaultActionRunning = true
                                let out = await appState.vaultGet(
                                    nodeID: vaultTargetNodeID,
                                    path: vaultPathDraft
                                )
                                if appState.lastErrorMessage == nil {
                                    didRunVaultGet = true
                                    vaultActionStatus = out?.isEmpty == false
                                        ? out!
                                        : "Vault Get completed for node \(vaultTargetNodeID): \(vaultPathDraft)"
                                } else {
                                    didRunVaultGet = false
                                    vaultActionStatus = appState.lastErrorMessage ?? "Vault Get failed."
                                }
                                isVaultActionRunning = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!realmBootstrapped || isVaultActionRunning || !didRunVaultPut)

                        Button("Vault Commit") {
                            Task {
                                isVaultActionRunning = true
                                let out = await appState.vaultCommit(nodeID: vaultTargetNodeID)
                                if appState.lastErrorMessage == nil {
                                    vaultActionStatus = out?.isEmpty == false
                                        ? out!
                                        : "Vault Commit completed for node \(vaultTargetNodeID)."
                                } else {
                                    vaultActionStatus = appState.lastErrorMessage ?? "Vault Commit failed."
                                }
                                isVaultActionRunning = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!realmBootstrapped || isVaultActionRunning || !didRunVaultGet)
                    }

                    Text(vaultActionStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
    }
}
