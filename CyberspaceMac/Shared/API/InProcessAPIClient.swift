import Foundation

/// In-process mock implementation of `ClientAPI` for unit tests and simulator builds.
/// All harness operations return plausible synthetic data without launching shell processes.
struct InProcessAPIClient: ClientAPI {
    func createRealmTestEnvironment(
        nodeCount: Int,
        config _: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> RealmHarnessInitResponse {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        let nodes = (1...nodeCount).map { id in
            RealmHarnessNodeMetadata(
                id: id,
                nodeName: "node\(id)",
                envFile: "/tmp/mock/node\(id)/node.env",
                workdir: "/tmp/mock/node\(id)/work",
                keydir: "/tmp/mock/node\(id)/keys",
                logdir: "/tmp/mock/node\(id)/logs",
                host: "127.0.0.1",
                port: 7779 + id,
                status: "standalone",
                memberCount: 1
            )
        }
        return RealmHarnessInitResponse(nodeCount: nodeCount, nodes: nodes)
    }

    func selfJoinRealmHarness(
        nodeCount: Int,
        config _: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> RealmHarnessLaunchResponse {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        return RealmHarnessLaunchResponse(
            nodeCount: nodeCount,
            output: "Mock self-join: node1 joined local realm."
        )
    }

    func inviteOtherRealmHarnessNodes(
        nodeCount: Int,
        config _: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> RealmHarnessLaunchResponse {
        guard nodeCount > 1 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 1", details: nil)
        }
        return RealmHarnessLaunchResponse(
            nodeCount: nodeCount,
            output: "Mock invite: nodes 2...\(nodeCount) joined local realm."
        )
    }

    func launchRealmHarnessUIs(
        nodeCount: Int,
        config _: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> RealmHarnessLaunchResponse {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        return RealmHarnessLaunchResponse(
            nodeCount: nodeCount,
            output: "Mock launch for \(nodeCount) nodes: no background processes started in in-process mode."
        )
    }

    func stopRealmHarnessUIs(
        nodeCount: Int,
        config _: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> RealmHarnessLaunchResponse {
        guard nodeCount > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeCount must be > 0", details: nil)
        }
        return RealmHarnessLaunchResponse(
            nodeCount: nodeCount,
            output: "Mock stop for \(nodeCount) nodes: no background processes to stop in in-process mode."
        )
    }

    func cleanRealmHarness(
        config _: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> RealmHarnessLaunchResponse {
        return RealmHarnessLaunchResponse(nodeCount: 0, output: "Mock clean: harness root removed in in-process mode.")
    }

    func realmHarnessNodes(
        nodeCount: Int,
        config: RealmHarnessCreateConfig?,
        requestID: String?
    ) async throws -> [RealmHarnessNodeMetadata] {
        let response = try await createRealmTestEnvironment(nodeCount: nodeCount, config: config, requestID: requestID)
        return response.nodes
    }

    func realmHarnessCurrentLog(
        nodeID: Int,
        maxLines: Int,
        config _: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> String {
        guard nodeID > 0 else {
            throw APIErrorPayload(code: "invalid_argument", message: "nodeID must be > 0", details: nil)
        }
        return """
        [mock node \(nodeID)] Current Log
        maxLines=\(maxLines)
        - realm status queried
        - no live harness process in in-process mode
        """
    }

    func realmHarnessLog(
        maxLines: Int,
        config _: RealmHarnessCreateConfig?,
        requestID _: String?
    ) async throws -> String {
        return "[mock harness log] maxLines=\(maxLines) — no harness process in in-process mode."
    }
}
