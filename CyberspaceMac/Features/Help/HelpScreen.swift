import SwiftUI

struct HelpScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Step 10: Help")
                    .font(.title2.weight(.semibold))

                GroupBox("Workflow Map") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Start Here")
                        Text("2. Current Status")
                        Text("3. Generate Identity Keys")
                        Text("4. Create Initial Realm")
                        Text("5. Issue Certificates")
                        Text("6. Invite & Join Realm")
                        Text("7. Test Access")
                        Text("8. Revoke & Re-Issue")
                        Text("9. Terminal")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("CLI Paths") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Configure command paths in `spki/macos/swiftui/.env`.")
                        Text("Defaults are loaded by `spki/macos/swiftui/Scripts/run-local.sh`.")
                        Text("Key env vars: SPKI_KEY_DIR, SPKI_*_BIN, SPKI_CHEZ_*_SCRIPT.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Common Troubleshooting") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Could not find SPKI executable: confirm PATH or SPKI_*_BIN values.")
                        Text("Realm status unknown: check SPKI_REALM_WORKDIR and Chez script paths.")
                        Text("Install/build: run `make build` in `spki/` and verify binaries exist.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
