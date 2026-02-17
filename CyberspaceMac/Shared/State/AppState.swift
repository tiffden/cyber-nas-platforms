import Combine
import Foundation

enum AppRoute: String, CaseIterable, Hashable, Identifiable {
    case startHere
    case currentStatus
    case generateIdentityKeys
    case createInitialRealm
    case issueCertificates
    case inviteJoinRealm
    case testAccess
    case revokeReissue
    case terminal
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startHere: return "Start Here"
        case .currentStatus: return "Current Status"
        case .generateIdentityKeys: return "Generate Identity Keys"
        case .createInitialRealm: return "Create Initial Realm"
        case .issueCertificates: return "Issue Certificates"
        case .inviteJoinRealm: return "Invite & Join Realm"
        case .testAccess: return "Test Access"
        case .revokeReissue: return "Revoke & Re-Issue"
        case .terminal: return "Terminal"
        case .help: return "Help"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedRoute: AppRoute? = .startHere

    @Published var systemStatus = SystemStatus(status: "loading", uptime: "n/a")
    @Published var keys: [KeySummary] = []
    @Published var createdCertificateSexp: String = ""
    @Published var signedCertificateSexp: String = ""
    @Published var certificateVerifyResult: CertVerifyResponse?
    @Published var authzVerifyResult: AuthzVerifyChainResponse?
    @Published var vaultGetResult: VaultGetResponse?
    @Published var vaultPutResult: VaultPutResponse?
    @Published var vaultCommitResult: VaultCommitResponse?
    @Published var auditEntries: [AuditEntry] = []
    @Published var realmStatusValue = RealmStatus(
        status: "loading",
        nodeName: "n/a",
        policy: "n/a",
        memberCount: 0
    )
    @Published var realmJoinResult: RealmJoinResponse?
    @Published var harnessNodeCount: Int = 3
    @Published var harnessNodes: [RealmHarnessNodeMetadata] = []
    @Published var selectedHarnessNodeID: Int = 1
    @Published var harnessCurrentLog: String = ""
    @Published var harnessLaunchOutput: String = ""
    @Published var hasLoadedBootstrapData = false
    @Published var lastErrorMessage: String?

    private let api: any ClientAPI
    private let launchNodeID: Int

