import Darwin
import Foundation

struct CLIBridgeAPIClient: ClientAPI {
    private let environment: [String: String]
    private let keyDirectory: URL

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        keyDirectory: URL? = nil
    ) {
        self.environment = environment
        if let keyDirectory {
            self.keyDirectory = keyDirectory
        } else if let keyDir = environment["SPKI_KEY_DIR"], !keyDir.isEmpty {
            self.keyDirectory = URL(fileURLWithPath: keyDir, isDirectory: true)
        } else {
            self.keyDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".spki/keys", isDirectory: true)
        }
    }

    // MARK: - Harness Operations

    func createRealmTestEnvironment(
        nodeCount: Int,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> RealmHarnessInitResponse {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        // Delegate setup to the shell harness — creates machine directories and machine.env files.
        // Realm/node sub-directories are created later at Bootstrap Realm time.
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        _ = try run(
            executable: harnessScript,
            arguments: ["init", String(nodeCount)],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.init"
        )
        // No node.env files exist yet — Bootstrap Realm creates them.
        return RealmHarnessInitResponse(nodeCount: nodeCount, nodes: [])
    }

    func selfJoinRealmHarness(
        nodeCount: Int,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> RealmHarnessLaunchResponse {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        let output = try run(
            executable: harnessScript,
            arguments: ["self-join", String(nodeCount)],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.self_join"
        )
        return RealmHarnessLaunchResponse(nodeCount: nodeCount, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func inviteOtherRealmHarnessNodes(
        nodeCount: Int,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> RealmHarnessLaunchResponse {
        guard nodeCount > 1 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 1", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        let output = try run(
            executable: harnessScript,
            arguments: ["join-all", String(nodeCount)],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.join_all"
        )
        return RealmHarnessLaunchResponse(nodeCount: nodeCount, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func joinSingleRealmHarnessNode(
        nodeID: Int,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> RealmHarnessLaunchResponse {
        guard nodeID >= 2 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeID must be >= 2", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        let output = try run(
            executable: harnessScript,
            arguments: ["join-one", String(nodeID)],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.join_one"
        )
        return RealmHarnessLaunchResponse(nodeCount: 1, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func launchRealmHarnessUIs(
        nodeCount: Int,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> RealmHarnessLaunchResponse {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        // Use the harness wrapper so each UI gets isolated env and its own log file.
        let output = try run(
            executable: harnessScript,
            arguments: ["ui-all-bg", String(nodeCount)],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.ui_all_bg"
        )
        return RealmHarnessLaunchResponse(nodeCount: nodeCount, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func stopRealmHarnessUIs(
        nodeCount: Int,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> RealmHarnessLaunchResponse {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        let output = try run(
            executable: harnessScript,
            arguments: ["stop-all-bg", String(nodeCount)],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.stop_all_bg"
        )
        return RealmHarnessLaunchResponse(nodeCount: nodeCount, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func realmHarnessLog(
        maxLines: Int,
        config: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> String {
        let clamped = max(10, min(5000, maxLines))
        let harnessRoot = realmHarnessRoot(config: config)
        let logURL = harnessRoot.appendingPathComponent("harness.log", isDirectory: false)
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return "No harness log yet.\nExpected: \(logURL.path)"
        }
        let text = try String(contentsOf: logURL, encoding: .utf8)
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.contains("\"action\":\"harness.log_tail\"") }
        return lines.suffix(clamped).joined(separator: "\n")
    }

    func realmHarnessAllNodesLog(
        nodes: [RealmHarnessNodeMetadata],
        maxLines: Int,
        config _: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> String {
        guard !nodes.isEmpty else {
            return "No nodes bootstrapped yet. Bootstrap Realm first."
        }
        let clamped = max(10, min(5000, maxLines))

        // Collect every line from each node's realm.log, tagging with its ISO-8601 ts.
        var tagged: [(ts: String, line: String)] = []
        for node in nodes {
            let logURL = URL(fileURLWithPath: node.logdir, isDirectory: true)
                .appendingPathComponent("realm.log", isDirectory: false)
            guard FileManager.default.fileExists(atPath: logURL.path) else { continue }
            let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
                let ts = extractJSONTimestamp(from: rawLine) ?? ""
                tagged.append((ts: ts, line: rawLine))
            }
        }

        guard !tagged.isEmpty else {
            return "No realm log entries yet across \(nodes.count) node(s)."
        }

        // Lexicographic sort on ISO-8601 ts; entries without a ts use "" and sort
        // before timestamped lines.
        tagged.sort { $0.ts < $1.ts }
        return tagged.suffix(clamped).map(\.line).joined(separator: "\n")
    }

    func cleanRealmHarness(
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> RealmHarnessLaunchResponse {
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        let output = try run(
            executable: harnessScript,
            arguments: ["clean"],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.clean"
        )
        return RealmHarnessLaunchResponse(nodeCount: 0, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func vaultPut(
        nodeID: Int,
        path: String,
        value: String,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> String {
        guard nodeID > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeID must be > 0", details: nil)
        }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "vault path must not be empty", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        let output = try run(
            executable: harnessScript,
            arguments: ["vault-put", String(nodeID), trimmedPath, value],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.vault_put"
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func vaultGet(
        nodeID: Int,
        path: String,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> String {
        guard nodeID > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeID must be > 0", details: nil)
        }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "vault path must not be empty", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        let output = try run(
            executable: harnessScript,
            arguments: ["vault-get", String(nodeID), trimmedPath],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.vault_get"
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func vaultCommit(
        nodeID: Int,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> String {
        guard nodeID > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeID must be > 0", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        let output = try run(
            executable: harnessScript,
            arguments: ["vault-commit", String(nodeID)],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.vault_commit"
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sealCommit(
        nodeID: Int,
        message: String,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> String {
        guard nodeID > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeID must be > 0", details: nil)
        }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "seal commit message must not be empty", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        let output = try run(
            executable: harnessScript,
            arguments: ["seal-commit", String(nodeID), trimmedMessage],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.seal_commit"
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sealRelease(
        nodeID: Int,
        version: String,
        message: String?,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> String {
        guard nodeID > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeID must be > 0", details: nil)
        }
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVersion.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "seal release version must not be empty", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        var args = ["seal-release", String(nodeID), trimmedVersion]
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let output = try run(
            executable: harnessScript,
            arguments: args,
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.seal_release"
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sealVerify(
        nodeID: Int,
        version: String,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> String {
        guard nodeID > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeID must be > 0", details: nil)
        }
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVersion.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "seal verify version must not be empty", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        let output = try run(
            executable: harnessScript,
            arguments: ["seal-verify", String(nodeID), trimmedVersion],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.seal_verify"
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sealArchive(
        nodeID: Int,
        version: String,
        format: String,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> String {
        guard nodeID > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeID must be > 0", details: nil)
        }
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVersion.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "seal archive version must not be empty", details: nil)
        }
        let trimmedFormat = format.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFormat.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "seal archive format must not be empty", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let harnessEnv = harnessEnvironment(config: config)
        let output = try run(
            executable: harnessScript,
            arguments: ["seal-archive", String(nodeID), trimmedVersion, trimmedFormat],
            environment: harnessEnv,
            requestID: requestID,
            action: "harness.seal_archive"
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func realmHarnessNodes(
        nodeCount: Int,
        config: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> [RealmHarnessNodeMetadata] {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        let harnessRoot = realmHarnessRoot(config: config)
        // Resolve machine directory names from the CSV (mirrors resolve_node_name in realm-harness.sh).
        // Each entry is the machineLabel used as the top-level harness directory name.
        let machineNames = parseMachineNames(config: config)
        var nodes: [RealmHarnessNodeMetadata] = []
        nodes.reserveCapacity(nodeCount)

        for id in 1...nodeCount {
            let machineDirName = machineDirectoryName(nodeID: id, machineNames: machineNames)
            let envURL = harnessRoot
                .appendingPathComponent(machineDirName, isDirectory: true)
                .appendingPathComponent("harness-generated", isDirectory: true)
                .appendingPathComponent("node.env", isDirectory: false)
            // node.env is written at Bootstrap Realm time; skip machines not yet bootstrapped.
            guard FileManager.default.fileExists(atPath: envURL.path) else { continue }
            let parsedEnv = try parseNodeEnv(fileURL: envURL)
            let status = derivedNodeStatus(nodeEnvURL: envURL)

            let workdir = parsedEnv["SPKI_REALM_WORKDIR"] ?? ""
            let keydir = parsedEnv["SPKI_KEY_DIR"] ?? ""
            let logdir = resolvedNodeLogDirectory(parsedEnv: parsedEnv)
            let nodeName = parsedEnv["SPKI_NODE_NAME"] ?? "node\(id)"
            let host = parsedEnv["SPKI_JOIN_HOST"] ?? "127.0.0.1"
            let port = Int(parsedEnv["SPKI_NODE_PORT"] ?? "") ?? (7779 + id)
            nodes.append(
                RealmHarnessNodeMetadata(
                    id: id,
                    nodeName: nodeName,
                    envFile: envURL.path,
                    workdir: workdir,
                    keydir: keydir,
                    logdir: logdir,
                    host: host,
                    port: port,
                    status: status,
                    memberCount: 0,
                    policy: "runtime",
                    uuid: parsedEnv["SPKI_NODE_UUID"] ?? ""
                )
            )
        }

        return nodes
    }

    func realmHarnessCurrentLog(
        nodeID: Int,
        maxLines: Int,
        config: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> String {
        guard nodeID > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeID must be > 0", details: nil)
        }
        // Bound the tail size to keep UI refresh cheap even when logs grow large.
        let clamped = max(10, min(5000, maxLines))
        let harnessRoot = realmHarnessRoot(config: config)
        let machineNames = parseMachineNames(config: config)
        let machineDirName = machineDirectoryName(nodeID: nodeID, machineNames: machineNames)
        let envURL = harnessRoot
            .appendingPathComponent(machineDirName, isDirectory: true)
            .appendingPathComponent("node.env", isDirectory: false)
        // node.env is written at Bootstrap Realm time; return a placeholder if it
        // doesn't exist yet so the caller gets informative text rather than an error.
        guard FileManager.default.fileExists(atPath: envURL.path) else {
            return "Node \(nodeID) (\(machineDirName)) not yet bootstrapped.\nRun Bootstrap Realm to initialize."
        }
        let parsedEnv = try parseNodeEnv(fileURL: envURL)
        let resolvedLogPath = resolvedNodeLogDirectory(parsedEnv: parsedEnv)
        let nodeLogsRoot = resolvedLogPath.isEmpty
            ? envURL.deletingLastPathComponent().appendingPathComponent("logs", isDirectory: true)
            : URL(fileURLWithPath: resolvedLogPath, isDirectory: true)
        let realmLogURL = nodeLogsRoot.appendingPathComponent("realm.log", isDirectory: false)
        let nodeLogURL = nodeLogsRoot.appendingPathComponent("node.log", isDirectory: false)

        let fm = FileManager.default
        let hasRealmLog = fm.fileExists(atPath: realmLogURL.path)
        let hasNodeLog = fm.fileExists(atPath: nodeLogURL.path)
        guard hasRealmLog || hasNodeLog else {
            return """
            No per-node logs yet for node \(nodeID).
            Expected files:
            - \(realmLogURL.path)
            - \(nodeLogURL.path)
            """
        }

        var combined: [String] = []
        if hasRealmLog {
            let realmText = try String(contentsOf: realmLogURL, encoding: .utf8)
            combined.append("=== realm.log ===")
            combined.append(
                contentsOf: realmText
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                    .filter { !$0.contains("\"action\":\"harness.log_tail\"") }
            )
        }
        if hasNodeLog {
            let uiText = try String(contentsOf: nodeLogURL, encoding: .utf8)
            if !combined.isEmpty {
                combined.append("")
            }
            combined.append("=== node.log ===")
            combined.append(
                contentsOf: uiText
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                    .filter { !$0.contains("\"action\":\"harness.log_tail\"") }
            )
        }

        return combined.suffix(clamped).joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func derivedNodeStatus(nodeEnvURL: URL) -> String {
        let harnessGeneratedDir = nodeEnvURL.deletingLastPathComponent()
        let pidFile = harnessGeneratedDir.appendingPathComponent("listener.pid", isDirectory: false)
        guard let pidText = try? String(contentsOf: pidFile, encoding: .utf8) else {
            return "joined"
        }
        guard let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else {
            return "joined"
        }
        return isProcessAlive(pid: pid) ? "listening" : "joined"
    }

    private func isProcessAlive(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private func run(
        executable: URL,
        arguments: [String],
        requestID: String? = nil,
        action: String? = nil
    ) throws -> String {
        try run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            requestID: requestID,
            action: action
        )
    }

    private func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        requestID: String? = nil,
        action: String? = nil
    ) throws -> String {
        let started = Date()
        let resolvedRequestID = requestID ?? environment["SPKI_REQUEST_ID"] ?? UUID().uuidString.lowercased()
        let actionName = action ?? executable.lastPathComponent
        logEvent(
            level: "info",
            action: actionName,
            result: "start",
            requestID: resolvedRequestID,
            fields: [
                "command": executable.lastPathComponent,
                "arg_count": String(arguments.count)
            ]
        )

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        var processEnvironment = environment
        if processEnvironment["SPKI_REQUEST_ID"] == nil || processEnvironment["SPKI_REQUEST_ID"]?.isEmpty == true {
            processEnvironment["SPKI_REQUEST_ID"] = resolvedRequestID
        }
        process.environment = processEnvironment
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            logEvent(
                level: "error",
                action: actionName,
                result: "error",
                requestID: resolvedRequestID,
                fields: [
                    "command": executable.lastPathComponent,
                    "status": String(process.terminationStatus),
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1000))
                ]
            )
            throw APIErrorPayload(
                code: "internal_error",
                message: "CLI command failed",
                details: [
                    "command": executable.lastPathComponent,
                    "status": String(process.terminationStatus),
                    "stderr": stderr
                ]
            )
        }

        logEvent(
            level: "info",
            action: actionName,
            result: "ok",
            requestID: resolvedRequestID,
            fields: [
                "command": executable.lastPathComponent,
                "duration_ms": String(Int(Date().timeIntervalSince(started) * 1000)),
                "stdout_bytes": String(stdout.utf8.count),
                "stderr_bytes": String(stderr.utf8.count)
            ]
        )

        return stdout
    }

    private func logEvent(
        level: String,
        action: String,
        result: String,
        requestID: String?,
        fields: [String: String] = [:]
    ) {
        var payload: [String: String] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "level": level,
            "component": "cli_bridge",
            "action": action,
            "result": result,
            "request_id": requestID ?? "n/a"
        ]
        for (key, value) in fields {
            payload[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        guard let encoded = "\(line)\n".data(using: .utf8) else { return }
        FileHandle.standardError.write(encoded)
    }

    private func resolveHarnessScript() throws -> URL {
        if let overridePath = environment["SPKI_REALM_HARNESS_SCRIPT"], !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath)
            if FileManager.default.isExecutableFile(atPath: overrideURL.path) {
                return overrideURL
            }
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let script = cwd.appendingPathComponent("Scripts/realm-harness.sh")
        if FileManager.default.isExecutableFile(atPath: script.path) {
            return script
        }
        throw APIErrorPayload(
            code: "not_found",
            message: "Could not find realm harness script",
            details: ["hint": "Set SPKI_REALM_HARNESS_SCRIPT to Scripts/realm-harness.sh"]
        )
    }

    private func realmHarnessRoot(config: RealmHarnessCreateConfig?) -> URL {
        if let override = config?.harnessRoot, !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let override = environment["SPKI_REALM_HARNESS_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".cyberspace", isDirectory: true)
            .appendingPathComponent("testbed", isDirectory: true)
    }

    private func harnessEnvironment(config: RealmHarnessCreateConfig?) -> [String: String] {
        guard let config else { return environment }
        var merged = environment
        if !config.realmName.isEmpty {
            merged["SPKI_REALM_HARNESS_NAME"] = config.realmName
        }
        if let logLevel = config.logLevel, !logLevel.isEmpty {
            merged["SPKI_LOG_LEVEL"] = logLevel
        }
        if !config.host.isEmpty {
            merged["SPKI_REALM_HARNESS_HOST"] = config.host
        }
        if config.port > 0 {
            merged["SPKI_REALM_HARNESS_PORT"] = String(config.port)
        }
        if let harnessRoot = config.harnessRoot, !harnessRoot.isEmpty {
            // Expand ~ here so the shell receives an absolute path.
            // Bash does not expand tildes inside environment variable assignments.
            merged["SPKI_REALM_HARNESS_ROOT"] = (harnessRoot as NSString).expandingTildeInPath
        }
        if let nodeNamesCSV = config.nodeNamesCSV, !nodeNamesCSV.isEmpty {
            merged["SPKI_REALM_HARNESS_NODE_NAMES"] = nodeNamesCSV
        }
        if let bootstrapNodeName = config.bootstrapNodeName, !bootstrapNodeName.isEmpty {
            merged["SPKI_BOOTSTRAP_NODE_NAME"] = bootstrapNodeName
        }
        if let joinNodeName = config.joinNodeName, !joinNodeName.isEmpty {
            merged["SPKI_JOIN_NODE_NAME"] = joinNodeName
        }
        return merged
    }

    private func parseMachineNames(config: RealmHarnessCreateConfig?) -> [String] {
        config?.nodeNamesCSV?
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
    }

    private func machineDirectoryName(nodeID: Int, machineNames: [String]) -> String {
        let idx = nodeID - 1
        if idx >= 0, idx < machineNames.count, !machineNames[idx].isEmpty {
            return machineNames[idx]
        }
        // Fallback mirrors resolve_node_name in realm-harness.sh when CSV is unset.
        return "node\(nodeID)"
    }

    private func resolvedNodeLogDirectory(parsedEnv: [String: String]) -> String {
        return parsedEnv["SPKI_NODE_LOG_DIR"] ?? ""
    }

    private func extractJSONTimestamp(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ts = object["ts"] as? String else { return nil }
        return ts
    }

    private func parseNodeEnv(fileURL: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw APIErrorPayload(
                code: "not_found",
                message: "Node environment file not found",
                details: ["path": fileURL.path]
            )
        }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        var parsed: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eqIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            // `node.env` values are emitted as quoted strings by the harness script.
            var value = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            parsed[key] = value
        }
        return parsed
    }

}
