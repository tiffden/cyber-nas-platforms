import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedRoute) {
                ForEach(AppRoute.allCases) { route in
                    NavigationLink(route.title, value: route)
                }
            }
            .navigationTitle(appState.uiWindowTitle)
        } detail: {
            switch appState.selectedRoute ?? .startHere {
            case .startHere:
                StartHereScreen()
            case .currentStatus:
                CurrentStatusScreen()
            case .generateIdentityKeys:
                KeyringScreen()
            case .createInitialRealm:
                RealmScreen()
            case .issueCertificates:
                CertificatesScreen()
            case .inviteJoinRealm:
                RealmScreen()
            case .testAccess:
                AuditScreen()
            case .revokeReissue:
                CertificatesScreen()
            case .terminal:
                TerminalScreen()
            case .help:
                HelpScreen()
            }
        }
        .task {
            await appState.loadBootstrapDataIfNeeded()
        }
        .onAppear {
            applyWindowTitle()
        }
        .onChange(of: appState.uiWindowTitle) { _, _ in
            applyWindowTitle()
        }
    }

    private func applyWindowTitle() {
        #if canImport(AppKit)
        // Keep macOS title bar aligned with the dynamic sidebar title.
        let title = appState.uiWindowTitle
        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first {
            window.title = title
        }
        #endif
    }
}
