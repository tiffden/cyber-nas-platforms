import SwiftUI
import AppKit

/// Machine Setup — infrastructure phase.
///
/// Creates isolated machine environments (directories, env files, port assignments).
/// Node identity and realm membership are not established here; that happens in Demo Workflow.
struct MachineSetupScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var harnessRootDraft = ""
    @State private var machineCount: Int = 3
    @State private var basePort: Int = 8000
    @State private var machineDrafts: [HarnessLocalMachine] = []
    @State private var didInitialize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Configuration") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Machines")
                            .frame(width: 110, alignment: .leading)
                        Stepper(value: $machineCount, in: 1...10) {
                            Text("\(machineCount)")
                                .monospacedDigit()
                        }
                        .frame(width: 130)
                        .onChange(of: machineCount) { _, newCount in
                            syncMachineDrafts(count: newCount)
                        }

                        Text("Base port")
                            .frame(width: 70, alignment: .leading)
                        Stepper(value: $basePort, in: 1...65000, step: 10) {
                            Text("\(basePort)")
                                .monospacedDigit()
                        }
                        .frame(width: 130)
                        .onChange(of: basePort) { _, newBase in
                            regeneratePorts(basePort: newBase)
                        }

                        Text("Harness root")
                            .frame(width: 90, alignment: .leading)
                        TextField("~/.cyberspace/testbed (optional override)", text: $harnessRootDraft)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Button("Setup Machines") {
                            Task {
                                applyMachineDrafts()
                                await appState.createRealmTestEnvironment(nodeCount: machineDrafts.count)
                                await appState.refreshRealmHarnessNodes()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Refresh") {
                            Task {
                                applyMachineDrafts()
                                await appState.refreshRealmHarnessNodes()
                            }
                        }

                        if let err = appState.lastErrorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            GroupBox("Machines") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("#").frame(width: 30, alignment: .leading)
                        Text("Host").frame(width: 130, alignment: .leading)
                        Text("Port").frame(width: 80, alignment: .leading)
                        Text("Label").frame(width: 130, alignment: .leading)
                        Text("Node Name").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach($machineDrafts) { $machine in
                        HStack {
                            Text("#\(machine.id)")
                                .frame(width: 30, alignment: .leading)
                                .font(.system(.caption, design: .monospaced))
                            TextField("127.0.0.1", text: $machine.host)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 130)
                                .font(.system(.caption, design: .monospaced))
                            TextField("Port", value: $machine.port, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .font(.system(.caption, design: .monospaced))
                            TextField("Machine \(machine.id)", text: $machine.machineLabel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 130)
                                .font(.system(.caption, design: .monospaced))
                            TextField("machine\(machine.id)", text: $machine.nodeName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }

            Spacer()
        }
        .onAppear {
            guard !didInitialize else { return }
            harnessRootDraft = appState.harnessRootOverride
            if appState.harnessMachines.isEmpty {
                machineCount = appState.harnessNodeCount
                syncMachineDrafts(count: machineCount)
            } else {
                machineDrafts = appState.harnessMachines
                machineCount = machineDrafts.count
            }
            activateWindow()
            didInitialize = true
        }
    }

    // MARK: - Helpers

    private func syncMachineDrafts(count: Int) {
        machineDrafts = (1...count).map { i in
            if let existing = machineDrafts.first(where: { $0.id == i }) {
                return existing
            }
            return HarnessLocalMachine(
                id: i,
                host: "127.0.0.1",
                port: basePort + (i - 1),
                machineLabel: "Machine \(i)",
                nodeName: "machine\(i)"
            )
        }
    }

    private func regeneratePorts(basePort: Int) {
        machineDrafts = machineDrafts.enumerated().map { idx, machine in
            var m = machine
            m.port = basePort + idx
            return m
        }
    }

    private func applyMachineDrafts() {
        appState.harnessRootOverride = harnessRootDraft
        appState.harnessMachines = machineDrafts
        appState.harnessNodeCount = machineDrafts.count
    }

    private func activateWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first(where: { $0.canBecomeKey }) {
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }
}
