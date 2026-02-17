# Cyberspace macOS App Scaffold

SwiftUI-first macOS app scaffold with minimal AppKit bridge points.

- `CyberspaceMac/` app source
- `Tests/` unit and UI tests
- `Scripts/` local build/dev scripts
- `Docs/` app-specific notes

## Buildable Target

This scaffold includes a Swift Package target:

- `Package.swift`
- executable product: `CyberspaceMac`

Open in Xcode:

1. `cd spki/macos/swiftui`
2. `open Package.swift` (or run `./Scripts/open-in-xcode.sh`)
3. Select the `CyberspaceMac` scheme and Run.

## Notes

- The package is intended to be the bootstrap target before creating a full
  `.xcodeproj`/workspace.
- If CLI builds fail, run from Xcode first (toolchain/SDK selection is managed there).

## CLI Bridge Configuration

The app uses `CLIBridgeAPIClient` by default.

- `SPKI_STATUS_BIN`: absolute path to `spki-status` (or `spki_status.exe`)
- `SPKI_SHOW_BIN`: absolute path to `spki-show` (or `spki_show.exe`)
- `SPKI_REALM_BIN`: absolute path to `spki-realm` (or `spki_realm.exe`)
- `SPKI_KEY_DIR`: directory containing key files (`*.public` / `*.pub`)

Defaults:

- show binary resolved from `PATH`
- key directory defaults to `~/.spki/keys`

Bridge behavior:

- tries `spki-status --json` first for `system.status`; falls back to probe mode
- tries `spki-show --json <file>` first for structured parsing
- uses `spki-realm --json --status/--join` for realm operations
- falls back to legacy text output parsing when JSON is unavailable

Contract reference:

- `spki/docs/CLI_JSON_API.md`
