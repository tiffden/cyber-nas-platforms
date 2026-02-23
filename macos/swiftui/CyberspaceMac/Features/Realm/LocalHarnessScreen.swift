import SwiftUI
import AppKit

/// Top-level container for the Local Harness builder UI.
///
/// Switches between the phases of a local testbed session:
/// - Machine Setup: create isolated machine environments (no realm state yet)
/// - Demo Workflow: bootstrap realm, join nodes, observe status and logs
/// - Demo Vaults: exercise vault put/get/commit once the realm exists
struct LocalHarnessScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var activeTab: HarnessTab = .machineSetup

    private enum HarnessTab: String, CaseIterable {
        case machineSetup = "Machine Setup"
        case demoWorkflow = "Demo Workflow"
        case demoVaults   = "Demo Vaults"
        case schemeREPL   = "Scheme REPL"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Local Harness (Builder Mode)")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("UI Version: \(appState.uiVersionLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("", selection: $activeTab) {
                ForEach(HarnessTab.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 560)

            ZStack {
                MachineSetupScreen()
                    .opacity(activeTab == .machineSetup ? 1 : 0)
                    .allowsHitTesting(activeTab == .machineSetup)
                    .accessibilityHidden(activeTab != .machineSetup)

                DemoWorkflowScreen()
                    .opacity(activeTab == .demoWorkflow ? 1 : 0)
                    .allowsHitTesting(activeTab == .demoWorkflow)
                    .accessibilityHidden(activeTab != .demoWorkflow)

                DemoVaultsView()
                    .opacity(activeTab == .demoVaults ? 1 : 0)
                    .allowsHitTesting(activeTab == .demoVaults)
                    .accessibilityHidden(activeTab != .demoVaults)

                SchemeREPLPanel()
                    .opacity(activeTab == .schemeREPL ? 1 : 0)
                    .allowsHitTesting(activeTab == .schemeREPL)
                    .accessibilityHidden(activeTab != .schemeREPL)
            }
        }
        .padding()
    }
}
