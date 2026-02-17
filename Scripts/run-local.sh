#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPKI_ROOT="$(cd "$UI_ROOT/../.." && pwd)"
SPKI_BIN_DIR="$SPKI_ROOT/_build/default/bin"
ENV_FILE="${SPKI_ENV_FILE:-$UI_ROOT/.env}"

if [[ ! -f "$SPKI_ROOT/dune-project" ]]; then
  echo "Error: could not locate spki root (missing dune-project at $SPKI_ROOT)."
  echo "Run from a checkout where this script lives at spki/macos/swiftui/Scripts."
  exit 1
fi

if ! command -v dune >/dev/null 2>&1; then
  echo "Error: dune not found. Install with: opam install dune"
  exit 1
fi

echo "Building SPKI tools..."
(cd "$SPKI_ROOT" && dune build)

if [[ -f "$ENV_FILE" ]]; then
  echo "Loading environment from $ENV_FILE"
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

for exe in spki_keygen.exe spki_status.exe spki_show.exe spki_realm.exe spki_audit.exe spki_vault.exe spki_certs.exe spki_authz.exe; do
  if [[ ! -x "$SPKI_BIN_DIR/$exe" ]]; then
    echo "Error: missing executable $SPKI_BIN_DIR/$exe"
    echo "Try: cd $SPKI_ROOT && make build"
    exit 1
  fi
done

export SPKI_STATUS_BIN="${SPKI_STATUS_BIN:-$SPKI_BIN_DIR/spki_status.exe}"
export SPKI_SHOW_BIN="${SPKI_SHOW_BIN:-$SPKI_BIN_DIR/spki_show.exe}"
export SPKI_KEYGEN_BIN="${SPKI_KEYGEN_BIN:-$SPKI_BIN_DIR/spki_keygen.exe}"
export SPKI_REALM_BIN="${SPKI_REALM_BIN:-$SPKI_BIN_DIR/spki_realm.exe}"
export SPKI_AUDIT_BIN="${SPKI_AUDIT_BIN:-$SPKI_BIN_DIR/spki_audit.exe}"
export SPKI_VAULT_BIN="${SPKI_VAULT_BIN:-$SPKI_BIN_DIR/spki_vault.exe}"
export SPKI_CERTS_BIN="${SPKI_CERTS_BIN:-$SPKI_BIN_DIR/spki_certs.exe}"
export SPKI_AUTHZ_BIN="${SPKI_AUTHZ_BIN:-$SPKI_BIN_DIR/spki_authz.exe}"
export SPKI_KEY_DIR="${SPKI_KEY_DIR:-$HOME/.spki/keys}"
export SPKI_CHEZ_SCRIPT="${SPKI_CHEZ_SCRIPT:-$SPKI_ROOT/scheme/chez/spki-realm.sps}"
export SPKI_CHEZ_STATUS_SCRIPT="${SPKI_CHEZ_STATUS_SCRIPT:-$SPKI_ROOT/scheme/chez/spki-status.sps}"
export SPKI_CHEZ_SHOW_SCRIPT="${SPKI_CHEZ_SHOW_SCRIPT:-$SPKI_ROOT/scheme/chez/spki-show-bridge.sps}"
export SPKI_CHEZ_KEYGEN_SCRIPT="${SPKI_CHEZ_KEYGEN_SCRIPT:-$SPKI_ROOT/scheme/chez/spki-keygen.sps}"
export SPKI_CHEZ_CERTS_SCRIPT="${SPKI_CHEZ_CERTS_SCRIPT:-$SPKI_ROOT/scheme/chez/spki-certs.sps}"
export SPKI_CHEZ_AUTHZ_SCRIPT="${SPKI_CHEZ_AUTHZ_SCRIPT:-$SPKI_ROOT/scheme/chez/spki-authz.sps}"
export SPKI_CHEZ_AUDIT_SCRIPT="${SPKI_CHEZ_AUDIT_SCRIPT:-$SPKI_ROOT/scheme/chez/spki-audit.sps}"
export SPKI_CHEZ_VAULT_SCRIPT="${SPKI_CHEZ_VAULT_SCRIPT:-$SPKI_ROOT/scheme/chez/spki-vault.sps}"
export SPKI_CHEZ_LIBDIR="${SPKI_CHEZ_LIBDIR:-$SPKI_ROOT/scheme/chez}"
export SPKI_REALM_WORKDIR="${SPKI_REALM_WORKDIR:-$SPKI_ROOT/scheme/chez}"
export PATH="$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

echo "Launching Cyberspace UI..."
cd "$UI_ROOT"
swift run CyberspaceMac
