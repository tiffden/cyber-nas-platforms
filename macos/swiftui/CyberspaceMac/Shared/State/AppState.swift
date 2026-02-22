import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    // Bump this on each UI rollout so operators can verify they are on the latest binary.
    static let uiVersion = "ui-2026.02.22-r01"

    // MARK: - Harness State

    @Published var harnessNodeCount: Int = 3
    @Published var harnessRealmName: String = "local-realm"
    @Published var harnessHost: String = "127.0.0.1"
    @Published var harnessPort: Int = 7780
    @Published var harnessRootOverride: String = ""
    @Published var harnessNodeNamesCSV: String = ""
    /// Per-machine config set by MachineSetupScreen. When non-empty, overrides the
    /// scalar host/port/nodeNamesCSV fields in `currentHarnessConfig`.
    @Published var harnessMachines: [HarnessLocalMachine] = []
    @Published var harnessPhase: HarnessPhase = .notSetup
    @Published var harnessNodes: [RealmHarnessNodeMetadata] = []
    @Published var selectedHarnessNodeID: Int = 1
    @Published var harnessCurrentLog: String = ""
    @Published var harnessSetupLog: String = ""
    @Published var harnessLaunchOutput: String = ""
    @Published var harnessLastBackendCommand: String = ""
    @Published var harnessLastBackendResult: String = ""
    @Published var lastErrorMessage: String?
    @Published var harnessLogLevelSetting: String = ""

    private let api: any ClientAPI
    private let launchNodeID: Int

    init(
        api: any ClientAPI = CLIBridgeAPIClient(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.api = api
        // `SPKI_NODE_ID` is set by harness scripts so each UI instance can identify itself in the window title.
        self.launchNodeID = Int(environment["SPKI_NODE_ID"] ?? "") ?? 1
        if let realmName = environment["SPKI_REALM_HARNESS_NAME"], !realmName.isEmpty {
            self.harnessRealmName = realmName
        }
        if let host = environment["SPKI_REALM_HARNESS_HOST"], !host.isEmpty {
            self.harnessHost = host
        }
        if let port = Int(environment["SPKI_REALM_HARNESS_PORT"] ?? ""), port > 0 {
            self.harnessPort = port
        }
        if let root = environment["SPKI_REALM_HARNESS_ROOT"], !root.isEmpty {
            self.harnessRootOverride = root
        }
        if let nodeNamesCSV = environment["SPKI_REALM_HARNESS_NODE_NAMES"], !nodeNamesCSV.isEmpty {
            self.harnessNodeNamesCSV = nodeNamesCSV
        }
        if let logLevel = environment["SPKI_LOG_LEVEL"], !logLevel.isEmpty {
            self.harnessLogLevelSetting = logLevel
        }
    }

    // MARK: - UI Labels

    var uiInstanceLabel: String {
        if launchNodeID <= 1 {
            return "Main"
        }
        return "Test Client \(launchNodeID - 1)"
    }

    var uiWindowTitle: String {
        "Cyberspace \(Self.uiVersion) | \(uiInstanceLabel)"
    }

    var uiVersionLabel: String {
        Self.uiVersion
    }

    var harnessLogLevelOptions: [String] {
        ["debug", "info", "warn", "crit"]
    }

    var effectiveHarnessLogLevel: String {
        let normalized = harnessLogLevelSetting
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "debug", "info", "warn", "crit":
            return normalized
        default:
            return "info"
        }
    }

    var effectiveHarnessLogLevelLabel: String {
        let normalized = harnessLogLevelSetting
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.isEmpty {
            return "info (default)"
        }
        if normalized == effectiveHarnessLogLevel {
            return normalized
        }
        return "\(effectiveHarnessLogLevel) (fallback from '\(normalized)')"
    }

    func setHarnessLogLevel(_ level: String) {
        let normalized = level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if harnessLogLevelOptions.contains(normalized) {
            harnessLogLevelSetting = normalized
        }
    }

    var harnessBackendTraceBlock: String {
        var lines: [String] = []
        if !harnessLastBackendCommand.isEmpty {
            lines.append("[debug] backend.call \(harnessLastBackendCommand)")
        }
        if !harnessLastBackendResult.isEmpty {
            let level = harnessLastBackendResult.lowercased().hasPrefix("error") ? "crit" : "info"
            let resultLines = harnessLastBackendResult
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            if resultLines.count <= 1 {
                lines.append("[\(level)] backend.result \(harnessLastBackendResult)")
            } else {
                lines.append("[\(level)] backend.result")
                lines.append(contentsOf: resultLines.map { "  \($0)" })
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func makeRequestID(action: String) -> String {
        "\(action)-\(UUID().uuidString.lowercased())"
    }

    private func shellQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private func harnessEnvPrefix(config: RealmHarnessCreateConfig) -> String {
        var parts: [String] = []
        if !config.realmName.isEmpty {
            parts.append("SPKI_REALM_HARNESS_NAME=\(shellQuote(config.realmName))")
        }
        if let logLevel = config.logLevel, !logLevel.isEmpty {
            parts.append("SPKI_LOG_LEVEL=\(shellQuote(logLevel))")
        }
        if !config.host.isEmpty {
            parts.append("SPKI_REALM_HARNESS_HOST=\(shellQuote(config.host))")
        }
        if config.port > 0 {
            parts.append("SPKI_REALM_HARNESS_PORT=\(config.port)")
        }
        if let root = config.harnessRoot, !root.isEmpty {
            parts.append("SPKI_REALM_HARNESS_ROOT=\(shellQuote(root))")
        }
        if let nodeNamesCSV = config.nodeNamesCSV, !nodeNamesCSV.isEmpty {
            parts.append("SPKI_REALM_HARNESS_NODE_NAMES=\(shellQuote(nodeNamesCSV))")
        }
        guard !parts.isEmpty else { return "" }
        return parts.joined(separator: " ") + " "
    }

    private func setHarnessBackendCall(command: String) {
        harnessLastBackendCommand = command
    }

    private func setHarnessBackendResult(_ result: String) {
        harnessLastBackendResult = result
    }

    /// Format an error for display, appending stderr when the underlying CLI command failed.
    private func formatError(_ error: Error) -> String {
        guard let payload = error as? APIErrorPayload else {
            return error.localizedDescription
        }
        var parts = [payload.message]
        if let status = payload.details?["status"], !status.isEmpty {
            parts.append("exit \(status)")
        }
        if let stderr = payload.details?["stderr"], !stderr.isEmpty {
            parts.append("stderr:\n\(stderr)")
        }
        return parts.joined(separator: "\n")
    }

    private func harnessScriptCommand(subcommand: String, nodeCount: Int) -> String {
        let config = currentHarnessConfig
        return "\(harnessEnvPrefix(config: config))Scripts/realm-harness.sh \(subcommand) \(nodeCount)"
    }

    private var currentHarnessConfig: RealmHarnessCreateConfig {
        let trimmedRoot = harnessRootOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let realmName = harnessRealmName.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmedRoot.isEmpty ? nil : trimmedRoot

        // When per-machine config is set, derive host/port/names from it.
        if !harnessMachines.isEmpty {
            // TODO: validate that each machineLabel is a legal macOS directory name
            // (no NUL or '/', length ≤ 255, non-empty) before passing to the harness script.
            let nodeNamesCSV = harnessMachines.map(\.machineLabel).joined(separator: ",")
            return RealmHarnessCreateConfig(
                realmName: realmName,
                host: harnessMachines[0].host,
                port: harnessMachines[0].port,
                harnessRoot: root,
                nodeNamesCSV: nodeNamesCSV.isEmpty ? nil : nodeNamesCSV,
                logLevel: effectiveHarnessLogLevel
            )
        }

        // Fallback: scalar fields (used when app is launched by harness scripts via env vars).
        let trimmedNodeNames = harnessNodeNamesCSV.trimmingCharacters(in: .whitespacesAndNewlines)
        return RealmHarnessCreateConfig(
            realmName: realmName,
            host: harnessHost.trimmingCharacters(in: .whitespacesAndNewlines),
            port: harnessPort,
            harnessRoot: root,
            nodeNamesCSV: trimmedNodeNames.isEmpty ? nil : trimmedNodeNames,
            logLevel: effectiveHarnessLogLevel
        )
    }

    private func logHarnessEvent(
        action: String,
        result: String,
        requestID: String,
        fields: [String: String] = [:]
    ) {
        var payload: [String: String] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "level": result == "error" ? "error" : "info",
            "component": "app_state",
            "action": action,
            "result": result,
            "request_id": requestID,
            "node_id": String(launchNodeID)
        ]
        for (key, value) in fields {
            payload[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        print(line)
    }

    // MARK: - Harness Actions

    func createRealmTestEnvironment(nodeCount: Int) async {
        let requestID = makeRequestID(action: "harness.init")
        setHarnessBackendCall(command: harnessScriptCommand(subcommand: "init", nodeCount: nodeCount))
        logHarnessEvent(
            action: "harness.init",
            result: "start",
            requestID: requestID,
            fields: ["node_count": String(nodeCount)]
        )
        do {
            let response = try await api.createRealmTestEnvironment(
                nodeCount: nodeCount,
                config: currentHarnessConfig,
                requestID: requestID
            )
            harnessNodeCount = response.nodeCount
            harnessNodes = response.nodes   // empty — Bootstrap Realm creates node.env files
            harnessPhase = .running
            // No log files exist yet; Bootstrap Realm creates them when node.env is written.
            logHarnessEvent(
                action: "harness.init",
                result: "ok",
                requestID: requestID,
                fields: ["node_count": String(response.nodeCount)]
            )
            setHarnessBackendResult("ok: \(response.nodeCount) machine directories created")
            lastErrorMessage = nil
            await refreshHarnessSetupLog()
        } catch {
            logHarnessEvent(
                action: "harness.init",
                result: "error",
                requestID: requestID,
                fields: ["error": formatError(error)]
            )
            setHarnessBackendResult("error:\n\(formatError(error))")
            lastErrorMessage = formatError(error)
        }
    }

    func refreshRealmHarnessNodes(requestID: String? = nil) async {
        let resolvedRequestID = requestID ?? makeRequestID(action: "harness.status")
        setHarnessBackendCall(command: harnessScriptCommand(subcommand: "status", nodeCount: harnessNodeCount))
        do {
            harnessNodes = try await api.realmHarnessNodes(
                nodeCount: harnessNodeCount,
                config: currentHarnessConfig,
                requestID: resolvedRequestID
            )
            if harnessNodes.contains(where: { $0.id == selectedHarnessNodeID }) == false,
               let first = harnessNodes.first {
                selectedHarnessNodeID = first.id
            }
            logHarnessEvent(
                action: "harness.status",
                result: "ok",
                requestID: resolvedRequestID,
                fields: ["node_count": String(harnessNodes.count)]
            )
            setHarnessBackendResult("ok: loaded \(harnessNodes.count) node statuses")
            lastErrorMessage = nil
        } catch {
            logHarnessEvent(
                action: "harness.status",
                result: "error",
                requestID: resolvedRequestID,
                fields: ["error": formatError(error)]
            )
            setHarnessBackendResult("error:\n\(formatError(error))")
            lastErrorMessage = formatError(error)
        }
    }

    func selfJoinRealmHarness(nodeNameOverride: String? = nil) async {
        let requestID = makeRequestID(action: "harness.self_join")
        // self-join always bootstraps node 1 only — nodeCount is not meaningful here.
        setHarnessBackendCall(command: harnessScriptCommand(subcommand: "self-join", nodeCount: 1))
        logHarnessEvent(
            action: "harness.self_join",
            result: "start",
            requestID: requestID,
            fields: [:]
        )
        do {
            let base = currentHarnessConfig
            let config: RealmHarnessCreateConfig
            if let name = nodeNameOverride, !name.isEmpty {
                config = RealmHarnessCreateConfig(
                    realmName: base.realmName,
                    host: base.host,
                    port: base.port,
                    harnessRoot: base.harnessRoot,
                    nodeNamesCSV: base.nodeNamesCSV,
                    logLevel: base.logLevel,
                    bootstrapNodeName: name
                )
            } else {
                config = base
            }
            let response = try await api.selfJoinRealmHarness(
                nodeCount: 1,
                config: config,
                requestID: requestID
            )
            harnessLaunchOutput = response.output
            await refreshRealmHarnessNodes(requestID: requestID)
            logHarnessEvent(
                action: "harness.self_join",
                result: "ok",
                requestID: requestID,
                fields: [:]
            )
            setHarnessBackendResult(response.output.isEmpty ? "ok" : response.output)
            lastErrorMessage = nil
        } catch {
            logHarnessEvent(
                action: "harness.self_join",
                result: "error",
                requestID: requestID,
                fields: ["error": formatError(error)]
            )
            setHarnessBackendResult("error:\n\(formatError(error))")
            lastErrorMessage = formatError(error)
        }
    }

    func inviteOtherRealmHarnessNodes(nodeCount: Int, nodeNameOverrides: [Int: String] = [:]) async {
        let requestID = makeRequestID(action: "harness.join_all")
        setHarnessBackendCall(command: harnessScriptCommand(subcommand: "join-all", nodeCount: nodeCount))
        logHarnessEvent(
            action: "harness.join_all",
            result: "start",
            requestID: requestID,
            fields: ["node_count": String(nodeCount)]
        )
        do {
            let base = currentHarnessConfig
            let config: RealmHarnessCreateConfig
            if !nodeNameOverrides.isEmpty, !harnessMachines.isEmpty {
                let names = harnessMachines.map { machine -> String in
                    if let override = nodeNameOverrides[machine.id], !override.isEmpty {
                        return override
                    }
                    return machine.machineLabel
                }.joined(separator: ",")
                config = RealmHarnessCreateConfig(
                    realmName: base.realmName,
                    host: base.host,
                    port: base.port,
                    harnessRoot: base.harnessRoot,
                    nodeNamesCSV: names.isEmpty ? nil : names,
                    logLevel: base.logLevel
                )
            } else {
                config = base
            }
            let response = try await api.inviteOtherRealmHarnessNodes(
                nodeCount: nodeCount,
                config: config,
                requestID: requestID
            )
            harnessLaunchOutput = response.output
            await refreshRealmHarnessNodes(requestID: requestID)
            logHarnessEvent(
                action: "harness.join_all",
                result: "ok",
                requestID: requestID,
                fields: ["node_count": String(nodeCount)]
            )
            setHarnessBackendResult(response.output.isEmpty ? "ok" : response.output)
            lastErrorMessage = nil
        } catch {
            logHarnessEvent(
                action: "harness.join_all",
                result: "error",
                requestID: requestID,
                fields: ["error": formatError(error)]
            )
            setHarnessBackendResult("error:\n\(formatError(error))")
            lastErrorMessage = formatError(error)
        }
    }

    /// Join only the nodes whose IDs appear in `nodeIDs`, using per-node name overrides where provided.
    /// Node names are passed via SPKI_JOIN_NODE_NAME (not by modifying nodeNamesCSV) so that
    /// machine directory resolution — which relies on the original machine labels — is unaffected.
    func joinSelectedRealmHarnessNodes(nodeIDs: [Int], nodeNameOverrides: [Int: String] = [:]) async {
        let requestID = makeRequestID(action: "harness.join_selected")
        setHarnessBackendCall(command: "join-one \(nodeIDs.map(String.init).joined(separator: " "))")
        logHarnessEvent(
            action: "harness.join_selected",
            result: "start",
            requestID: requestID,
            fields: ["node_ids": nodeIDs.map(String.init).joined(separator: ",")]
        )
        var outputs: [String] = []
        let base = currentHarnessConfig
        for nodeID in nodeIDs {
            let joinName = nodeNameOverrides[nodeID]
            let config = RealmHarnessCreateConfig(
                realmName: base.realmName,
                host: base.host,
                port: base.port,
                harnessRoot: base.harnessRoot,
                nodeNamesCSV: base.nodeNamesCSV,
                logLevel: base.logLevel,
                joinNodeName: joinName
            )
            do {
                let response = try await api.joinSingleRealmHarnessNode(
                    nodeID: nodeID,
                    config: config,
                    requestID: requestID
                )
                if !response.output.isEmpty { outputs.append(response.output) }
            } catch {
                logHarnessEvent(
                    action: "harness.join_selected",
                    result: "error",
                    requestID: requestID,
                    fields: ["node_id": String(nodeID), "error": formatError(error)]
                )
                setHarnessBackendResult("error:\n\(formatError(error))")
                lastErrorMessage = formatError(error)
                return
            }
        }
        harnessLaunchOutput = outputs.joined(separator: "\n")
        await refreshRealmHarnessNodes(requestID: requestID)
        logHarnessEvent(
            action: "harness.join_selected",
            result: "ok",
            requestID: requestID,
            fields: ["node_ids": nodeIDs.map(String.init).joined(separator: ",")]
        )
        setHarnessBackendResult(outputs.isEmpty ? "ok" : outputs.joined(separator: "\n"))
        lastErrorMessage = nil
    }

    func vaultPut(nodeID: Int, path: String, value: String) async -> String? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            let msg = "Vault path is required."
            setHarnessBackendResult("error:\n\(msg)")
            lastErrorMessage = msg
            return nil
        }
        let requestID = makeRequestID(action: "harness.vault_put")
        let command = "\(harnessScriptCommand(subcommand: "vault-put", nodeCount: nodeID)) \(shellQuote(trimmedPath)) \(shellQuote(value))"
        setHarnessBackendCall(command: command)
        logHarnessEvent(
            action: "harness.vault_put",
            result: "start",
            requestID: requestID,
            fields: ["node_id": String(nodeID), "path": trimmedPath]
        )
        do {
            let output = try await api.vaultPut(
                nodeID: nodeID,
                path: trimmedPath,
                value: value,
                config: currentHarnessConfig,
                requestID: requestID
            )
            logHarnessEvent(
                action: "harness.vault_put",
                result: "ok",
                requestID: requestID,
                fields: ["node_id": String(nodeID), "path": trimmedPath]
            )
            setHarnessBackendResult(output.isEmpty ? "ok: vault put complete" : output)
            lastErrorMessage = nil
            await refreshRealmHarnessLog(nodeID: nodeID, requestID: requestID)
            return output
        } catch {
            logHarnessEvent(
                action: "harness.vault_put",
                result: "error",
                requestID: requestID,
                fields: ["node_id": String(nodeID), "path": trimmedPath, "error": formatError(error)]
            )
            setHarnessBackendResult("error:\n\(formatError(error))")
            lastErrorMessage = formatError(error)
            return nil
        }
    }

    func vaultGet(nodeID: Int, path: String) async -> String? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            let msg = "Vault path is required."
            setHarnessBackendResult("error:\n\(msg)")
            lastErrorMessage = msg
            return nil
        }
        let requestID = makeRequestID(action: "harness.vault_get")
        let command = "\(harnessScriptCommand(subcommand: "vault-get", nodeCount: nodeID)) \(shellQuote(trimmedPath))"
        setHarnessBackendCall(command: command)
        logHarnessEvent(
            action: "harness.vault_get",
            result: "start",
            requestID: requestID,
            fields: ["node_id": String(nodeID), "path": trimmedPath]
        )
        do {
            let output = try await api.vaultGet(
                nodeID: nodeID,
                path: trimmedPath,
                config: currentHarnessConfig,
                requestID: requestID
            )
            logHarnessEvent(
                action: "harness.vault_get",
                result: "ok",
                requestID: requestID,
                fields: ["node_id": String(nodeID), "path": trimmedPath]
            )
            setHarnessBackendResult(output.isEmpty ? "ok: vault get complete" : output)
            lastErrorMessage = nil
            await refreshRealmHarnessLog(nodeID: nodeID, requestID: requestID)
            return output
        } catch {
            logHarnessEvent(
                action: "harness.vault_get",
                result: "error",
                requestID: requestID,
                fields: ["node_id": String(nodeID), "path": trimmedPath, "error": formatError(error)]
            )
            setHarnessBackendResult("error:\n\(formatError(error))")
            lastErrorMessage = formatError(error)
            return nil
        }
    }

    func vaultCommit(nodeID: Int) async -> String? {
        let requestID = makeRequestID(action: "harness.vault_commit")
        setHarnessBackendCall(command: harnessScriptCommand(subcommand: "vault-commit", nodeCount: nodeID))
        logHarnessEvent(
            action: "harness.vault_commit",
            result: "start",
            requestID: requestID,
            fields: ["node_id": String(nodeID)]
        )
        do {
            let output = try await api.vaultCommit(
                nodeID: nodeID,
                config: currentHarnessConfig,
                requestID: requestID
            )
            logHarnessEvent(
                action: "harness.vault_commit",
                result: "ok",
                requestID: requestID,
                fields: ["node_id": String(nodeID)]
            )
            setHarnessBackendResult(output.isEmpty ? "ok: vault commit complete" : output)
            lastErrorMessage = nil
            await refreshRealmHarnessLog(nodeID: nodeID, requestID: requestID)
            return output
        } catch {
            logHarnessEvent(
                action: "harness.vault_commit",
                result: "error",
                requestID: requestID,
                fields: ["node_id": String(nodeID), "error": formatError(error)]
            )
            setHarnessBackendResult("error:\n\(formatError(error))")
            lastErrorMessage = formatError(error)
            return nil
        }
    }

    func resetRealmHarness() async {
        let requestID = makeRequestID(action: "harness.reset")
        let config = currentHarnessConfig
        setHarnessBackendCall(command: "\(harnessEnvPrefix(config: config))Scripts/realm-harness.sh stop-all-bg \(harnessNodeCount) && Scripts/realm-harness.sh clean")
        logHarnessEvent(action: "harness.reset", result: "start", requestID: requestID)
        do {
            // Stop first; ignore errors — processes may already be down.
            _ = try? await api.stopRealmHarnessUIs(
                nodeCount: harnessNodeCount,
                config: config,
                requestID: requestID
            )
            let response = try await api.cleanRealmHarness(config: config, requestID: requestID)
            harnessNodes = []
            harnessCurrentLog = ""
            harnessSetupLog = ""
            harnessLaunchOutput = ""
            harnessPhase = .notSetup
            selectedHarnessNodeID = 1
            logHarnessEvent(action: "harness.reset", result: "ok", requestID: requestID)
            setHarnessBackendResult(response.output.isEmpty ? "ok: harness reset" : response.output)
            lastErrorMessage = nil
        } catch {
            logHarnessEvent(
                action: "harness.reset",
                result: "error",
                requestID: requestID,
                fields: ["error": formatError(error)]
            )
            setHarnessBackendResult("error:\n\(formatError(error))")
            lastErrorMessage = formatError(error)
        }
    }

    func refreshHarnessSetupLog() async {
        do {
            harnessSetupLog = try await api.realmHarnessLog(
                maxLines: 200,
                config: currentHarnessConfig,
                requestID: nil
            )
            lastErrorMessage = nil
        } catch {
            harnessSetupLog = "Error loading harness log: \((error as? APIErrorPayload)?.message ?? error.localizedDescription)"
        }
    }

    func refreshRealmHarnessLog(nodeID: Int, requestID: String? = nil) async {
        let resolvedRequestID = requestID ?? makeRequestID(action: "harness.log_tail")

        // nodeID == 0 is the sentinel for the interleaved "Realm (All Nodes)" view.
        if nodeID == 0 {
            setHarnessBackendCall(command: "realm.log (all nodes, interleaved by ts)")
            do {
                harnessCurrentLog = try await api.realmHarnessAllNodesLog(
                    nodes: harnessNodes,
                    maxLines: 500,
                    config: currentHarnessConfig,
                    requestID: resolvedRequestID
                )
                setHarnessBackendResult("ok: interleaved realm log, \(harnessNodes.count) node(s)")
                lastErrorMessage = nil
            } catch {
                setHarnessBackendResult("error:\n\(formatError(error))")
                lastErrorMessage = formatError(error)
            }
            return
        }

        let logRoot = harnessNodes.first(where: { $0.id == nodeID })?.logdir
            ?? "\(currentHarnessConfig.harnessRoot ?? "~/.cyberspace/testbed")/node\(nodeID)/logs"
        setHarnessBackendCall(
            command: "tail -n 200 \(logRoot)/realm.log \(logRoot)/node.log"
        )
        do {
            harnessCurrentLog = try await api.realmHarnessCurrentLog(
                nodeID: nodeID,
                maxLines: 200,
                config: currentHarnessConfig,
                requestID: resolvedRequestID
            )
            setHarnessBackendResult("ok: tailed node \(nodeID) log")
            lastErrorMessage = nil
        } catch {
            logHarnessEvent(
                action: "harness.log_tail",
                result: "error",
                requestID: resolvedRequestID,
                fields: [
                    "node_id": String(nodeID),
                    "error": (error as? APIErrorPayload)?.message ?? error.localizedDescription
                ]
            )
            setHarnessBackendResult("error:\n\(formatError(error))")
            lastErrorMessage = formatError(error)
        }
    }
}
