import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        LocalHarnessScreen()
        .onAppear {
            applyWindowTitle()
        }
        .onChange(of: appState.uiWindowTitle) { _, _ in
            applyWindowTitle()
        }
    }

    private func applyWindowTitle() {
        // Keep the macOS title bar in sync with the dynamic window title from AppState.
        let title = appState.uiWindowTitle
        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first {
            window.title = title
        }
    }
}
