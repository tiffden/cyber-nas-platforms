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

Run without Xcode UI:

1. `cd spki`
2. `make ui-run` (foreground, terminal stays attached)
3. `make ui-run-bg` (background, prompt returns immediately)

This launcher builds SPKI CLIs and exports all required `SPKI_*_BIN` paths to
the local `_build/default/bin` outputs before running `swift run CyberspaceMac`.
For background mode, logs are written to `/tmp/cyberspace-ui.log`.

Optional `.env` support:

1. `cd spki/macos/swiftui`
2. `cp .env.example .env`
3. Set `SPKI_KEY_DIR` (and any optional `SPKI_*_BIN` overrides)

The launcher auto-loads `spki/macos/swiftui/.env`. You can override the file
path with `SPKI_ENV_FILE=/path/to/file`.

## Notes

- The package is intended to be the bootstrap target before creating a full
  `.xcodeproj`/workspace.
- If CLI builds fail, run from Xcode first (toolchain/SDK selection is managed there).

## CLI Bridge Configuration

The app uses `CLIBridgeAPIClient` by default.

- `SPKI_STATUS_BIN`: absolute path to `spki-status` (or `spki_status.exe`)
- `SPKI_SHOW_BIN`: absolute path to `spki-show` (or `spki_show.exe`)
- `SPKI_KEYGEN_BIN`: absolute path to `spki-keygen` (or `spki_keygen.exe`)
- `SPKI_REALM_BIN`: absolute path to `spki-realm` (or `spki_realm.exe`)
- `SPKI_CHEZ_BIN`: Chez executable name/path used by `spki-realm` backend
- `SPKI_CHEZ_SCRIPT`: path to `spki/scheme/chez/spki-realm.sps`
- `SPKI_CHEZ_STATUS_SCRIPT`: path to `spki/scheme/chez/spki-status.sps`
- `SPKI_CHEZ_SHOW_SCRIPT`: path to `spki/scheme/chez/spki-show-bridge.sps`
- `SPKI_CHEZ_KEYGEN_SCRIPT`: path to `spki/scheme/chez/spki-keygen.sps`
- `SPKI_CHEZ_CERTS_SCRIPT`: path to `spki/scheme/chez/spki-certs.sps`
- `SPKI_CHEZ_AUTHZ_SCRIPT`: path to `spki/scheme/chez/spki-authz.sps`
- `SPKI_CHEZ_AUDIT_SCRIPT`: path to `spki/scheme/chez/spki-audit.sps`
- `SPKI_CHEZ_VAULT_SCRIPT`: path to `spki/scheme/chez/spki-vault.sps`
- `SPKI_CHEZ_LIBDIR`: path to `spki/scheme/chez` for `(cyberspace ...)` imports
- `SPKI_REALM_WORKDIR`: working directory containing realm state/runtime libs (default: `spki/scheme/chez`)
- `SPKI_AUDIT_BIN`: absolute path to `spki-audit` (or `spki_audit.exe`)
- `SPKI_VAULT_BIN`: absolute path to `spki-vault` (or `spki_vault.exe`)
- `SPKI_CERTS_BIN`: absolute path to `spki-certs` (or `spki_certs.exe`)
- `SPKI_AUTHZ_BIN`: absolute path to `spki-authz` (or `spki_authz.exe`)
- `SPKI_KEY_DIR`: directory containing key files (`*.public` / `*.pub`)

Defaults:

- show binary resolved from `PATH`
- key directory defaults to `~/.spki/keys`

Bridge behavior:

- tries `spki-status --json` first for `system.status`; falls back to probe mode
- tries `spki-show --json <file>` first for structured parsing
- uses `spki-keygen --json --output-dir <dir> --name <name>` for key generation
- `spki-status` and `spki-show` now delegate to Chez bridge scripts for backend-backed output
- uses `spki-realm --json --status/--join` for realm operations
  - `spki-realm` now delegates to Chez `(cyberspace auto-enroll)` via `spki/scheme/chez/spki-realm.sps`
- uses `spki-audit --json --query` for audit operations
- `spki-audit` now delegates to Chez bridge script `spki/scheme/chez/spki-audit.sps`
- uses `spki-vault --json --get/--put/--commit` for vault operations
- `spki-vault` now delegates to Chez bridge script `spki/scheme/chez/spki-vault.sps`
- uses `spki-certs --json --create/--sign/--verify` for certificate operations
- `spki-certs` now delegates to Chez bridge script `spki/scheme/chez/spki-certs.sps`
- uses `spki-authz --json --verify-chain` for authorization chain checks
- `spki-authz` now delegates to Chez bridge script `spki/scheme/chez/spki-authz.sps`
- falls back to legacy text output parsing when JSON is unavailable

Contract reference:

- `spki/docs/CLI_JSON_API.md`
