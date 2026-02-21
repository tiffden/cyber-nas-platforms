import XCTest
@testable import CyberspaceMac

final class CyberspaceMacUnitTests: XCTestCase {
    // Harness tests go here. Use CLITestFixture to build isolated executable stubs.
}

// MARK: - Test Fixture

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
