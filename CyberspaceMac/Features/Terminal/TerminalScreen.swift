import SwiftUI

struct TerminalScreen: View {
    @State private var terminalText = """
    Cyberspace Terminal
    -------------------
    Scaffold mode: no REPL process connected yet.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Terminal")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Clear") {
                    terminalText = ""
                }
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
