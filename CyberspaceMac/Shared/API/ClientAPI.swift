import Foundation

protocol ClientAPI {
    func call(_ request: APIRequestEnvelope) async throws -> APIResponseEnvelope

    func systemStatus() async throws -> SystemStatus
    func keysList() async throws -> KeyList
    func keysGenerate(_ request: KeyGenerateRequest) async throws -> KeyGenerateResponse
    func keysGet(_ request: KeyGetRequest) async throws -> KeyGetResponse
    func certsCreate(_ request: CertCreateRequest) async throws -> CertCreateResponse
    func certsSign(_ request: CertSignRequest) async throws -> CertSignResponse
    func certsVerify(_ request: CertVerifyRequest) async throws -> CertVerifyResponse
    func authzVerifyChain(_ request: AuthzVerifyChainRequest) async throws -> AuthzVerifyChainResponse
    func vaultGet(_ request: VaultGetRequest) async throws -> VaultGetResponse
    func vaultPut(_ request: VaultPutRequest) async throws -> VaultPutResponse
    func vaultCommit(_ request: VaultCommitRequest) async throws -> VaultCommitResponse
    func auditQuery(_ request: AuditQueryRequest) async throws -> AuditQueryResponse
    func realmStatus() async throws -> RealmStatus
    func realmJoin(_ request: RealmJoinRequest) async throws -> RealmJoinResponse
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
