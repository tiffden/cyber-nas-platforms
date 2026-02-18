import SwiftUI
import AppKit

/// Top-level container for the Local Harness builder UI.
///
/// Switches between the two phases of a local testbed session:
/// - Machine Setup: create isolated machine environments (no realm state yet)
/// - Demo Workflow: bootstrap realm, join nodes, observe status and logs
struct LocalHarnessScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var activeTab: HarnessTab = .machineSetup

    private enum HarnessTab: String, CaseIterable {
        case machineSetup = "Machine Setup"
        case demoWorkflow = "Demo Workflow"
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
            .frame(maxWidth: 280)

            switch activeTab {
            case .machineSetup: MachineSetupScreen()
            case .demoWorkflow: DemoWorkflowScreen()
            }
        }
        .padding()
    }
}
