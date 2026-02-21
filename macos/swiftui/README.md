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

1. `cd macos/swiftui`
2. `open Package.swift` (or run `./Scripts/open-in-xcode.sh`)
3. Select the `CyberspaceMac` scheme and Run.

Run without Xcode UI:

1. `cd macos/swiftui`
2. `./Scripts/run-local.sh` (foreground, terminal stays attached)
3. `SPKI_SKIP_UI_BUILD=1 ./Scripts/run-local.sh` (reuse existing UI build)

This launcher resolves `spki-*` binaries from `SPKI_BIN_DIR` (default:
`../cyber-nas-overlay/_build/default/bin`) and then runs `swift run CyberspaceMac`.

Optional `.env` support:

1. `cd macos/swiftui`
2. `cp .env.example .env`
3. Set `SPKI_KEY_DIR` (and any optional `SPKI_*_BIN` overrides)

The launcher auto-loads `macos/swiftui/.env`. You can override the file
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
- `SPKI_BIN_DIR`: directory containing SPKI executables (default: `../cyber-nas-overlay/_build/default/bin`); used as shared lookup before `PATH`
- `SPKI_OVERLAY_ROOT`: optional overlay repo root override used by scripts (default: `../cyber-nas-overlay`)
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
- uses `spki-realm --json --status/--join` for realm operations
- uses `spki-audit --json --query` for audit operations
- uses `spki-vault --json --get/--put/--commit` for vault operations
- uses `spki-certs --json --create/--sign/--verify` for certificate operations
- uses `spki-authz --json --verify-chain` for authorization chain checks
- falls back to legacy text output parsing when JSON is unavailable

Contract reference:

- canonical: `../cyber-nas-overlay/spki/docs/CLI_JSON_API.md`
- mirror in this repo: `shared/interface-contracts/cli/CLI_JSON_API.md` (read-only compatibility copy)
