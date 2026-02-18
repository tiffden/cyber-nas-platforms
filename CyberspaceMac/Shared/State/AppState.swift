import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    // Bump this on each UI rollout so operators can verify they are on the latest binary.
    static let uiVersion = "ui-2026.02.18-r06"

    // MARK: - Harness State

    @Published var harnessNodeCount: Int = 3
    @Published var harnessRealmName: String = "local-realm"
    @Published var harnessHost: String = "127.0.0.1"
    @Published var harnessPort: Int = 7780
    @Published var harnessRootOverride: String = ""
    @Published var harnessNodeNamesCSV: String = ""
    @Published var harnessNodes: [RealmHarnessNodeMetadata] = []
    @Published var selectedHarnessNodeID: Int = 1
    @Published var harnessCurrentLog: String = ""
    @Published var harnessLaunchOutput: String = ""
    @Published var harnessLastBackendCommand: String = ""
    @Published var harnessLastBackendResult: String = ""
    @Published var lastErrorMessage: String?

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

    private func harnessScriptCommand(subcommand: String, nodeCount: Int) -> String {
        let config = currentHarnessConfig
        return "\(harnessEnvPrefix(config: config))spki/macos/swiftui/Scripts/realm-harness.sh \(subcommand) \(nodeCount)"
    }

    private var currentHarnessConfig: RealmHarnessCreateConfig {
        let trimmedRoot = harnessRootOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNodeNames = harnessNodeNamesCSV.trimmingCharacters(in: .whitespacesAndNewlines)
        return RealmHarnessCreateConfig(
            realmName: harnessRealmName.trimmingCharacters(in: .whitespacesAndNewlines),
            host: harnessHost.trimmingCharacters(in: .whitespacesAndNewlines),
            port: harnessPort,
            harnessRoot: trimmedRoot.isEmpty ? nil : trimmedRoot,
            nodeNamesCSV: trimmedNodeNames.isEmpty ? nil : trimmedNodeNames
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
            harnessNodes = response.nodes
            // Default log view to a real node immediately after init so operators see live feedback.
            if let first = response.nodes.first {
                selectedHarnessNodeID = first.id
            }
            await refreshRealmHarnessLog(nodeID: selectedHarnessNodeID, requestID: requestID)
            logHarnessEvent(
                action: "harness.init",
                result: "ok",
                requestID: requestID,
                fields: ["node_count": String(response.nodeCount)]
            )
            setHarnessBackendResult("ok: initialized \(response.nodeCount) nodes")
            lastErrorMessage = nil
        } catch {
            logHarnessEvent(
                action: "harness.init",
                result: "error",
                requestID: requestID,
                fields: ["error": (error as? APIErrorPayload)?.message ?? error.localizedDescription]
            )
            setHarnessBackendResult("error: \((error as? APIErrorPayload)?.message ?? error.localizedDescription)")
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
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
                fields: ["error": (error as? APIErrorPayload)?.message ?? error.localizedDescription]
            )
            setHarnessBackendResult("error: \((error as? APIErrorPayload)?.message ?? error.localizedDescription)")
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func launchRealmHarnessUIs(nodeCount: Int) async {
        let requestID = makeRequestID(action: "harness.start_ui")
        setHarnessBackendCall(command: harnessScriptCommand(subcommand: "ui-all-bg", nodeCount: nodeCount))
        logHarnessEvent(
            action: "harness.start_ui",
            result: "start",
            requestID: requestID,
            fields: ["node_count": String(nodeCount)]
        )
        do {
            let response = try await api.launchRealmHarnessUIs(
                nodeCount: nodeCount,
                config: currentHarnessConfig,
                requestID: requestID
            )
            harnessLaunchOutput = response.output
            logHarnessEvent(
                action: "harness.start_ui",
                result: "ok",
                requestID: requestID,
                fields: ["node_count": String(nodeCount)]
            )
            setHarnessBackendResult(response.output.isEmpty ? "ok" : response.output)
            lastErrorMessage = nil
        } catch {
            logHarnessEvent(
                action: "harness.start_ui",
                result: "error",
                requestID: requestID,
                fields: ["error": (error as? APIErrorPayload)?.message ?? error.localizedDescription]
            )
            setHarnessBackendResult("error: \((error as? APIErrorPayload)?.message ?? error.localizedDescription)")
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func selfJoinRealmHarness(nodeCount: Int) async {
        let requestID = makeRequestID(action: "harness.self_join")
        setHarnessBackendCall(command: harnessScriptCommand(subcommand: "self-join", nodeCount: nodeCount))
        logHarnessEvent(
            action: "harness.self_join",
            result: "start",
            requestID: requestID,
            fields: ["node_count": String(nodeCount)]
        )
        do {
            let response = try await api.selfJoinRealmHarness(
                nodeCount: nodeCount,
                config: currentHarnessConfig,
                requestID: requestID
            )
            harnessLaunchOutput = response.output
            await refreshRealmHarnessNodes(requestID: requestID)
            logHarnessEvent(
                action: "harness.self_join",
                result: "ok",
                requestID: requestID,
                fields: ["node_count": String(nodeCount)]
            )
            setHarnessBackendResult(response.output.isEmpty ? "ok" : response.output)
            lastErrorMessage = nil
        } catch {
            logHarnessEvent(
                action: "harness.self_join",
                result: "error",
                requestID: requestID,
                fields: ["error": (error as? APIErrorPayload)?.message ?? error.localizedDescription]
            )
            setHarnessBackendResult("error: \((error as? APIErrorPayload)?.message ?? error.localizedDescription)")
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func inviteOtherRealmHarnessNodes(nodeCount: Int) async {
        let requestID = makeRequestID(action: "harness.invite")
        setHarnessBackendCall(command: harnessScriptCommand(subcommand: "invite-all", nodeCount: nodeCount))
        logHarnessEvent(
            action: "harness.invite",
            result: "start",
            requestID: requestID,
            fields: ["node_count": String(nodeCount)]
        )
        do {
            let response = try await api.inviteOtherRealmHarnessNodes(
                nodeCount: nodeCount,
                config: currentHarnessConfig,
                requestID: requestID
            )
            harnessLaunchOutput = response.output
            await refreshRealmHarnessNodes(requestID: requestID)
            logHarnessEvent(
                action: "harness.invite",
                result: "ok",
                requestID: requestID,
                fields: ["node_count": String(nodeCount)]
            )
            setHarnessBackendResult(response.output.isEmpty ? "ok" : response.output)
            lastErrorMessage = nil
        } catch {
            logHarnessEvent(
                action: "harness.invite",
                result: "error",
                requestID: requestID,
                fields: ["error": (error as? APIErrorPayload)?.message ?? error.localizedDescription]
            )
            setHarnessBackendResult("error: \((error as? APIErrorPayload)?.message ?? error.localizedDescription)")
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func stopRealmHarnessUIs(nodeCount: Int) async {
        let requestID = makeRequestID(action: "harness.stop_ui")
        setHarnessBackendCall(command: harnessScriptCommand(subcommand: "stop-all-bg", nodeCount: nodeCount))
        logHarnessEvent(
            action: "harness.stop_ui",
            result: "start",
            requestID: requestID,
            fields: ["node_count": String(nodeCount)]
        )
        do {
            let response = try await api.stopRealmHarnessUIs(
                nodeCount: nodeCount,
                config: currentHarnessConfig,
                requestID: requestID
            )
            harnessLaunchOutput = response.output
            logHarnessEvent(
                action: "harness.stop_ui",
                result: "ok",
                requestID: requestID,
                fields: ["node_count": String(nodeCount)]
            )
            setHarnessBackendResult(response.output.isEmpty ? "ok" : response.output)
            lastErrorMessage = nil
        } catch {
            logHarnessEvent(
                action: "harness.stop_ui",
                result: "error",
                requestID: requestID,
                fields: ["error": (error as? APIErrorPayload)?.message ?? error.localizedDescription]
            )
            setHarnessBackendResult("error: \((error as? APIErrorPayload)?.message ?? error.localizedDescription)")
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func refreshRealmHarnessLog(nodeID: Int, requestID: String? = nil) async {
        let resolvedRequestID = requestID ?? makeRequestID(action: "harness.log_tail")
        let root = currentHarnessConfig.harnessRoot ?? "~/.cyberspace/testbed"
        setHarnessBackendCall(
            command: "tail -n 200 \(root)/node\(nodeID)/logs/realm.log \(root)/node\(nodeID)/logs/node.log"
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
            setHarnessBackendResult("error: \((error as? APIErrorPayload)?.message ?? error.localizedDescription)")
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }
}
