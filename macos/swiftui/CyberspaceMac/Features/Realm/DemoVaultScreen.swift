import SwiftUI

struct DemoVaultsView: View {
    @EnvironmentObject private var appState: AppState

    // Workflow state
    @State private var selectedFiles: [URL] = []
    @State private var sealCommitMessage = "Add user data"
    @State private var releaseVersion = "1.0.0"
    @State private var releaseMessage = "Demo sealed release"
    @State private var didSealCommit = false
    @State private var didSealRelease = false
    @State private var didSealVerify = false
    @State private var sealActionStatus = ""
    @State private var isSealActionRunning = false

    private var vaultTargetNodeID: Int {
        appState.selectedHarnessNodeID > 0 ? appState.selectedHarnessNodeID : 1
    }

    private var realmBootstrapped: Bool {
        appState.harnessNodes.contains(where: { $0.status != "standalone" })
    }

    private var hasFiles: Bool { !selectedFiles.isEmpty }
    private var hasCommitMessage: Bool {
        !sealCommitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var hasVersion: Bool {
        !releaseVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                if !realmBootstrapped {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .imageScale(.small)
                        Text("Bootstrap a realm in Demo Workflow first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // ── Step 1: Select Vault Node ────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        stepLabel(number: 1, title: "Select Vault Node")
                        HStack {
                            Text("Node")
                                .frame(width: 56, alignment: .leading)
                            Picker("", selection: $appState.selectedHarnessNodeID) {
                                Text("Node 1 (default)").tag(0)
                                ForEach(appState.harnessNodes) { node in
                                    Text("Node \(node.id) (\(node.nodeName))").tag(node.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 220)

                            vaultDirectoryBadge()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Step 2: Add User Data ────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        stepLabel(number: 2, title: "Add User Data")
                        Text("Select files to include in the vault. These will be staged for seal-commit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // File list
                        if selectedFiles.isEmpty {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                    .foregroundStyle(.tertiary)
                                Text("No files added yet. Use the buttons below to add files or a folder.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(selectedFiles.enumerated()), id: \.element) { index, url in
                                    HStack(spacing: 6) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(url.lastPathComponent)
                                                .font(.system(.caption, design: .default))
                                            Text(url.path)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                        Button {
                                            selectedFiles.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                                .imageScale(.small)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(index.isMultiple(of: 2)
                                        ? Color.secondary.opacity(0.04)
                                        : Color.clear)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
                        }

                        HStack(spacing: 8) {
                            Button("Add Files...") {
                                openFilePicker(allowFolders: false)
                            }
                            Button("Add Folder...") {
                                openFilePicker(allowFolders: true)
                            }
                            if hasFiles {
                                Button("Clear All") {
                                    selectedFiles.removeAll()
                                }
                                .foregroundStyle(.red)
                            }
                            Spacer()
                            if hasFiles {
                                Text("\(selectedFiles.count) item\(selectedFiles.count == 1 ? "" : "s") selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Step 3: Seal Commit ──────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        stepLabel(number: 3, title: "Seal Commit", done: didSealCommit)
                        Text("Stage and cryptographically seal the selected files into the vault.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Message")
                                .frame(width: 64, alignment: .leading)
                            TextField("Commit message", text: $sealCommitMessage)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button("seal-commit") {
                            Task {
                                isSealActionRunning = true
                                let out = await appState.sealCommit(
                                    nodeID: vaultTargetNodeID,
                                    message: sealCommitMessage
                                )
                                if appState.lastErrorMessage == nil {
                                    didSealCommit = true
                                    didSealRelease = false
                                    didSealVerify = false
                                    sealActionStatus = out?.isEmpty == false
                                        ? out!
                                        : "seal-commit completed for node \(vaultTargetNodeID)."
                                } else {
                                    didSealCommit = false
                                    didSealRelease = false
                                    didSealVerify = false
                                    sealActionStatus = appState.lastErrorMessage ?? "seal-commit failed."
                                }
                                isSealActionRunning = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!realmBootstrapped || isSealActionRunning || !hasCommitMessage)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Step 4: Seal Release ─────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        stepLabel(number: 4, title: "Seal Release", done: didSealRelease)
                        Text("Create a cryptographically signed release at a semantic version.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Version")
                                .frame(width: 64, alignment: .leading)
                            TextField("1.0.0", text: $releaseVersion)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                            Text("(X.Y.Z)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        HStack {
                            Text("Notes")
                                .frame(width: 64, alignment: .leading)
                            TextField("Release notes", text: $releaseMessage)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button("seal-release") {
                            Task {
                                isSealActionRunning = true
                                let out = await appState.sealRelease(
                                    nodeID: vaultTargetNodeID,
                                    version: releaseVersion,
                                    message: releaseMessage
                                )
                                if appState.lastErrorMessage == nil {
                                    didSealRelease = true
                                    didSealVerify = false
                                    sealActionStatus = out?.isEmpty == false
                                        ? out!
                                        : "seal-release \(releaseVersion) completed for node \(vaultTargetNodeID)."
                                } else {
                                    didSealRelease = false
                                    didSealVerify = false
                                    sealActionStatus = appState.lastErrorMessage ?? "seal-release failed."
                                }
                                isSealActionRunning = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!realmBootstrapped || isSealActionRunning || !didSealCommit || !hasVersion)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Step 5: Verify & Archive (Zstd+Age) ─────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        stepLabel(number: 5, title: "Verify & Archive", done: didSealVerify)
                        Text("Verify the Ed25519 signature, then create a sealed archive. The archive format is always Zstd+Age (Zstd compression + Age encryption).")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Archive format badge
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.blue)
                                .imageScale(.small)
                            Text("Zstd+Age")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.blue)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("vault-\(releaseVersion).archive.tar.zst.age")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        HStack(spacing: 8) {
                            Button("seal-verify") {
                                Task {
                                    isSealActionRunning = true
                                    let out = await appState.sealVerify(
                                        nodeID: vaultTargetNodeID,
                                        version: releaseVersion
                                    )
                                    if appState.lastErrorMessage == nil {
                                        didSealVerify = true
                                        sealActionStatus = out?.isEmpty == false
                                            ? out!
                                            : "seal-verify \(releaseVersion) passed for node \(vaultTargetNodeID)."
                                    } else {
                                        didSealVerify = false
                                        sealActionStatus = appState.lastErrorMessage ?? "seal-verify failed."
                                    }
                                    isSealActionRunning = false
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!realmBootstrapped || isSealActionRunning || !didSealRelease)

                            Button("seal-archive  (Zstd+Age)") {
                                Task {
                                    isSealActionRunning = true
                                    let out = await appState.sealArchive(
                                        nodeID: vaultTargetNodeID,
                                        version: releaseVersion,
                                        format: "zstd-age"
                                    )
                                    if appState.lastErrorMessage == nil {
                                        sealActionStatus = out?.isEmpty == false
                                            ? out!
                                            : "seal-archive \(releaseVersion) (zstd-age) completed for node \(vaultTargetNodeID)."
                                    } else {
                                        sealActionStatus = appState.lastErrorMessage ?? "seal-archive failed."
                                    }
                                    isSealActionRunning = false
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!realmBootstrapped || isSealActionRunning || !didSealVerify)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Status ───────────────────────────────────────────────────
                if !sealActionStatus.isEmpty {
                    GroupBox {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: appState.lastErrorMessage == nil
                                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(appState.lastErrorMessage == nil ? .green : .red)
                                .imageScale(.small)
                            Text(sealActionStatus)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                Spacer()
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepLabel(number: Int, title: String, done: Bool = false) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.accentColor)
                    .frame(width: 20, height: 20)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            Text(title)
                .font(.headline)
        }
    }

    @ViewBuilder
    private func vaultDirectoryBadge() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(".vault/")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(["objects/", "metadata/", "releases/", "audit/", "subscriptions/"], id: \.self) { dir in
                    Text(dir)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func openFilePicker(allowFolders: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = !allowFolders
        panel.canChooseDirectories = allowFolders
        panel.canCreateDirectories = false
        if panel.runModal() == .OK {
            let newURLs = panel.urls.filter { url in
                !selectedFiles.contains(url)
            }
            selectedFiles.append(contentsOf: newURLs)
        }
    }
}
