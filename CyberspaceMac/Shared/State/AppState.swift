import Combine
import Foundation

enum AudienceMode: String, CaseIterable, Identifiable {
    case operatorMode = "operator"
    case builderMode = "builder"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .operatorMode: return "Operator"
        case .builderMode: return "Builder"
        }
    }
}

enum AppRoute: String, CaseIterable, Hashable, Identifiable {
    case startHere
    case currentStatus
    case generateIdentityKeys
    case createInitialRealm
    case localHarness
    case issueCertificates
    case inviteJoinRealm
    case testAccess
    case revokeReissue
    case terminal
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startHere: return "Start Here"
        case .currentStatus: return "Current Status"
        case .generateIdentityKeys: return "Generate Identity Keys"
        case .createInitialRealm: return "Create Initial Realm"
        case .localHarness: return "Local Harness"
        case .issueCertificates: return "Issue Certificates"
        case .inviteJoinRealm: return "Invite & Join Realm"
        case .testAccess: return "Test Access"
        case .revokeReissue: return "Revoke & Re-Issue"
        case .terminal: return "Terminal"
        case .help: return "Help"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    private static let audienceModeDefaultsKey = "cyberspace.audienceMode"
    // Bump this on each UI rollout so operators can verify they are on the latest binary.
    static let uiVersion = "ui-2026.02.18-r06"

    @Published var selectedRoute: AppRoute? = .startHere
    @Published var audienceMode: AudienceMode = .operatorMode {
        didSet {
            UserDefaults.standard.set(audienceMode.rawValue, forKey: Self.audienceModeDefaultsKey)
            // Keep selection valid when the route list changes between modes.
            if let selectedRoute, visibleRoutes.contains(selectedRoute) == false {
                self.selectedRoute = .startHere
            }
        }
    }

