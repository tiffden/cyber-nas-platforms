import Foundation

// MARK: - Error

struct APIErrorPayload: Codable, Error {
    let code: String
    let message: String
    let details: [String: String]?
}

// MARK: - Realm Status (used internally by CLIBridgeAPIClient)

struct RealmStatus: Equatable {
    let status: String
    let nodeName: String
    let policy: String
    let memberCount: Int
}

// MARK: - Harness Types

/// Per-machine configuration for the local harness testbed.
///
/// `machineLabel` is the operator-facing name shown in the UI (e.g. "Machine 1").
/// `nodeName` is the protocol identity created at join time (e.g. "machine1").
/// They default to the same value but can be edited independently.
struct HarnessLocalMachine: Identifiable, Equatable {
    let id: Int              // 1-based; immutable after creation
    var host: String
    var port: Int
    var machineLabel: String // UI/operator-facing label
    var nodeName: String     // protocol identity at join
}

struct RealmHarnessCreateConfig: Equatable {
    let realmName: String
    let host: String
    let port: Int
    let harnessRoot: String?
    let nodeNamesCSV: String?
}

struct RealmHarnessNodeMetadata: Identifiable, Equatable {
    let id: Int
    let nodeName: String
    let envFile: String
    let workdir: String
    let keydir: String
    let host: String
    let port: Int
    let status: String
    let memberCount: Int
}

struct RealmHarnessInitResponse: Equatable {
    let nodeCount: Int
    let nodes: [RealmHarnessNodeMetadata]
}

struct RealmHarnessLaunchResponse: Equatable {
    let nodeCount: Int
    let output: String
}
