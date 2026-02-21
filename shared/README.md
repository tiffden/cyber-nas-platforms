# Shared Contracts (Plain English)

This folder holds the "agreement" files that different apps use to talk to the same backend behavior.

Think of a contract as:

- what requests can be made
- what data comes back
- what field names mean

If macOS, Linux, and Windows all follow the same contract, they can share backend tooling without guessing.

## Start Here

- `shared/interface-contracts/swift/ClientAPI.swift`
  - The list of operations the app can ask for (create test environment, join realm, read logs, clean up, etc).

- `shared/interface-contracts/swift/APITypes.swift`
  - The shapes of data used by those operations (errors, node metadata, config objects, response objects).

- `../cyber-nas-overlay/spki/docs/CLI_JSON_API.md` (canonical)
  - The JSON format expected from command-line tools (`spki-*` commands).
  - Server/backend owns this contract in overlay.
- `shared/interface-contracts/cli/CLI_JSON_API.md` (mirror)
  - Compatibility copy for this repo; do not edit directly.

## When To Edit Which File

- "I need a new app action" -> update `ClientAPI.swift`
- "I need a new field in a response" -> update `APITypes.swift` (and then implement it in clients/backends)
- "CLI output changed / new JSON key" -> update `../cyber-nas-overlay/spki/docs/CLI_JSON_API.md`

## Important Rule

If you change a contract file, update all users of that contract:

- app-side code (macOS/Linux/Windows clients)
- backend/bridge code (CLI wrappers, scripts, adapters)

Otherwise one side will send data the other side does not understand.

## Where Platform-Specific Code Lives

Contracts are shared here, but platform-specific implementation stays in each platform area.
For macOS SwiftUI bridge code, see:

- `macos/swiftui/interface-layer/swiftui-spki-bridge/`
