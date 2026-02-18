import Foundation

protocol ClientAPI {
    func createRealmTestEnvironment(nodeCount: Int, config: RealmHarnessCreateConfig?, requestID: String?) async throws -> RealmHarnessInitResponse
    func selfJoinRealmHarness(nodeCount: Int, config: RealmHarnessCreateConfig?, requestID: String?) async throws -> RealmHarnessLaunchResponse
    func inviteOtherRealmHarnessNodes(nodeCount: Int, config: RealmHarnessCreateConfig?, requestID: String?) async throws -> RealmHarnessLaunchResponse
    func launchRealmHarnessUIs(nodeCount: Int, config: RealmHarnessCreateConfig?, requestID: String?) async throws -> RealmHarnessLaunchResponse
    func stopRealmHarnessUIs(nodeCount: Int, config: RealmHarnessCreateConfig?, requestID: String?) async throws -> RealmHarnessLaunchResponse
    func realmHarnessNodes(nodeCount: Int, config: RealmHarnessCreateConfig?, requestID: String?) async throws -> [RealmHarnessNodeMetadata]
    func realmHarnessCurrentLog(nodeID: Int, maxLines: Int, config: RealmHarnessCreateConfig?, requestID: String?) async throws -> String
}

extension ClientAPI {
    func createRealmTestEnvironment(nodeCount: Int) async throws -> RealmHarnessInitResponse {
        try await createRealmTestEnvironment(nodeCount: nodeCount, config: nil, requestID: nil)
    }

    func selfJoinRealmHarness(nodeCount: Int) async throws -> RealmHarnessLaunchResponse {
        try await selfJoinRealmHarness(nodeCount: nodeCount, config: nil, requestID: nil)
    }

    func inviteOtherRealmHarnessNodes(nodeCount: Int) async throws -> RealmHarnessLaunchResponse {
        try await inviteOtherRealmHarnessNodes(nodeCount: nodeCount, config: nil, requestID: nil)
    }

    func launchRealmHarnessUIs(nodeCount: Int) async throws -> RealmHarnessLaunchResponse {
        try await launchRealmHarnessUIs(nodeCount: nodeCount, config: nil, requestID: nil)
    }

    func stopRealmHarnessUIs(nodeCount: Int) async throws -> RealmHarnessLaunchResponse {
        try await stopRealmHarnessUIs(nodeCount: nodeCount, config: nil, requestID: nil)
    }

    func realmHarnessNodes(nodeCount: Int) async throws -> [RealmHarnessNodeMetadata] {
        try await realmHarnessNodes(nodeCount: nodeCount, config: nil, requestID: nil)
    }

    func realmHarnessCurrentLog(nodeID: Int, maxLines: Int) async throws -> String {
        try await realmHarnessCurrentLog(nodeID: nodeID, maxLines: maxLines, config: nil, requestID: nil)
    }
}
