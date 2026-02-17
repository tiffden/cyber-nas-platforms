import SwiftUI

struct StartHereScreen: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Start Here: Build a 5-Node Realm")
                    .font(.largeTitle.weight(.bold))

                Text("Goal: create one trust domain with five nodes, each with its own certificate-backed identity and explicit delegation rules.")
                    .foregroundStyle(.secondary)

                GroupBox("Node Plan") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Node 1: Root Admin (creates realm policy and signs invitations).")
                        Text("Node 2: Editor Desk (publication approvals).")
                        Text("Node 3: Reporter (draft + source package upload).")
                        Text("Node 4: Fact-Check (read + annotate evidence).")
                        Text("Node 5: Legal (final review scope).")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Step 1: Generate Identity Keys (All 5 Nodes)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("UI page: Keyring")
                        Text("Create one keypair per node identity: root-admin, editor, reporter, factcheck, legal.")
                        Text("Why: each principal must have a unique cryptographic identity before any certificate can be issued.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Step 2: Create Initial Realm (Node 1)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("UI page: Realm")
                        Text("Use Node 1 to create/host the initial realm endpoint (name + host + port).")
                        Text("This establishes the trust domain boundary and initial authority anchor.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Step 3: Issue Certificates (Node 1 -> Nodes 2-5)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("UI page: Certificates")
                        Text("For each node, create a capability cert with least privilege tags.")
                        Text("Examples: reporter can upload to one story path; legal can review but not edit.")
                        Text("Sign each certificate with Node 1's key, then verify signature and delegation chain.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Step 4: Invite and Join Realm (Nodes 2-5)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("UI page: Realm")
                        Text("Each invited node uses realm join with the realm endpoint and assigned identity.")
                        Text("Confirm member count reaches 5 and status is joined for each node.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Step 5: Test Delegation and Enforcement") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("UI pages: Certificates + Audit")
                        Text("Use authz.verify_chain to prove each action is allowed before performing it.")
                        Text("Run vault.put/get/commit under each role and confirm policy boundaries hold.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Step 6: Revoke and Re-Issue (Incident Drill)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("UI pages: Certificates + Realm + Audit")
                        Text("Revoke one node certificate (for example reporter device compromise).")
                        Text("Verify old chain is denied, then issue replacement cert and re-join.")
                        Text("Confirm audit trail captures revoke, re-issue, and post-recovery access.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Operational Checklist") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Every node has a unique keypair.")
                        Text("2. Every node has an explicit certificate.")
                        Text("3. Realm membership is explicit and auditable.")
                        Text("4. Delegation is least-privilege and time-bounded.")
                        Text("5. Revocation path is tested before production use.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Current Local Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("System: \(appState.systemStatus.status)")
                        Text("Keys discovered: \(appState.keys.count)")
                        Text("Realm status: \(appState.realmStatusValue.status)")
                        if let err = appState.lastErrorMessage {
                            Text("Last error: \(err)")
                                .foregroundStyle(.red)
                        }
                        Button("Refresh") {
                            Task { await appState.loadBootstrapData() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            await appState.loadBootstrapDataIfNeeded()
        }
    }
}