    @Published var systemStatus = SystemStatus(status: "loading", uptime: "n/a")
    @Published var keys: [KeySummary] = []
    @Published var createdCertificateSexp: String = ""
    @Published var signedCertificateSexp: String = ""
    @Published var certificateVerifyResult: CertVerifyResponse?
    @Published var authzVerifyResult: AuthzVerifyChainResponse?
    @Published var vaultGetResult: VaultGetResponse?
    @Published var vaultPutResult: VaultPutResponse?
    @Published var vaultCommitResult: VaultCommitResponse?
    @Published var auditEntries: [AuditEntry] = []
    @Published var realmStatusValue = RealmStatus(
        status: "loading",
        nodeName: "n/a",
        policy: "n/a",
        memberCount: 0
    )
    @Published var realmJoinResult: RealmJoinResponse?
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
    @Published var hasLoadedBootstrapData = false
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
        // Env override is useful for deterministic launches from make targets and harness scripts.
        if let envMode = environment["SPKI_UI_AUDIENCE"],
           let mode = AudienceMode(rawValue: envMode) {
            self.audienceMode = mode
        } else if let raw = UserDefaults.standard.string(forKey: Self.audienceModeDefaultsKey),
           let mode = AudienceMode(rawValue: raw) {
            self.audienceMode = mode
        }
    }

    var uiInstanceLabel: String {
        if launchNodeID <= 1 {
            return "Main"
        }
        return "Test Client \(launchNodeID - 1)"
    }

    var uiKeyStatusLabel: String {
        keys.isEmpty ? "no key" : "has key pair"
    }

    var uiWindowTitle: String {
        "Cyberspace \(Self.uiVersion) | \(uiInstanceLabel) - status: \(uiKeyStatusLabel)"
    }

    var uiVersionLabel: String {
        Self.uiVersion
    }

    var visibleRoutes: [AppRoute] {
        switch audienceMode {
        case .operatorMode:
            return AppRoute.allCases.filter { $0 != .localHarness }
        case .builderMode:
            return AppRoute.allCases
        }
    }

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
        return RealmHarnessCreateConfig(
            realmName: harnessRealmName.trimmingCharacters(in: .whitespacesAndNewlines),
            host: harnessHost.trimmingCharacters(in: .whitespacesAndNewlines),
            port: harnessPort,
            harnessRoot: trimmedRoot.isEmpty ? nil : trimmedRoot,
            nodeNamesCSV: harnessNodeNamesCSV.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : harnessNodeNamesCSV.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func loadBootstrapDataIfNeeded() async {
        guard !hasLoadedBootstrapData else { return }
        await loadBootstrapData()
    }

    func loadBootstrapData() async {
        do {
            async let status = api.systemStatus()
            async let keyList = api.keysList()
            let (resolvedStatus, resolvedKeys) = try await (status, keyList)
            systemStatus = resolvedStatus
            keys = resolvedKeys.keys
            if let realm = try? await api.realmStatus() {
                realmStatusValue = realm
            }
            lastErrorMessage = nil
            hasLoadedBootstrapData = true
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func generateKey(name: String, algorithm: String = "ed25519") async {
        do {
            let response = try await api.keysGenerate(KeyGenerateRequest(name: name, algorithm: algorithm))
            keys.append(response.key)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func fetchKey(name: String) async {
        do {
            let response = try await api.keysGet(KeyGetRequest(name: name))
            if let idx = keys.firstIndex(where: { $0.name == response.key.name }) {
                keys[idx] = response.key
            } else {
                keys.append(response.key)
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func createCertificate(
        issuerPrincipal: String,
        subjectPrincipal: String,
        tag: String,
        validityNotAfter: String?,
        propagate: Bool
    ) async {
        do {
            let response = try await api.certsCreate(
                CertCreateRequest(
                    issuerPrincipal: issuerPrincipal,
                    subjectPrincipal: subjectPrincipal,
                    tag: tag,
                    validityNotAfter: validityNotAfter,
                    propagate: propagate
                )
            )
            createdCertificateSexp = response.certificateSexp
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func signCertificate(certificateSexp: String, signerKeyName: String, hashAlgorithm: String = "ed25519") async {
        do {
            let response = try await api.certsSign(
                CertSignRequest(
                    certificateSexp: certificateSexp,
                    signerKeyName: signerKeyName,
                    hashAlgorithm: hashAlgorithm
                )
            )
            signedCertificateSexp = response.signedCertificateSexp
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func verifyCertificate(signedCertificateSexp: String, issuerPublicKey: String) async {
        do {
            let response = try await api.certsVerify(
                CertVerifyRequest(
                    signedCertificateSexp: signedCertificateSexp,
                    issuerPublicKey: issuerPublicKey
                )
            )
            certificateVerifyResult = response
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func verifyAuthorizationChain(rootPublicKey: String, signedCertificates: [String], targetTag: String) async {
        do {
            authzVerifyResult = try await api.authzVerifyChain(
                AuthzVerifyChainRequest(
                    rootPublicKey: rootPublicKey,
                    signedCertificates: signedCertificates,
                    targetTag: targetTag
                )
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func queryAudit(filter: String, limit: Int = 50) async {
        do {
            let response = try await api.auditQuery(AuditQueryRequest(filter: filter, limit: limit))
            auditEntries = response.entries
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func refreshRealmStatus() async {
        do {
            realmStatusValue = try await api.realmStatus()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func joinRealm(name: String, host: String, port: Int) async {
        do {
            realmJoinResult = try await api.realmJoin(
                RealmJoinRequest(name: name, host: host, port: port)
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

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

    func vaultPut(path: String, dataBase64: String, metadata: [String: String] = [:]) async {
        do {
            vaultPutResult = try await api.vaultPut(
                VaultPutRequest(path: path, dataBase64: dataBase64, metadata: metadata)
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func vaultGet(path: String) async {
        do {
            vaultGetResult = try await api.vaultGet(VaultGetRequest(path: path))
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func vaultCommit(message: String) async {
        do {
            vaultCommitResult = try await api.vaultCommit(VaultCommitRequest(message: message))
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }
}
