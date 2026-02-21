# SwiftUI SPKI Bridge (Platform-Specific)

This directory contains macOS SwiftUI-specific bridge implementation artifacts.

Contents:

- `swiftui/api/ClientAPI.swift` (mirrored from shared contract)
- `swiftui/api/CLIBridgeAPIClient.swift`
- `swiftui/api/InProcessAPIClient.swift`
- `swiftui/models/APITypes.swift` (mirrored from shared contract)
- `swiftui/state/AppState.swift`
- `swiftui/scripts/run-local.sh`
- `swiftui/scripts/realm-harness.sh`
- runtime binaries owned by overlay repo (`../cyber-nas-overlay`)

Shared contracts were moved to:

- `shared/interface-contracts/swift/ClientAPI.swift`
- `shared/interface-contracts/swift/APITypes.swift`
- canonical CLI JSON contract: `../cyber-nas-overlay/spki/docs/CLI_JSON_API.md`
- mirror copy in this repo: `shared/interface-contracts/cli/CLI_JSON_API.md`

This split keeps platform-agnostic contracts in one place for reuse by Linux/Windows clients.

Note:
- `swiftui/api/ClientAPI.swift` and `swiftui/models/APITypes.swift` are mirrored
  copies for editor/indexing stability in this staged tree.
- Canonical contract edits should still be made in `shared/interface-contracts/`.
