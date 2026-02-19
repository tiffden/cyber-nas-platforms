import SwiftUI
import AppKit

/// Machine Setup — infrastructure phase.
///
/// Creates machine environments and starts listeners for each virtual node.
/// After Setup Machines completes, all nodes are configured and listening.
/// Node identity and realm membership are established later in Demo Workflow.
struct MachineSetupScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var harnessRootDraft = ""
    @State private var machineCount: Int = 3
    @State private var basePort: Int = 8000
    @State private var machineDrafts: [HarnessLocalMachine] = []
    @State private var didInitialize = false
    @State private var showResetConfirmation = false
    @State private var autoRefreshLog = false
    @State private var autoRefreshSeconds = 2
    @State private var useReadableLogLayout = true

    private var renderedHarnessLog: String {
        let raw = appState.harnessSetupLog
        guard !raw.isEmpty else { return "No harness log yet." }
        guard useReadableLogLayout else { return raw }
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { formatLogLine(String($0)) }.joined(separator: "\n")
    }

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

                        Text("Base Port")
                            .frame(width: 70, alignment: .leading)
                        Stepper(value: $basePort, in: 1...65000, step: 10) {
                            Text(verbatim: "\(basePort)")
                                .monospacedDigit()
                        }
                        .frame(width: 130)
                        .onChange(of: basePort) { _, newBase in
                            regeneratePorts(basePort: newBase)
                        }

                        Text("Harness Root")
                            .frame(width: 90, alignment: .leading)
                        TextField("~/.cyberspace/testbed (optional override)", text: $harnessRootDraft)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Lifecycle controls
                    HStack(spacing: 10) {
                        // Phase indicator
                        Circle()
                            .fill(phaseColor)
                            .frame(width: 8, height: 8)
                        Text(appState.harnessPhase.rawValue)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Divider().frame(height: 16)

                        // Setup Machines (only before first setup)
                        if appState.harnessPhase == .notSetup {
                            Button("Setup Machines") {
                                Task {
                                    applyMachineDrafts()
                                    await appState.createRealmTestEnvironment(nodeCount: machineDrafts.count)
                                    await appState.refreshRealmHarnessNodes()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        // Reset (always destructive — confirmation required)
                        Button("Reset…") { showResetConfirmation = true }
                            .foregroundStyle(.red)
                            .disabled(appState.harnessPhase == .notSetup)

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
                        // TODO: validate port is in legal range 1–65535
                        Text("Port").frame(width: 80, alignment: .leading)
                        Text("Machine Name").frame(maxWidth: .infinity, alignment: .leading)
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
                            TextField("Port", value: $machine.port, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .font(.system(.caption, design: .monospaced))
                            TextField("machine\(machine.id)", text: $machine.machineLabel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }

            // ── Harness Log (fills remaining vertical space) ──────────────
            GroupBox("Harness Log") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("Refresh") {
                            Task { await appState.refreshHarnessSetupLog() }
                        }
                        Toggle("Auto-refresh every:", isOn: $autoRefreshLog)
                        Stepper(value: $autoRefreshSeconds, in: 1...10) {
                            Text("\(autoRefreshSeconds)s").monospacedDigit()
                        }
                        .frame(width: 90)
                        .disabled(!autoRefreshLog)
                        Toggle("Readable", isOn: $useReadableLogLayout)
                    }

                    ScrollView {
                        Text(renderedHarnessLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxHeight: .infinity)
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
            if appState.harnessPhase == .running {
                Task { await appState.refreshHarnessSetupLog() }
            }
            didInitialize = true
        }
        .task(id: "\(autoRefreshLog)-\(autoRefreshSeconds)") {
            guard autoRefreshLog else { return }
            while autoRefreshLog, !Task.isCancelled {
                await appState.refreshHarnessSetupLog()
                let nanos = UInt64(autoRefreshSeconds) * 1_000_000_000
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
        .confirmationDialog(
            "Reset will stop all running processes and delete the harness root. This cannot be undone.",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task { await appState.resetRealmHarness() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Helpers

    private var phaseColor: Color {
        switch appState.harnessPhase {
        case .notSetup: return .secondary
        case .running:  return .green
        }
    }

    private func syncMachineDrafts(count: Int) {
        machineDrafts = (1...count).map { i in
            if let existing = machineDrafts.first(where: { $0.id == i }) {
                return existing
            }
            return HarnessLocalMachine(
                id: i,
                host: "127.0.0.1",
                port: basePort + (i - 1),
                machineLabel: "machine\(i)"
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

    // MARK: - Log Formatting

    private func formatLogLine(_ rawLine: String) -> String {
        guard let data = rawLine.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let component = object["component"] as? String,
              let action = object["action"] as? String else {
            return rawLine
        }

        let timestamp = shortTimestamp(object["ts"] as? String)
        let rawLevel = object["level"] as? String ?? "info"
        let consoleType = consoleLogType(rawLevel)
        let result = object["result"] as? String ?? "ok"
        let subsystem = "\(component):\(action)"

        var messageParts: [String] = [result]
        if let nodeID = object["node_id"] as? String, !nodeID.isEmpty {
            messageParts.append("node \(nodeID)")
        }
        if let duration = object["duration_ms"] as? String, !duration.isEmpty {
            messageParts.append("\(duration)ms")
        }
        if let message = object["message"] as? String, !message.isEmpty {
            messageParts.append(message)
        }
        if let requestID = object["request_id"] as? String,
           !requestID.isEmpty,
           requestID != "n/a" {
            messageParts.append("req \(requestID.prefix(12))")
        }

        let typeCol = consoleType.padding(toLength: 10, withPad: " ", startingAt: 0)
        let subsystemCol = subsystem.padding(toLength: 34, withPad: " ", startingAt: 0)
        return "\(timestamp)  \(typeCol)  \(subsystemCol)  \(messageParts.joined(separator: " | "))"
    }

    private func consoleLogType(_ level: String) -> String {
        switch level.lowercased() {
        case "error", "fault": return "Error"
        case "debug":          return "Debug"
        default:               return "Default"
        }
    }

    private func shortTimestamp(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "--:--:--.---" }
        // Unix epoch seconds emitted by spki-realm.sps (all-digit, > 1 billion).
        if let secs = TimeInterval(raw), secs > 1_000_000_000 {
            let date = Date(timeIntervalSince1970: secs)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm:ss.SSS"
            return f.string(from: date)
        }
        // ISO 8601 (with or without fractional seconds) from other log sources.
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: raw) ?? {
            let fallback = ISO8601DateFormatter()
            return fallback.date(from: raw)
        }()
        guard let date else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
