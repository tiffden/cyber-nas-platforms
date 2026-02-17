import Foundation

struct InProcessAPIClient: ClientAPI {
    func call(_ request: APIRequestEnvelope) async throws -> APIResponseEnvelope {
        switch request.method {
        case "system.status":
            return APIResponseEnvelope(
                id: request.id,
                ok: true,
                result: [
                    "uptime": "0s",
                    "status": "ok"
                ],
                error: nil
            )
        case "keys.list":
            return APIResponseEnvelope(
                id: request.id,
                ok: true,
                result: [
                    "count": "2"
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
                    message: "Method not implemented in scaffold",
                    details: ["method": request.method]
                )
            )
        }
    }

    func systemStatus() async throws -> SystemStatus {
        let envelope = try await call(
            APIRequestEnvelope(id: UUID().uuidString, method: "system.status", params: [:])
        )
        guard envelope.ok, let result = envelope.result else {
            throw envelope.error ?? APIErrorPayload(
                code: "internal_error",
                message: "Missing system status payload",
                details: nil
            )
        }
        return SystemStatus(
            status: result["status"] ?? "unknown",
            uptime: result["uptime"] ?? "n/a"
        )
    }

    func keysList() async throws -> KeyList {
        let envelope = try await call(
            APIRequestEnvelope(id: UUID().uuidString, method: "keys.list", params: [:])
        )
        guard envelope.ok else {
            throw envelope.error ?? APIErrorPayload(
                code: "internal_error",
                message: "Failed to load key list",
                details: nil
            )
        }

        return KeyList(
            keys: [
                KeySummary(
                    id: "alice",
                    name: "alice",
                    algorithm: "ed25519",
                    fingerprint: "8730:a3fd:eb16:bc6c:67c0:65c6:6de2:ba83"
                ),
                KeySummary(
                    id: "bob",
                    name: "bob",
                    algorithm: "ed25519",
                    fingerprint: "6b49:ffe7:eadc:f8a5:5d7e:b26c:ef35:7c9d"
                )
            ]
        )
    }

    func keysGenerate(_ request: KeyGenerateRequest) async throws -> KeyGenerateResponse {
        guard !request.name.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "key name is required", details: nil)
        }
        return KeyGenerateResponse(
            key: KeySummary(
                id: request.name,
                name: request.name,
                algorithm: request.algorithm,
                fingerprint: UUID().uuidString.lowercased()
            )
        )
    }

    func keysGet(_ request: KeyGetRequest) async throws -> KeyGetResponse {
        guard !request.name.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "key name is required", details: nil)
        }
        return KeyGetResponse(
            key: KeySummary(
                id: request.name,
                name: request.name,
                algorithm: "ed25519",
                fingerprint: "sample-\(request.name)-fingerprint"
            )
        )
    }

    func certsCreate(_ request: CertCreateRequest) async throws -> CertCreateResponse {
        guard !request.issuerPrincipal.isEmpty, !request.subjectPrincipal.isEmpty else {
            throw APIErrorPayload(
                code: "invalid_argument",
                message: "issuer and subject are required",
                details: nil
            )
        }
        return CertCreateResponse(
            certificateSexp: "(cert (issuer \(request.issuerPrincipal)) (subject \(request.subjectPrincipal)) (tag \(request.tag)))"
        )
    }

    func certsSign(_ request: CertSignRequest) async throws -> CertSignResponse {
        guard !request.certificateSexp.isEmpty, !request.signerKeyName.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "certificate and signer key are required", details: nil)
        }
        return CertSignResponse(signedCertificateSexp: "(signed \(request.certificateSexp))")
    }

    func certsVerify(_ request: CertVerifyRequest) async throws -> CertVerifyResponse {
        guard !request.signedCertificateSexp.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "signed certificate is required", details: nil)
        }
        return CertVerifyResponse(valid: true, reason: "verified in in-process mock")
    }

    func authzVerifyChain(_ request: AuthzVerifyChainRequest) async throws -> AuthzVerifyChainResponse {
        guard !request.targetTag.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "target tag is required", details: nil)
        }
        return AuthzVerifyChainResponse(allowed: true, reason: "delegation chain accepted in mock")
    }

    func vaultGet(_ request: VaultGetRequest) async throws -> VaultGetResponse {
        guard !request.path.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "path is required", details: nil)
        }
        return VaultGetResponse(
            path: request.path,
            dataBase64: Data("demo-vault-data".utf8).base64EncodedString(),
            metadata: ["source": "in-process"]
        )
    }

    func vaultPut(_ request: VaultPutRequest) async throws -> VaultPutResponse {
        guard !request.path.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "path is required", details: nil)
        }
        return VaultPutResponse(path: request.path, revisionHint: "pending-commit")
    }

    func vaultCommit(_ request: VaultCommitRequest) async throws -> VaultCommitResponse {
        guard !request.message.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "commit message is required", details: nil)
        }
        return VaultCommitResponse(commitID: UUID().uuidString)
    }

    func auditQuery(_ request: AuditQueryRequest) async throws -> AuditQueryResponse {
        guard request.limit > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "limit must be > 0", details: nil)
        }
        let entry = AuditEntry(
            id: UUID().uuidString,
            actor: "alice",
            action: "vault.commit",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            context: request.filter.isEmpty ? "sample event" : "filter=\(request.filter)"
        )
        return AuditQueryResponse(entries: [entry])
    }

    func realmStatus() async throws -> RealmStatus {
        RealmStatus(status: "standalone", nodeName: "local-node", policy: "invite-only", memberCount: 1)
    }

    func realmJoin(_ request: RealmJoinRequest) async throws -> RealmJoinResponse {
        guard !request.name.isEmpty, !request.host.isEmpty else {
            throw APIErrorPayload(code: "invalid_argument", message: "name and host are required", details: nil)
        }
        return RealmJoinResponse(joined: true, message: "joined \(request.name) via \(request.host):\(request.port)")
    }
}
