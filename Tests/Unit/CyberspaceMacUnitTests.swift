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
