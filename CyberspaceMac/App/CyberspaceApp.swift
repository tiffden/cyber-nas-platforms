import SwiftUI
import AppKit

@main
struct CyberspaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Cyberspace") {
            RootView()
                .environmentObject(appState)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Cyberspace") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }

        Settings {
            SettingsScreen()
                .environmentObject(appState)
        }
    }
}

// MARK: - App Delegate

/// Handles early-lifecycle activation that SwiftUI's App protocol cannot express.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app is treated as a regular foreground process.
        // Plain binaries launched from a shell (not through a .app bundle /
        // LaunchServices) may get an accessory activation policy, which
        // prevents windows from becoming key and blocks text-field focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }
}
