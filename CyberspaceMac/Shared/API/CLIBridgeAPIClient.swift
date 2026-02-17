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

    func call(_ request: APIRequestEnvelope) async throws -> APIResponseEnvelope {
        switch request.method {
        case "system.status":
            let status = try await systemStatus()
            return APIResponseEnvelope(
                id: request.id,
                ok: true,
                result: [
                    "status": status.status,
                    "uptime": status.uptime
                ],
                error: nil
            )
        case "keys.list":
            let keyList = try await keysList()
            return APIResponseEnvelope(
                id: request.id,
                ok: true,
                result: [
                    "count": String(keyList.keys.count)
                ],
                error: nil
            )
        default:
            return APIResponseEnvelope(
                id: request.id,
                ok: false,
                result: nil,
                error: APIErrorPayload(
                    code: "unavailable",
                    message: "Method not implemented in CLI bridge",
                    details: ["method": request.method]
                )
            )
        }
    }

    func systemStatus() async throws -> SystemStatus {
        if let statusExecutable = resolveExecutableIfPresent(
            overrideEnvVar: "SPKI_STATUS_BIN",
            names: ["spki-status", "spki_status.exe"]
        ) {
            if let parsed = try parseSystemStatusFromJSON(executable: statusExecutable) {
                return parsed
            }
            _ = try run(executable: statusExecutable, arguments: ["--help"])
            return localSystemStatus()
        }

        let showExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_SHOW_BIN",
            names: ["spki-show", "spki_show.exe"]
        )
        _ = try run(executable: showExecutable, arguments: ["--help"])
        return localSystemStatus()
    }

    func keysList() async throws -> KeyList {
        let showExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_SHOW_BIN",
            names: ["spki-show", "spki_show.exe"]
        )

        let fm = FileManager.default
        guard fm.fileExists(atPath: keyDirectory.path) else {
            return KeyList(keys: [])
        }

        let urls = try fm.contentsOfDirectory(
            at: keyDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let publicKeyFiles = urls
            .filter { $0.pathExtension == "public" || $0.pathExtension == "pub" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let keys = try publicKeyFiles.map { fileURL in
            let name = fileURL.deletingPathExtension().lastPathComponent

            if let summary = try parseKeySummaryFromJSON(
                executable: showExecutable,
                fileURL: fileURL,
                fallbackName: name
            ) {
                return summary
            }

            let output = try run(executable: showExecutable, arguments: [fileURL.path])
            let fingerprint = parseKeyHash(fromShowOutput: output) ?? "unknown"
            return KeySummary(id: name, name: name, algorithm: "ed25519", fingerprint: fingerprint)
        }

        return KeyList(keys: keys)
    }

    func keysGenerate(_ request: KeyGenerateRequest) async throws -> KeyGenerateResponse {
        guard !request.name.isEmpty else {
            throw APIErrorPayload(
                code: "invalid_argument",
                message: "name is required",
                details: nil
            )
        }
        guard request.algorithm == "ed25519" else {
            throw APIErrorPayload(
                code: "invalid_argument",
                message: "Unsupported algorithm",
                details: ["algorithm": request.algorithm]
            )
        }

        let keygenExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_KEYGEN_BIN",
            names: ["spki-keygen", "spki_keygen.exe"]
        )

        let output = try run(
            executable: keygenExecutable,
            arguments: [
                "--json",
                "--output-dir", keyDirectory.path,
                "--name", request.name
            ]
        )
        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid key generate output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed key generate JSON", details: nil)
        }
        guard (object["kind"] as? String) == "key_generate" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected key generate payload", details: nil)
        }

        let algorithm = object["algorithm"] as? String ?? request.algorithm
        let fingerprint = object["keyHash"] as? String ?? "unknown"
        let key = KeySummary(id: request.name, name: request.name, algorithm: algorithm, fingerprint: fingerprint)
        return KeyGenerateResponse(key: key)
    }

    func keysGet(_ request: KeyGetRequest) async throws -> KeyGetResponse {
        guard !request.name.isEmpty else {
            throw APIErrorPayload(
                code: "invalid_argument",
                message: "name is required",
                details: nil
            )
        }

        let showExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_SHOW_BIN",
            names: ["spki-show", "spki_show.exe"]
        )

        let keyFile = try findKeyFile(named: request.name)
        if let summary = try parseKeySummaryFromJSON(
            executable: showExecutable,
            fileURL: keyFile,
            fallbackName: request.name
        ) {
            return KeyGetResponse(key: summary)
        }

        let output = try run(executable: showExecutable, arguments: [keyFile.path])
        let fingerprint = parseKeyHash(fromShowOutput: output) ?? "unknown"
        return KeyGetResponse(
            key: KeySummary(
                id: request.name,
                name: request.name,
                algorithm: "ed25519",
                fingerprint: fingerprint
            )
        )
    }

    func certsCreate(_ request: CertCreateRequest) async throws -> CertCreateResponse {
        guard !request.issuerPrincipal.isEmpty, !request.subjectPrincipal.isEmpty, !request.tag.isEmpty else {
            throw APIErrorPayload(
                code: "invalid_argument",
                message: "issuerPrincipal, subjectPrincipal, and tag are required",
                details: nil
            )
        }

        let certsExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_CERTS_BIN",
            names: ["spki-certs", "spki_certs.exe"]
        )

        var args = [
            "--json",
            "--create",
            "--issuer-principal", request.issuerPrincipal,
            "--subject-principal", request.subjectPrincipal,
            "--tag", request.tag
        ]
        if let notAfter = request.validityNotAfter, !notAfter.isEmpty {
            args += ["--not-after", notAfter]
        }
        if request.propagate {
            args.append("--propagate")
        }

        let output = try run(executable: certsExecutable, arguments: args)
        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid cert create output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed cert create JSON", details: nil)
        }
        guard (object["kind"] as? String) == "cert_create" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected cert create payload", details: nil)
        }

        return CertCreateResponse(certificateSexp: object["certificateSexp"] as? String ?? "")
    }

    func certsSign(_ request: CertSignRequest) async throws -> CertSignResponse {
        guard !request.certificateSexp.isEmpty, !request.signerKeyName.isEmpty else {
            throw APIErrorPayload(
                code: "invalid_argument",
                message: "certificateSexp and signerKeyName are required",
                details: nil
            )
        }

        let certsExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_CERTS_BIN",
            names: ["spki-certs", "spki_certs.exe"]
        )

        let output = try run(
            executable: certsExecutable,
            arguments: [
                "--json",
                "--sign",
                "--certificate-sexp", request.certificateSexp,
                "--signer-key-name", request.signerKeyName,
                "--hash-alg", request.hashAlgorithm
            ]
        )

        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid cert sign output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed cert sign JSON", details: nil)
        }
        guard (object["kind"] as? String) == "cert_sign" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected cert sign payload", details: nil)
        }

        return CertSignResponse(signedCertificateSexp: object["signedCertificateSexp"] as? String ?? "")
    }

    func certsVerify(_ request: CertVerifyRequest) async throws -> CertVerifyResponse {
        guard !request.signedCertificateSexp.isEmpty, !request.issuerPublicKey.isEmpty else {
            throw APIErrorPayload(
                code: "invalid_argument",
                message: "signedCertificateSexp and issuerPublicKey are required",
                details: nil
            )
        }

        let certsExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_CERTS_BIN",
            names: ["spki-certs", "spki_certs.exe"]
        )

        let output = try run(
            executable: certsExecutable,
            arguments: [
                "--json",
                "--verify",
                "--signed-certificate-sexp", request.signedCertificateSexp,
                "--issuer-public-key", request.issuerPublicKey
            ]
        )

        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid cert verify output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed cert verify JSON", details: nil)
        }
        guard (object["kind"] as? String) == "cert_verify" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected cert verify payload", details: nil)
        }

        return CertVerifyResponse(
            valid: object["valid"] as? Bool ?? false,
            reason: object["reason"] as? String ?? "unknown"
        )
    }

    func authzVerifyChain(_ request: AuthzVerifyChainRequest) async throws -> AuthzVerifyChainResponse {
        guard !request.rootPublicKey.isEmpty, !request.targetTag.isEmpty else {
            throw APIErrorPayload(
                code: "invalid_argument",
                message: "rootPublicKey and targetTag are required",
                details: nil
            )
        }

        let authzExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_AUTHZ_BIN",
            names: ["spki-authz", "spki_authz.exe"]
        )

        var args = [
            "--json",
            "--verify-chain",
            "--root-public-key", request.rootPublicKey,
            "--target-tag", request.targetTag
        ]
        for cert in request.signedCertificates {
            args += ["--signed-certificate", cert]
        }

        let output = try run(executable: authzExecutable, arguments: args)
        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid authz output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed authz verify JSON", details: nil)
        }
        guard (object["kind"] as? String) == "authz_verify_chain" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected authz verify payload", details: nil)
        }

        return AuthzVerifyChainResponse(
            allowed: object["allowed"] as? Bool ?? false,
            reason: object["reason"] as? String ?? "unknown"
        )
    }

    func vaultGet(_ request: VaultGetRequest) async throws -> VaultGetResponse {
        guard !request.path.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "path is required", details: nil)
        }

        let vaultExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_VAULT_BIN",
            names: ["spki-vault", "spki_vault.exe"]
        )

        let output = try run(
            executable: vaultExecutable,
            arguments: ["--json", "--get", "--path", request.path]
        )

        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid vault get output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed vault get JSON", details: nil)
        }
        guard (object["kind"] as? String) == "vault_get" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected vault get payload", details: nil)
        }

        let metadata = object["metadata"] as? [String: String] ?? [:]
        return VaultGetResponse(
            path: object["path"] as? String ?? request.path,
            dataBase64: object["dataBase64"] as? String ?? "",
            metadata: metadata
        )
    }

    func vaultPut(_ request: VaultPutRequest) async throws -> VaultPutResponse {
        guard !request.path.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "path is required", details: nil)
        }
        guard !request.dataBase64.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "dataBase64 is required", details: nil)
        }

        let vaultExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_VAULT_BIN",
            names: ["spki-vault", "spki_vault.exe"]
        )

        let output = try run(
            executable: vaultExecutable,
            arguments: ["--json", "--put", "--path", request.path, "--data-base64", request.dataBase64]
        )

        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid vault put output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed vault put JSON", details: nil)
        }
        guard (object["kind"] as? String) == "vault_put" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected vault put payload", details: nil)
        }

        return VaultPutResponse(
            path: object["path"] as? String ?? request.path,
            revisionHint: object["revisionHint"] as? String ?? "unknown"
        )
    }

    func vaultCommit(_ request: VaultCommitRequest) async throws -> VaultCommitResponse {
        guard !request.message.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "commit message is required", details: nil)
        }

        let vaultExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_VAULT_BIN",
            names: ["spki-vault", "spki_vault.exe"]
        )

        let output = try run(
            executable: vaultExecutable,
            arguments: ["--json", "--commit", "--message", request.message]
        )

        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid vault commit output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed vault commit JSON", details: nil)
        }
        guard (object["kind"] as? String) == "vault_commit" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected vault commit payload", details: nil)
        }

        return VaultCommitResponse(commitID: object["commitID"] as? String ?? "unknown")
    }

    func auditQuery(_ request: AuditQueryRequest) async throws -> AuditQueryResponse {
        guard request.limit > 0 else {
            throw APIErrorPayload(
                code: "invalid_argument",
                message: "limit must be > 0",
                details: ["limit": String(request.limit)]
            )
        }

        let auditExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_AUDIT_BIN",
            names: ["spki-audit", "spki_audit.exe"]
        )

        let output = try run(
            executable: auditExecutable,
            arguments: [
                "--json",
                "--query",
                "--filter", request.filter,
                "--limit", String(request.limit)
            ]
        )

        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid audit output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed audit query JSON", details: nil)
        }
        guard (object["kind"] as? String) == "audit_query" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected audit query payload", details: nil)
        }

        let entries = (object["entries"] as? [[String: Any]] ?? []).map { item in
            AuditEntry(
                id: item["id"] as? String ?? UUID().uuidString,
                actor: item["actor"] as? String ?? "unknown",
                action: item["action"] as? String ?? "unknown",
                timestamp: item["timestamp"] as? String ?? "",
                context: item["context"] as? String ?? ""
            )
        }

        return AuditQueryResponse(entries: entries)
    }

    func realmStatus() async throws -> RealmStatus {
        let realmExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_REALM_BIN",
            names: ["spki-realm", "spki_realm.exe"]
        )

        let output = try run(executable: realmExecutable, arguments: ["--json", "--status"])
        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid realm status output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed realm status JSON", details: nil)
        }
        guard (object["kind"] as? String) == "realm_status" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected realm status payload", details: nil)
        }

        return RealmStatus(
            status: object["status"] as? String ?? "unknown",
            nodeName: object["nodeName"] as? String ?? "unknown",
            policy: object["policy"] as? String ?? "unknown",
            memberCount: object["memberCount"] as? Int ?? 0
        )
    }

    func realmJoin(_ request: RealmJoinRequest) async throws -> RealmJoinResponse {
        guard !request.name.isEmpty, !request.host.isEmpty else {
            throw APIErrorPayload(
                code: "invalid_argument",
                message: "name and host are required",
                details: ["name": request.name, "host": request.host]
            )
        }

        let realmExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_REALM_BIN",
            names: ["spki-realm", "spki_realm.exe"]
        )

        let output = try run(
            executable: realmExecutable,
            arguments: [
                "--json",
                "--join",
                "--name", request.name,
                "--host", request.host,
                "--port", String(request.port)
            ]
        )

        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid realm join output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed realm join JSON", details: nil)
        }
        guard (object["kind"] as? String) == "realm_join" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected realm join payload", details: nil)
        }

        return RealmJoinResponse(
            joined: object["joined"] as? Bool ?? false,
            message: object["message"] as? String ?? "unknown"
        )
    }

    func createRealmTestEnvironment(nodeCount: Int) async throws -> RealmHarnessInitResponse {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        // Delegate setup to the shell harness so UI/API use the same node bootstrap path as CLI workflows.
        let harnessScript = try resolveHarnessScript()
        _ = try run(executable: harnessScript, arguments: ["init", String(nodeCount)])
        let nodes = try await realmHarnessNodes(nodeCount: nodeCount)
        return RealmHarnessInitResponse(nodeCount: nodeCount, nodes: nodes)
    }

    func launchRealmHarnessUIs(nodeCount: Int) async throws -> RealmHarnessLaunchResponse {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        // Use the harness wrapper so each UI gets isolated env and its own log file.
        let output = try run(executable: harnessScript, arguments: ["ui-all-bg", String(nodeCount)])
        return RealmHarnessLaunchResponse(nodeCount: nodeCount, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func stopRealmHarnessUIs(nodeCount: Int) async throws -> RealmHarnessLaunchResponse {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        let harnessScript = try resolveHarnessScript()
        let output = try run(executable: harnessScript, arguments: ["stop-all-bg", String(nodeCount)])
        return RealmHarnessLaunchResponse(nodeCount: nodeCount, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func realmHarnessNodes(nodeCount: Int) async throws -> [RealmHarnessNodeMetadata] {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        let harnessRoot = realmHarnessRoot()
        let realmExecutable = try resolveExecutable(
            overrideEnvVar: "SPKI_REALM_BIN",
            names: ["spki-realm", "spki_realm.exe"]
        )
        var nodes: [RealmHarnessNodeMetadata] = []
        nodes.reserveCapacity(nodeCount)

        for id in 1...nodeCount {
            let envURL = harnessRoot
                .appendingPathComponent("node\(id)", isDirectory: true)
                .appendingPathComponent("node.env", isDirectory: false)
            let parsedEnv = try parseNodeEnv(fileURL: envURL)

            var mergedEnv = environment
            for (key, value) in parsedEnv {
                mergedEnv[key] = value
            }

            // Query status with each node's env injected so metadata reflects that node's isolated state.
            let output = try run(
                executable: realmExecutable,
                arguments: ["--json", "--status"],
                environment: mergedEnv
            )
            let status = try parseRealmStatusOutput(output)

            let workdir = parsedEnv["SPKI_REALM_WORKDIR"] ?? ""
            let keydir = parsedEnv["SPKI_KEY_DIR"] ?? ""
            let host = parsedEnv["SPKI_JOIN_HOST"] ?? "127.0.0.1"
            let port = Int(parsedEnv["SPKI_NODE_PORT"] ?? "") ?? (7779 + id)
            nodes.append(
                RealmHarnessNodeMetadata(
                    id: id,
                    envFile: envURL.path,
                    workdir: workdir,
                    keydir: keydir,
                    host: host,
                    port: port,
                    status: status.status,
                    memberCount: status.memberCount
                )
            )
        }

        return nodes
    }

    func realmHarnessCurrentLog(nodeID: Int, maxLines: Int) async throws -> String {
        guard nodeID > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeID must be > 0", details: nil)
        }
        // Bound the tail size to keep UI refresh cheap even when logs grow large.
        let clamped = max(10, min(5000, maxLines))
        let logURL = realmHarnessRoot()
            .appendingPathComponent("node\(nodeID)", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("ui.log", isDirectory: false)

        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return "No log file yet at \(logURL.path).\nLaunch UI for this node first."
        }
        let text = try String(contentsOf: logURL, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = lines.suffix(clamped).joined(separator: "\n")
        return String(tail)
    }

    private func resolveExecutable(
        overrideEnvVar: String,
        names: [String]
    ) throws -> URL {
        if let overridePath = environment[overrideEnvVar], !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath)
            if FileManager.default.isExecutableFile(atPath: overrideURL.path) {
                return overrideURL
            }
        }

        if let path = environment["PATH"], !path.isEmpty {
            for dir in path.split(separator: ":") {
                for name in names {
                    let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
                    if FileManager.default.isExecutableFile(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
        }

        throw APIErrorPayload(
            code: "not_found",
            message: "Could not find SPKI executable",
            details: ["names": names.joined(separator: ",")]
        )
    }

    private func resolveExecutableIfPresent(
        overrideEnvVar: String,
        names: [String]
    ) -> URL? {
        if let overridePath = environment[overrideEnvVar], !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath)
            if FileManager.default.isExecutableFile(atPath: overrideURL.path) {
                return overrideURL
            }
            return nil
        }

        if let path = environment["PATH"], !path.isEmpty {
            for dir in path.split(separator: ":") {
                for name in names {
                    let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
                    if FileManager.default.isExecutableFile(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    private func run(executable: URL, arguments: [String]) throws -> String {
        try run(executable: executable, arguments: arguments, environment: environment)
    }

    private func run(executable: URL, arguments: [String], environment: [String: String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
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

        return stdout
    }

    private func resolveHarnessScript() throws -> URL {
        if let overridePath = environment["SPKI_REALM_HARNESS_SCRIPT"], !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath)
            if FileManager.default.isExecutableFile(atPath: overrideURL.path) {
                return overrideURL
            }
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates = [
            cwd.appendingPathComponent("Scripts/realm-harness.sh"),
            cwd.appendingPathComponent("macos/swiftui/Scripts/realm-harness.sh"),
            cwd.appendingPathComponent("spki/macos/swiftui/Scripts/realm-harness.sh")
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw APIErrorPayload(
            code: "not_found",
            message: "Could not find realm harness script",
            details: ["hint": "Set SPKI_REALM_HARNESS_SCRIPT to Scripts/realm-harness.sh"]
        )
    }

    private func realmHarnessRoot() -> URL {
        if let override = environment["SPKI_REALM_HARNESS_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent(".realm-harness", isDirectory: true)
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

    private func parseRealmStatusOutput(_ output: String) throws -> RealmStatus {
        guard let data = output.data(using: .utf8) else {
            throw APIErrorPayload(code: "internal_error", message: "Invalid realm status output encoding", details: nil)
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            throw APIErrorPayload(code: "internal_error", message: "Malformed realm status JSON", details: nil)
        }
        guard (object["kind"] as? String) == "realm_status" else {
            throw APIErrorPayload(code: "internal_error", message: "Unexpected realm status payload", details: nil)
        }
        return RealmStatus(
            status: object["status"] as? String ?? "unknown",
            nodeName: object["nodeName"] as? String ?? "unknown",
            policy: object["policy"] as? String ?? "unknown",
            memberCount: object["memberCount"] as? Int ?? 0
        )
    }

    private func parseKeySummaryFromJSON(
        executable: URL,
        fileURL: URL,
        fallbackName: String
    ) throws -> KeySummary? {
        let output: String
        do {
            output = try run(executable: executable, arguments: ["--json", fileURL.path])
        } catch {
            return nil
        }

        guard let data = output.data(using: .utf8) else { return nil }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let object = rawObject as? [String: Any] else { return nil }

        guard let kind = object["kind"] as? String, kind.contains("key") else { return nil }
        let keyHash = object["keyHash"] as? String ?? "unknown"
        let algorithm = object["algorithm"] as? String ?? "ed25519"
        let name = object["name"] as? String ?? fallbackName

        return KeySummary(
            id: name,
            name: name,
            algorithm: algorithm,
            fingerprint: keyHash
        )
    }

    private func parseSystemStatusFromJSON(executable: URL) throws -> SystemStatus? {
        let output = try run(executable: executable, arguments: ["--json"])
        guard let data = output.data(using: .utf8) else { return nil }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let object = rawObject as? [String: Any] else { return nil }
        guard let kind = object["kind"] as? String, kind == "system_status" else { return nil }
        guard let status = object["status"] as? String else { return nil }

        if let uptimeSeconds = object["uptimeSeconds"] as? Int {
            return SystemStatus(status: status, uptime: formatUptime(seconds: uptimeSeconds))
        }

        if let uptimeDouble = object["uptimeSeconds"] as? Double {
            return SystemStatus(status: status, uptime: formatUptime(seconds: Int(uptimeDouble)))
        }

        if let uptimeString = object["uptime"] as? String, !uptimeString.isEmpty {
            return SystemStatus(status: status, uptime: uptimeString)
        }

        return SystemStatus(status: status, uptime: "n/a")
    }

    private func parseKeyHash(fromShowOutput output: String) -> String? {
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("Key hash:") {
                return line.replacingOccurrences(of: "Key hash:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func findKeyFile(named name: String) throws -> URL {
        let fm = FileManager.default
        let candidates = [
            keyDirectory.appendingPathComponent("\(name).public"),
            keyDirectory.appendingPathComponent("\(name).pub")
        ]
        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        throw APIErrorPayload(
            code: "not_found",
            message: "key not found",
            details: ["name": name, "keyDirectory": keyDirectory.path]
        )
    }

    private func formatUptime(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3600 {
            return "\(seconds / 60)m \(seconds % 60)s"
        }
        if seconds < 86_400 {
            return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
        }
        return "\(seconds / 86_400)d \((seconds % 86_400) / 3600)h"
    }

    private func localSystemStatus() -> SystemStatus {
        let uptimeSeconds = Int(ProcessInfo.processInfo.systemUptime)
        return SystemStatus(status: "ok", uptime: formatUptime(seconds: uptimeSeconds))
    }

    private func unavailable(_ method: String, details: [String: String]?) -> APIErrorPayload {
        APIErrorPayload(
            code: "unavailable",
            message: "Method not implemented in CLI bridge",
            details: details?.merging(["method": method]) { current, _ in current } ?? ["method": method]
        )
    }
}
