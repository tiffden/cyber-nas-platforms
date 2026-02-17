import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedRoute) {
                ForEach(AppRoute.allCases) { route in
                    NavigationLink(route.title, value: route)
                }
            }
            .navigationTitle("Cyberspace")
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
    }
}
