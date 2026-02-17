import SwiftUI

struct CertificatesScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var issuerPrincipal = "alice"
    @State private var subjectPrincipal = "bob"
    @State private var tag = "(read (path /library/*))"
    @State private var notAfter = ""
    @State private var propagate = true
    @State private var signerKey = "alice"
    @State private var verifyIssuerPublicKey = "issuer-public-key"
    @State private var authzRootKey = "root-public-key"
    @State private var authzTargetTag = "(read (path /library/*))"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Certificates")
                    .font(.title2.weight(.semibold))

                GroupBox("Create") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Issuer principal", text: $issuerPrincipal)
                        TextField("Subject principal", text: $subjectPrincipal)
                        TextField("Tag", text: $tag)
                        TextField("Not after (optional)", text: $notAfter)
                        Toggle("Propagate", isOn: $propagate)
                        Button("Create certificate") {
                            Task {
                                await appState.createCertificate(
                                    issuerPrincipal: issuerPrincipal,
                                    subjectPrincipal: subjectPrincipal,
                                    tag: tag,
                                    validityNotAfter: notAfter.isEmpty ? nil : notAfter,
                                    propagate: propagate
                                )
                            }
                        }
                    }
                }

                GroupBox("Sign + Verify") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Signer key name", text: $signerKey)
                        Button("Sign certificate") {
                            Task {
                                await appState.signCertificate(
                                    certificateSexp: appState.createdCertificateSexp,
                                    signerKeyName: signerKey
                                )
                            }
                        }

                        TextField("Issuer public key", text: $verifyIssuerPublicKey)
                        Button("Verify certificate") {
                            Task {
                                await appState.verifyCertificate(
                                    signedCertificateSexp: appState.signedCertificateSexp,
                                    issuerPublicKey: verifyIssuerPublicKey
                                )
                            }
                        }
                    }
                }

                GroupBox("Authz Chain") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Root public key", text: $authzRootKey)
                        TextField("Target tag", text: $authzTargetTag)
                        Button("Verify chain") {
                            Task {
                                let chain = appState.signedCertificateSexp.isEmpty ? [] : [appState.signedCertificateSexp]
                                await appState.verifyAuthorizationChain(
                                    rootPublicKey: authzRootKey,
                                    signedCertificates: chain,
                                    targetTag: authzTargetTag
                                )
                            }
                        }
                    }
                }

                GroupBox("Result") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Created cert: \(appState.createdCertificateSexp.isEmpty ? "none" : "ready")")
                        Text("Signed cert: \(appState.signedCertificateSexp.isEmpty ? "none" : "ready")")
                        if let verify = appState.certificateVerifyResult {
                            Text("Certificate verify: \(verify.valid ? "valid" : "invalid") (\(verify.reason))")
                        }
                        if let authz = appState.authzVerifyResult {
                            Text("Chain verify: \(authz.allowed ? "allowed" : "denied") (\(authz.reason))")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }
}
