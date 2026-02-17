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
            switch appState.selectedRoute ?? .onboarding {
            case .onboarding:
                OnboardingScreen()
            case .terminal:
                TerminalScreen()
            case .keyring:
                KeyringScreen()
            case .certificates:
                CertificatesScreen()
            case .audit:
                AuditScreen()
            case .realm:
                RealmScreen()
            }
        }
        .task {
            await appState.loadBootstrapDataIfNeeded()
        }
    }
}