    init(
        api: any ClientAPI = CLIBridgeAPIClient(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.api = api
        // `SPKI_NODE_ID` is set by harness scripts so each UI instance can identify itself in the window title.
        self.launchNodeID = Int(environment["SPKI_NODE_ID"] ?? "") ?? 1
    }

    var uiInstanceLabel: String {
        if launchNodeID <= 1 {
            return "Main"
        }
        return "Test Client \(launchNodeID - 1)"
    }

    var uiKeyStatusLabel: String {
        keys.isEmpty ? "no key" : "has key pair"
    }

    var uiWindowTitle: String {
        "\(uiInstanceLabel) - status: \(uiKeyStatusLabel)"
    }

    func loadBootstrapDataIfNeeded() async {
        guard !hasLoadedBootstrapData else { return }
        await loadBootstrapData()
    }

    func loadBootstrapData() async {
        do {
            async let status = api.systemStatus()
            async let keyList = api.keysList()
            let (resolvedStatus, resolvedKeys) = try await (status, keyList)
            systemStatus = resolvedStatus
            keys = resolvedKeys.keys
            if let realm = try? await api.realmStatus() {
                realmStatusValue = realm
            }
            lastErrorMessage = nil
            hasLoadedBootstrapData = true
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func generateKey(name: String, algorithm: String = "ed25519") async {
        do {
            let response = try await api.keysGenerate(KeyGenerateRequest(name: name, algorithm: algorithm))
            keys.append(response.key)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func fetchKey(name: String) async {
        do {
            let response = try await api.keysGet(KeyGetRequest(name: name))
            if let idx = keys.firstIndex(where: { $0.name == response.key.name }) {
                keys[idx] = response.key
            } else {
                keys.append(response.key)
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func createCertificate(
        issuerPrincipal: String,
        subjectPrincipal: String,
        tag: String,
        validityNotAfter: String?,
        propagate: Bool
    ) async {
        do {
            let response = try await api.certsCreate(
                CertCreateRequest(
                    issuerPrincipal: issuerPrincipal,
                    subjectPrincipal: subjectPrincipal,
                    tag: tag,
                    validityNotAfter: validityNotAfter,
                    propagate: propagate
                )
            )
            createdCertificateSexp = response.certificateSexp
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func signCertificate(certificateSexp: String, signerKeyName: String, hashAlgorithm: String = "ed25519") async {
        do {
            let response = try await api.certsSign(
                CertSignRequest(
                    certificateSexp: certificateSexp,
                    signerKeyName: signerKeyName,
                    hashAlgorithm: hashAlgorithm
                )
            )
            signedCertificateSexp = response.signedCertificateSexp
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func verifyCertificate(signedCertificateSexp: String, issuerPublicKey: String) async {
        do {
            let response = try await api.certsVerify(
                CertVerifyRequest(
                    signedCertificateSexp: signedCertificateSexp,
                    issuerPublicKey: issuerPublicKey
                )
            )
            certificateVerifyResult = response
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func verifyAuthorizationChain(rootPublicKey: String, signedCertificates: [String], targetTag: String) async {
        do {
            authzVerifyResult = try await api.authzVerifyChain(
                AuthzVerifyChainRequest(
                    rootPublicKey: rootPublicKey,
                    signedCertificates: signedCertificates,
                    targetTag: targetTag
                )
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func queryAudit(filter: String, limit: Int = 50) async {
        do {
            let response = try await api.auditQuery(AuditQueryRequest(filter: filter, limit: limit))
            auditEntries = response.entries
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func refreshRealmStatus() async {
        do {
            realmStatusValue = try await api.realmStatus()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func joinRealm(name: String, host: String, port: Int) async {
        do {
            realmJoinResult = try await api.realmJoin(
                RealmJoinRequest(name: name, host: host, port: port)
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func createRealmTestEnvironment(nodeCount: Int) async {
        do {
            let response = try await api.createRealmTestEnvironment(nodeCount: nodeCount)
            harnessNodeCount = response.nodeCount
            harnessNodes = response.nodes
            // Default log view to a real node immediately after init so operators see live feedback.
            if let first = response.nodes.first {
                selectedHarnessNodeID = first.id
            }
            await refreshRealmHarnessLog(nodeID: selectedHarnessNodeID)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func refreshRealmHarnessNodes() async {
        do {
            harnessNodes = try await api.realmHarnessNodes(nodeCount: harnessNodeCount)
            if harnessNodes.contains(where: { $0.id == selectedHarnessNodeID }) == false,
               let first = harnessNodes.first {
                selectedHarnessNodeID = first.id
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func launchRealmHarnessUIs(nodeCount: Int) async {
        do {
            let response = try await api.launchRealmHarnessUIs(nodeCount: nodeCount)
            harnessLaunchOutput = response.output
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func stopRealmHarnessUIs(nodeCount: Int) async {
        do {
            let response = try await api.stopRealmHarnessUIs(nodeCount: nodeCount)
            harnessLaunchOutput = response.output
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func refreshRealmHarnessLog(nodeID: Int) async {
        do {
            harnessCurrentLog = try await api.realmHarnessCurrentLog(nodeID: nodeID, maxLines: 200)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func vaultPut(path: String, dataBase64: String, metadata: [String: String] = [:]) async {
        do {
            vaultPutResult = try await api.vaultPut(
                VaultPutRequest(path: path, dataBase64: dataBase64, metadata: metadata)
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func vaultGet(path: String) async {
        do {
            vaultGetResult = try await api.vaultGet(VaultGetRequest(path: path))
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }

    func vaultCommit(message: String) async {
        do {
            vaultCommitResult = try await api.vaultCommit(VaultCommitRequest(message: message))
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? APIErrorPayload)?.message ?? error.localizedDescription
        }
    }
}
