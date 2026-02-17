import XCTest
@testable import CyberspaceMac

final class CyberspaceMacUnitTests: XCTestCase {
    func testInProcessAPIClientSystemStatus() async throws {
        let client = InProcessAPIClient()
        let response = try await client.systemStatus()
        XCTAssertEqual(response.status, "ok")
    }

    func testCLIBridgeKeysListParsesJSONWhenAvailable() async throws {
        let fixture = try CLITestFixture()
        let showExe = try fixture.writeExecutable(
            named: "spki-show",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--help" ]; then
              exit 0
            fi
            if [ "$1" = "--json" ]; then
              echo '{"kind":"public_key","algorithm":"ed448","keyHash":"json-hash-123","isPrivate":false}'
              exit 0
            fi
            echo 'Key hash: legacy-should-not-be-used'
            """
        )
        try fixture.writePublicKey(named: "alice.public")

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_SHOW_BIN": showExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let result = try await client.keysList()
        XCTAssertEqual(result.keys.count, 1)
        XCTAssertEqual(result.keys.first?.name, "alice")
        XCTAssertEqual(result.keys.first?.algorithm, "ed448")
        XCTAssertEqual(result.keys.first?.fingerprint, "json-hash-123")
    }

    func testCLIBridgeKeysListFallsBackWhenJSONMalformed() async throws {
        let fixture = try CLITestFixture()
        let showExe = try fixture.writeExecutable(
            named: "spki-show",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--help" ]; then
              exit 0
            fi
            if [ "$1" = "--json" ]; then
              echo 'not-json'
              exit 0
            fi
            echo 'Key hash: legacy-fallback-hash'
            """
        )
        try fixture.writePublicKey(named: "bob.public")

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_SHOW_BIN": showExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let result = try await client.keysList()
        XCTAssertEqual(result.keys.count, 1)
        XCTAssertEqual(result.keys.first?.name, "bob")
        XCTAssertEqual(result.keys.first?.algorithm, "ed25519")
        XCTAssertEqual(result.keys.first?.fingerprint, "legacy-fallback-hash")
    }

    func testCLIBridgeKeysGenerateParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let keygenExe = try fixture.writeExecutable(
            named: "spki-keygen",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "--output-dir" ] && [ "$4" = "--name" ] && [ "$5" = "alice" ]; then
              echo '{"kind":"key_generate","name":"alice","algorithm":"ed25519","publicKeyPath":"'$3'/alice.public","privateKeyPath":"'$3'/alice.private","keyHash":"generated-hash"}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 15
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_KEYGEN_BIN": keygenExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let result = try await client.keysGenerate(KeyGenerateRequest(name: "alice", algorithm: "ed25519"))
        XCTAssertEqual(result.key.name, "alice")
        XCTAssertEqual(result.key.algorithm, "ed25519")
        XCTAssertEqual(result.key.fingerprint, "generated-hash")
    }

    func testCLIBridgeKeysGenerateRejectsUnsupportedAlgorithm() async throws {
        let fixture = try CLITestFixture()
        let keygenExe = try fixture.writeExecutable(
            named: "spki-keygen",
            scriptBody: """
            #!/bin/sh
            exit 0
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_KEYGEN_BIN": keygenExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        do {
            _ = try await client.keysGenerate(KeyGenerateRequest(name: "alice", algorithm: "rsa"))
            XCTFail("Expected invalid_argument for unsupported algorithm")
        } catch let error as APIErrorPayload {
            XCTAssertEqual(error.code, "invalid_argument")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCLIBridgeKeysGetParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let showExe = try fixture.writeExecutable(
            named: "spki-show",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "\(fixture.keyDirectoryURL.path)/carol.public" ]; then
              echo '{"kind":"public_key","algorithm":"ed25519","keyHash":"carol-hash","isPrivate":false}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 16
            """
        )
        try fixture.writePublicKey(named: "carol.public")

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_SHOW_BIN": showExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let result = try await client.keysGet(KeyGetRequest(name: "carol"))
        XCTAssertEqual(result.key.name, "carol")
        XCTAssertEqual(result.key.algorithm, "ed25519")
        XCTAssertEqual(result.key.fingerprint, "carol-hash")
    }

    func testCLIBridgeKeysGetReturnsNotFoundWhenKeyMissing() async throws {
        let fixture = try CLITestFixture()
        let showExe = try fixture.writeExecutable(
            named: "spki-show",
            scriptBody: """
            #!/bin/sh
            exit 0
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_SHOW_BIN": showExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        do {
            _ = try await client.keysGet(KeyGetRequest(name: "missing"))
            XCTFail("Expected not_found for unknown key")
        } catch let error as APIErrorPayload {
            XCTAssertEqual(error.code, "not_found")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCLIBridgeSystemStatusThrowsWhenExecutableMissing() async {
        let client = CLIBridgeAPIClient(
            environment: ["PATH": ""],
            keyDirectory: FileManager.default.temporaryDirectory
        )

        do {
            _ = try await client.systemStatus()
            XCTFail("Expected not_found error when spki-show is unavailable")
        } catch let error as APIErrorPayload {
            XCTAssertEqual(error.code, "not_found")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCLIBridgeSystemStatusParsesJSONWhenAvailable() async throws {
        let fixture = try CLITestFixture()
        let statusExe = try fixture.writeExecutable(
            named: "spki-status",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ]; then
              echo '{"kind":"system_status","status":"ok","version":"1.2.3","uptimeSeconds":3661,"timestamp":"2026-02-16T23:10:00Z"}'
              exit 0
            fi
            if [ "$1" = "--help" ]; then
              exit 0
            fi
            exit 0
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_STATUS_BIN": statusExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let status = try await client.systemStatus()
        XCTAssertEqual(status.status, "ok")
        XCTAssertEqual(status.uptime, "1h 1m")
    }

    func testCLIBridgeSystemStatusFallsBackWhenJSONMalformed() async throws {
        let fixture = try CLITestFixture()
        let statusExe = try fixture.writeExecutable(
            named: "spki-status",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ]; then
              echo 'not-json'
              exit 0
            fi
            if [ "$1" = "--help" ]; then
              exit 0
            fi
            exit 0
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_STATUS_BIN": statusExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let status = try await client.systemStatus()
        XCTAssertEqual(status.status, "ok")
        XCTAssertFalse(status.uptime.isEmpty)
    }

    func testCLIBridgeSystemStatusMapsNonZeroExitToAPIError() async throws {
        let fixture = try CLITestFixture()
        let statusExe = try fixture.writeExecutable(
            named: "spki-status",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ]; then
              echo 'status command failed' >&2
              exit 17
            fi
            if [ "$1" = "--help" ]; then
              exit 0
            fi
            exit 0
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_STATUS_BIN": statusExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        do {
            _ = try await client.systemStatus()
            XCTFail("Expected internal_error when status command returns non-zero")
        } catch let error as APIErrorPayload {
            XCTAssertEqual(error.code, "internal_error")
            XCTAssertEqual(error.details?["status"], "17")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCLIBridgeRealmStatusParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let realmExe = try fixture.writeExecutable(
            named: "spki-realm",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "--status" ]; then
              echo '{"kind":"realm_status","status":"joined","nodeName":"node-1","policy":"threshold","memberCount":4}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 9
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_REALM_BIN": realmExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let status = try await client.realmStatus()
        XCTAssertEqual(status.status, "joined")
        XCTAssertEqual(status.nodeName, "node-1")
        XCTAssertEqual(status.policy, "threshold")
        XCTAssertEqual(status.memberCount, 4)
    }

    func testCLIBridgeRealmJoinParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let realmExe = try fixture.writeExecutable(
            named: "spki-realm",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "--join" ] && [ "$3" = "--name" ] && [ "$4" = "library-realm" ] && [ "$5" = "--host" ] && [ "$6" = "127.0.0.1" ] && [ "$7" = "--port" ] && [ "$8" = "7780" ]; then
              echo '{"kind":"realm_join","joined":true,"message":"joined library-realm via 127.0.0.1:7780"}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 8
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_REALM_BIN": realmExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let response = try await client.realmJoin(
            RealmJoinRequest(name: "library-realm", host: "127.0.0.1", port: 7780)
        )
        XCTAssertTrue(response.joined)
        XCTAssertTrue(response.message.contains("library-realm"))
    }

    func testCLIBridgeAuditQueryParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let auditExe = try fixture.writeExecutable(
            named: "spki-audit",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "--query" ] && [ "$3" = "--filter" ] && [ "$4" = "actor=alice" ] && [ "$5" = "--limit" ] && [ "$6" = "25" ]; then
              echo '{"kind":"audit_query","entries":[{"id":"evt-1","actor":"alice","action":"vault.commit","timestamp":"2026-02-16T23:10:00Z","context":"filter=actor=alice"}]}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 7
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_AUDIT_BIN": auditExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let response = try await client.auditQuery(AuditQueryRequest(filter: "actor=alice", limit: 25))
        XCTAssertEqual(response.entries.count, 1)
        XCTAssertEqual(response.entries.first?.id, "evt-1")
        XCTAssertEqual(response.entries.first?.actor, "alice")
        XCTAssertEqual(response.entries.first?.action, "vault.commit")
    }

    func testCLIBridgeAuditQueryRejectsInvalidLimit() async throws {
        let fixture = try CLITestFixture()
        let auditExe = try fixture.writeExecutable(
            named: "spki-audit",
            scriptBody: """
            #!/bin/sh
            exit 0
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_AUDIT_BIN": auditExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        do {
            _ = try await client.auditQuery(AuditQueryRequest(filter: "", limit: 0))
            XCTFail("Expected invalid_argument for non-positive limit")
        } catch let error as APIErrorPayload {
            XCTAssertEqual(error.code, "invalid_argument")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCLIBridgeVaultGetParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let vaultExe = try fixture.writeExecutable(
            named: "spki-vault",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "--get" ] && [ "$3" = "--path" ] && [ "$4" = "/library/demo.txt" ]; then
              echo '{"kind":"vault_get","path":"/library/demo.txt","dataBase64":"aGVsbG8=","metadata":{"source":"test"}}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 6
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_VAULT_BIN": vaultExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let response = try await client.vaultGet(VaultGetRequest(path: "/library/demo.txt"))
        XCTAssertEqual(response.path, "/library/demo.txt")
        XCTAssertEqual(response.dataBase64, "aGVsbG8=")
        XCTAssertEqual(response.metadata["source"], "test")
    }

    func testCLIBridgeVaultPutParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let vaultExe = try fixture.writeExecutable(
            named: "spki-vault",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "--put" ] && [ "$3" = "--path" ] && [ "$4" = "/library/demo.txt" ] && [ "$5" = "--data-base64" ] && [ "$6" = "aGVsbG8=" ]; then
              echo '{"kind":"vault_put","path":"/library/demo.txt","revisionHint":"pending-commit"}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 5
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_VAULT_BIN": vaultExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let response = try await client.vaultPut(
            VaultPutRequest(path: "/library/demo.txt", dataBase64: "aGVsbG8=", metadata: [:])
        )
        XCTAssertEqual(response.path, "/library/demo.txt")
        XCTAssertEqual(response.revisionHint, "pending-commit")
    }

    func testCLIBridgeVaultCommitParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let vaultExe = try fixture.writeExecutable(
            named: "spki-vault",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "--commit" ] && [ "$3" = "--message" ] && [ "$4" = "UI commit" ]; then
              echo '{"kind":"vault_commit","commitID":"abc123"}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 4
            """
        )

        let client = CLIBridgeAPIClient(
            environment: [
                "SPKI_VAULT_BIN": vaultExe.path,
                "PATH": ""
            ],
            keyDirectory: fixture.keyDirectoryURL
        )

        let response = try await client.vaultCommit(VaultCommitRequest(message: "UI commit"))
        XCTAssertEqual(response.commitID, "abc123")
    }

    func testCLIBridgeCertsCreateParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let certsExe = try fixture.writeExecutable(
            named: "spki-certs",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "--create" ] && [ "$3" = "--issuer-principal" ] && [ "$4" = "alice" ] && [ "$5" = "--subject-principal" ] && [ "$6" = "bob" ] && [ "$7" = "--tag" ] && [ "$8" = "(read /library)" ] && [ "$9" = "--propagate" ]; then
              echo '{"kind":"cert_create","certificateSexp":"(cert demo)"}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 13
            """
        )

        let client = CLIBridgeAPIClient(
            environment: ["SPKI_CERTS_BIN": certsExe.path, "PATH": ""],
            keyDirectory: fixture.keyDirectoryURL
        )

        let response = try await client.certsCreate(
            CertCreateRequest(
                issuerPrincipal: "alice",
                subjectPrincipal: "bob",
                tag: "(read /library)",
                validityNotAfter: nil,
                propagate: true
            )
        )
        XCTAssertEqual(response.certificateSexp, "(cert demo)")
    }

    func testCLIBridgeCertsSignParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let certsExe = try fixture.writeExecutable(
            named: "spki-certs",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "--sign" ] && [ "$3" = "--certificate-sexp" ] && [ "$4" = "(cert demo)" ] && [ "$5" = "--signer-key-name" ] && [ "$6" = "alice" ] && [ "$7" = "--hash-alg" ] && [ "$8" = "ed25519" ]; then
              echo '{"kind":"cert_sign","signedCertificateSexp":"(signed demo)"}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 12
            """
        )

        let client = CLIBridgeAPIClient(
            environment: ["SPKI_CERTS_BIN": certsExe.path, "PATH": ""],
            keyDirectory: fixture.keyDirectoryURL
        )

        let response = try await client.certsSign(
            CertSignRequest(
                certificateSexp: "(cert demo)",
                signerKeyName: "alice",
                hashAlgorithm: "ed25519"
            )
        )
        XCTAssertEqual(response.signedCertificateSexp, "(signed demo)")
    }

    func testCLIBridgeCertsVerifyParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let certsExe = try fixture.writeExecutable(
            named: "spki-certs",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "--verify" ] && [ "$3" = "--signed-certificate-sexp" ] && [ "$4" = "(signed demo)" ] && [ "$5" = "--issuer-public-key" ] && [ "$6" = "issuer-pub" ]; then
              echo '{"kind":"cert_verify","valid":true,"reason":"verified"}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 11
            """
        )

        let client = CLIBridgeAPIClient(
            environment: ["SPKI_CERTS_BIN": certsExe.path, "PATH": ""],
            keyDirectory: fixture.keyDirectoryURL
        )

        let response = try await client.certsVerify(
            CertVerifyRequest(signedCertificateSexp: "(signed demo)", issuerPublicKey: "issuer-pub")
        )
        XCTAssertTrue(response.valid)
        XCTAssertEqual(response.reason, "verified")
    }

    func testCLIBridgeAuthzVerifyChainParsesJSON() async throws {
        let fixture = try CLITestFixture()
        let authzExe = try fixture.writeExecutable(
            named: "spki-authz",
            scriptBody: """
            #!/bin/sh
            if [ "$1" = "--json" ] && [ "$2" = "--verify-chain" ] && [ "$3" = "--root-public-key" ] && [ "$4" = "root-pub" ] && [ "$5" = "--target-tag" ] && [ "$6" = "(read /library)" ] && [ "$7" = "--signed-certificate" ] && [ "$8" = "(signed demo)" ]; then
              echo '{"kind":"authz_verify_chain","allowed":true,"reason":"chain verified","chainLength":1,"targetTag":"(read /library)"}'
              exit 0
            fi
            echo 'unexpected args' >&2
            exit 10
            """
        )

        let client = CLIBridgeAPIClient(
            environment: ["SPKI_AUTHZ_BIN": authzExe.path, "PATH": ""],
            keyDirectory: fixture.keyDirectoryURL
        )

        let response = try await client.authzVerifyChain(
            AuthzVerifyChainRequest(
                rootPublicKey: "root-pub",
                signedCertificates: ["(signed demo)"],
                targetTag: "(read /library)"
            )
        )
        XCTAssertTrue(response.allowed)
        XCTAssertEqual(response.reason, "chain verified")
    }

    func testCLIBridgeAuthzVerifyChainRejectsMissingFields() async throws {
        let fixture = try CLITestFixture()
        let authzExe = try fixture.writeExecutable(
            named: "spki-authz",
            scriptBody: """
            #!/bin/sh
            exit 0
            """
        )

        let client = CLIBridgeAPIClient(
            environment: ["SPKI_AUTHZ_BIN": authzExe.path, "PATH": ""],
            keyDirectory: fixture.keyDirectoryURL
        )

        do {
            _ = try await client.authzVerifyChain(
                AuthzVerifyChainRequest(rootPublicKey: "", signedCertificates: [], targetTag: "")
            )
            XCTFail("Expected invalid_argument for missing rootPublicKey/targetTag")
        } catch let error as APIErrorPayload {
            XCTAssertEqual(error.code, "invalid_argument")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

private struct CLITestFixture {
    let rootURL: URL
    let keyDirectoryURL: URL

    init() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let keyDir = root.appendingPathComponent("keys", isDirectory: true)

        try fm.createDirectory(at: keyDir, withIntermediateDirectories: true)

        rootURL = root
        keyDirectoryURL = keyDir
    }

    func writePublicKey(named name: String) throws {
        let fileURL = keyDirectoryURL.appendingPathComponent(name)
        try "fixture-key-material".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func writeExecutable(named name: String, scriptBody: String) throws -> URL {
        let executableURL = rootURL.appendingPathComponent(name)
        try scriptBody.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        return executableURL
    }
}
