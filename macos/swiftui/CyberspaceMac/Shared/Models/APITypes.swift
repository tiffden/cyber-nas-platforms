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

/// Lifecycle phase of the local harness testbed.
///
/// - notSetup: initial state or after reset; no environments exist.
/// - running:  environments created, listeners active; ready for Demo Workflow.
enum HarnessPhase: String {
    case notSetup = "Not Setup"
    case running  = "Running"
}

/// Per-machine configuration for the local harness testbed.
///
/// `machineLabel` is both the operator-facing name and the harness directory name
/// (e.g. "machine1" → `~/.cyberspace/testbed/machine1/`).
/// Protocol node identity is assigned later during Demo Workflow.
struct HarnessLocalMachine: Identifiable, Equatable {
    let id: Int              // 1-based; immutable after creation
    var host: String
    var port: Int
    var machineLabel: String // UI label and harness directory name
}

struct RealmHarnessCreateConfig: Equatable {
    let realmName: String
    let host: String
    let port: Int
    let harnessRoot: String?
    let nodeNamesCSV: String?
    let logLevel: String?
    /// Overrides the name assigned to the bootstrap node (node 1) during self-join.
    /// When nil the default from SPKI_DEFAULT_NODE_NAMES is used.
    let bootstrapNodeName: String?
    /// Overrides the node identity name for a single non-master node during join-one.
    /// Does not affect machine directory resolution — the machine label from nodeNamesCSV is still
    /// used to locate the existing machine directory created at init time.
    let joinNodeName: String?

    init(
        realmName: String,
        host: String,
        port: Int,
        harnessRoot: String? = nil,
        nodeNamesCSV: String? = nil,
        logLevel: String? = nil,
        bootstrapNodeName: String? = nil,
        joinNodeName: String? = nil
    ) {
        self.realmName = realmName
        self.host = host
        self.port = port
        self.harnessRoot = harnessRoot
        self.nodeNamesCSV = nodeNamesCSV
        self.logLevel = logLevel
        self.bootstrapNodeName = bootstrapNodeName
        self.joinNodeName = joinNodeName
    }
}

struct RealmHarnessNodeMetadata: Identifiable, Equatable {
    let id: Int
    let nodeName: String
    let envFile: String
    let workdir: String
    let keydir: String
    let logdir: String
    let host: String
    let port: Int
    let status: String
    let memberCount: Int
    let policy: String
    let uuid: String
}

struct RealmHarnessInitResponse: Equatable {
    let nodeCount: Int
    let nodes: [RealmHarnessNodeMetadata]
}

struct RealmHarnessLaunchResponse: Equatable {
    let nodeCount: Int
    let output: String
}
