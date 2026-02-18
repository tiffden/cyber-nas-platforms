import Foundation

struct SystemStatus: Equatable {
    let status: String
    let uptime: String
}

struct KeySummary: Identifiable, Equatable {
    let id: String
    let name: String
    let algorithm: String
    let fingerprint: String
}

struct KeyList: Equatable {
    let keys: [KeySummary]
}

struct KeyGenerateRequest: Equatable {
    let name: String
    let algorithm: String
}

struct KeyGenerateResponse: Equatable {
    let key: KeySummary
}

struct KeyGetRequest: Equatable {
    let name: String
}

struct KeyGetResponse: Equatable {
    let key: KeySummary
}

struct CertCreateRequest: Equatable {
    let issuerPrincipal: String
    let subjectPrincipal: String
    let tag: String
    let validityNotAfter: String?
    let propagate: Bool
}

struct CertCreateResponse: Equatable {
    let certificateSexp: String
}

struct CertSignRequest: Equatable {
    let certificateSexp: String
    let signerKeyName: String
    let hashAlgorithm: String
}

struct CertSignResponse: Equatable {
    let signedCertificateSexp: String
}

struct CertVerifyRequest: Equatable {
    let signedCertificateSexp: String
    let issuerPublicKey: String
}

struct CertVerifyResponse: Equatable {
    let valid: Bool
    let reason: String
}

struct AuthzVerifyChainRequest: Equatable {
    let rootPublicKey: String
    let signedCertificates: [String]
    let targetTag: String
}

struct AuthzVerifyChainResponse: Equatable {
    let allowed: Bool
    let reason: String
}

struct VaultGetRequest: Equatable {
    let path: String
}

struct VaultGetResponse: Equatable {
    let path: String
    let dataBase64: String
    let metadata: [String: String]
}

struct VaultPutRequest: Equatable {
    let path: String
    let dataBase64: String
    let metadata: [String: String]
}

struct VaultPutResponse: Equatable {
    let path: String
    let revisionHint: String
}

struct VaultCommitRequest: Equatable {
    let message: String
}

struct VaultCommitResponse: Equatable {
    let commitID: String
}

struct AuditQueryRequest: Equatable {
    let filter: String
    let limit: Int
}

struct AuditEntry: Identifiable, Equatable {
    let id: String
    let actor: String
    let action: String
    let timestamp: String
    let context: String
}

struct AuditQueryResponse: Equatable {
    let entries: [AuditEntry]
}

struct RealmStatus: Equatable {
    let status: String
    let nodeName: String
    let policy: String
    let memberCount: Int
}

struct RealmJoinRequest: Equatable {
    let name: String
    let host: String
    let port: Int
}

struct RealmJoinResponse: Equatable {
    let joined: Bool
    let message: String
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
