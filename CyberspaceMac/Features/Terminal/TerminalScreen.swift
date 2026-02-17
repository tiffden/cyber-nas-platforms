import SwiftUI

struct TerminalScreen: View {
    @State private var terminalText = """
    Cyberspace Terminal
    -------------------
    Scaffold mode: no REPL process connected yet.

    Intended use:
    - Inspect trust state directly
    - Verify signatures before publishing
    - Run emergency checks when automation is unavailable
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Step 9: Terminal")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Clear") {
                    terminalText = ""
                }
            }

            GroupBox("Task Stub") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use terminal mode for direct inspection and emergency operations.")
                    Text("Run status, realm, cert, authz, vault, and audit commands when UI flow is insufficient.")
                    Text("Keep this as an operator tool; routine onboarding should stay in guided pages.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TerminalTextView(text: $terminalText)
                .frame(minHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.quaternary)
                )
        }
        .padding()
    }
}
