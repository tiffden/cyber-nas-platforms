import SwiftUI

@main
struct CyberspaceApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Cyberspace") {
            RootView()
                .environmentObject(appState)
        }
        .defaultSize(width: 1100, height: 760)

        Settings {
            SettingsScreen()
                .environmentObject(appState)
        }
    }
}
