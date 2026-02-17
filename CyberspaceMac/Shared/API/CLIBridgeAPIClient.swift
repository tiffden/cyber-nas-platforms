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
        throw unavailable("keys.generate", details: ["name": request.name, "algorithm": request.algorithm])
    }

    func keysGet(_ request: KeyGetRequest) async throws -> KeyGetResponse {
        throw unavailable("keys.get", details: ["name": request.name])
    }

    func certsCreate(_ request: CertCreateRequest) async throws -> CertCreateResponse {
        throw unavailable(
            "certs.create",
            details: [
                "issuer": request.issuerPrincipal,
                "subject": request.subjectPrincipal
            ]
        )
    }

    func certsSign(_ request: CertSignRequest) async throws -> CertSignResponse {
        throw unavailable("certs.sign", details: ["signerKeyName": request.signerKeyName])
    }

    func certsVerify(_ request: CertVerifyRequest) async throws -> CertVerifyResponse {
        throw unavailable("certs.verify", details: nil)
    }

    func authzVerifyChain(_ request: AuthzVerifyChainRequest) async throws -> AuthzVerifyChainResponse {
        throw unavailable("authz.verify_chain", details: ["targetTag": request.targetTag])
    }

    func vaultGet(_ request: VaultGetRequest) async throws -> VaultGetResponse {
        throw unavailable("vault.get", details: ["path": request.path])
    }

    func vaultPut(_ request: VaultPutRequest) async throws -> VaultPutResponse {
        throw unavailable("vault.put", details: ["path": request.path])
    }

    func vaultCommit(_ request: VaultCommitRequest) async throws -> VaultCommitResponse {
        throw unavailable("vault.commit", details: nil)
    }

    func auditQuery(_ request: AuditQueryRequest) async throws -> AuditQueryResponse {
        throw unavailable(
            "audit.query",
            details: ["filter": request.filter, "limit": String(request.limit)]
        )
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
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executable
        process.arguments = arguments
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
