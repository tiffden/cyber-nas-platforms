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

if [[ "${SPKI_SKIP_BUILD:-0}" = "1" ]]; then
  echo "Skipping build (SPKI_SKIP_BUILD=1)"
else
  echo "Building SPKI tools..."
  (cd "$SPKI_ROOT" && dune build)
fi

if [[ -f "$ENV_FILE" ]]; then
  echo "Loading environment from $ENV_FILE"
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

resolve_spki_bin() {
  local base="$1"
  local exe_path="$SPKI_BIN_DIR/$base.exe"
  local plain_path="$SPKI_BIN_DIR/$base"

  if [[ -x "$exe_path" ]]; then
    printf "%s" "$exe_path"
    return 0
  fi
  if [[ -x "$plain_path" ]]; then
    printf "%s" "$plain_path"
    return 0
  fi

  echo "Error: missing executable for $base"
  echo "Checked: $exe_path"
  echo "Checked: $plain_path"
  echo "Try: cd $SPKI_ROOT && make build"
  exit 1
}

# OCaml-built tools: resolve from dune _build output
SHOW_BIN_DEFAULT="$(resolve_spki_bin spki_show)"
KEYGEN_BIN_DEFAULT="$(resolve_spki_bin spki_keygen)"

export SPKI_SHOW_BIN="${SPKI_SHOW_BIN:-$SHOW_BIN_DEFAULT}"
export SPKI_KEYGEN_BIN="${SPKI_KEYGEN_BIN:-$KEYGEN_BIN_DEFAULT}"

# Chez-backed tools: point directly to the .sps scripts (have shebangs, no dune target)
export SPKI_STATUS_BIN="${SPKI_STATUS_BIN:-$SPKI_ROOT/scheme/chez/spki-status.sps}"
export SPKI_REALM_BIN="${SPKI_REALM_BIN:-$SPKI_ROOT/scheme/chez/spki-realm}"
export SPKI_AUDIT_BIN="${SPKI_AUDIT_BIN:-$SPKI_ROOT/scheme/chez/spki-audit.sps}"
export SPKI_VAULT_BIN="${SPKI_VAULT_BIN:-$SPKI_ROOT/scheme/chez/spki-vault.sps}"
export SPKI_CERTS_BIN="${SPKI_CERTS_BIN:-$SPKI_ROOT/scheme/chez/spki-certs.sps}"
export SPKI_AUTHZ_BIN="${SPKI_AUTHZ_BIN:-$SPKI_ROOT/scheme/chez/spki-authz.sps}"
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

if ! command -v swift >/dev/null 2>&1; then
  echo "Error: swift not found. Please install Swift or Xcode Command Line Tools and ensure 'swift' is on your PATH."
  exit 1
fi

SWIFT_BUILD_DIR="${SPKI_SWIFT_BUILD_DIR:-$UI_ROOT/.build}"
UI_BINARY="$SWIFT_BUILD_DIR/debug/CyberspaceMac"

echo "Launching Cyberspace UI..."
cd "$UI_ROOT" || {
  echo "Error: failed to change directory to $UI_ROOT"
  exit 1
}

if [[ "${SPKI_SKIP_UI_BUILD:-0}" = "1" ]]; then
  echo "Skipping SwiftUI build (SPKI_SKIP_UI_BUILD=1)"
else
  echo "Building SwiftUI app binary..."
  if ! swift build -c debug --product CyberspaceMac; then
    status=$?
    echo "Error: failed to build Cyberspace UI (swift exited with status $status)."
    exit "$status"
  fi
fi

if [[ ! -x "$UI_BINARY" ]]; then
  echo "Error: UI binary not found at $UI_BINARY"
  echo "Run from $UI_ROOT and execute: swift build -c debug --product CyberspaceMac"
  exit 1
fi

if "$UI_BINARY"; then
  :
else
  status=$?
  echo "Error: failed to launch Cyberspace UI binary (exit status $status)."
  exit "$status"
fi
