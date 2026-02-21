#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

find_repo_root() {
  local dir="$SCRIPT_DIR"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/macos/swiftui/Package.swift" ]]; then
      printf "%s" "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

SPKI_ROOT="$(find_repo_root || true)"
UI_ROOT="${SPKI_ROOT:+$SPKI_ROOT/macos/swiftui}"
DEFAULT_OVERLAY_ROOT="${SPKI_OVERLAY_ROOT:-$SPKI_ROOT/../cyber-nas-overlay}"
SPKI_BIN_DIR="${SPKI_BIN_DIR:-$DEFAULT_OVERLAY_ROOT/_build/default/bin}"
ENV_FILE="${SPKI_ENV_FILE:-$UI_ROOT/.env}"

if [[ -z "$SPKI_ROOT" ]]; then
  echo "Error: could not locate repo root (missing macos/swiftui/Package.swift)." >&2
  exit 1
fi

if [[ ! -f "$UI_ROOT/Package.swift" ]]; then
  echo "Error: could not locate UI package at $UI_ROOT (missing Package.swift)." >&2
  exit 1
fi

if [[ "${SPKI_SKIP_BUILD:-0}" = "1" ]]; then
  echo "Skipping build (SPKI_SKIP_BUILD=1)"
elif [[ -f "$DEFAULT_OVERLAY_ROOT/dune-project" ]]; then
  if ! command -v dune >/dev/null 2>&1; then
    echo "Error: dune not found. Install with: opam install dune"
    exit 1
  fi
  echo "Building SPKI tools in $DEFAULT_OVERLAY_ROOT..."
  (cd "$DEFAULT_OVERLAY_ROOT" && dune build)
else
  echo "Skipping build (no dune-project at $DEFAULT_OVERLAY_ROOT; expecting SPKI_*_BIN from .env or PATH)"
fi

if [[ -f "$ENV_FILE" ]]; then
  echo "Loading environment from $ENV_FILE"
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

# Allow .env to override after file load.
SPKI_BIN_DIR="${SPKI_BIN_DIR:-$DEFAULT_OVERLAY_ROOT/_build/default/bin}"
export SPKI_BIN_DIR

resolve_spki_bin() {
  local base="$1"
  local hyphen_name="${base//_/-}"
  local exe_path="$SPKI_BIN_DIR/$base.exe"
  local plain_path="$SPKI_BIN_DIR/$base"

  if command -v "$hyphen_name" >/dev/null 2>&1; then
    command -v "$hyphen_name"
    return 0
  fi
  if command -v "$base" >/dev/null 2>&1; then
    command -v "$base"
    return 0
  fi
  if [[ -x "$exe_path" ]]; then
    printf "%s" "$exe_path"
    return 0
  fi
  if [[ -x "$plain_path" ]]; then
    printf "%s" "$plain_path"
    return 0
  fi

  echo "Error: missing executable for $base"
  echo "Checked PATH names: $hyphen_name, $base"
  echo "Checked: $exe_path"
  echo "Checked: $plain_path"
  echo "Set the corresponding SPKI_*_BIN env var or install $hyphen_name on PATH."
  exit 1
}

# OCaml-built tools: resolve from env first, then overlay _build output/PATH.
if [[ -z "${SPKI_SHOW_BIN:-}" ]]; then
  export SPKI_SHOW_BIN="$(resolve_spki_bin spki_show)"
fi
if [[ -z "${SPKI_KEYGEN_BIN:-}" ]]; then
  export SPKI_KEYGEN_BIN="$(resolve_spki_bin spki_keygen)"
fi
if [[ -z "${SPKI_STATUS_BIN:-}" ]]; then
  export SPKI_STATUS_BIN="$(resolve_spki_bin spki_status)"
fi
if [[ -z "${SPKI_REALM_BIN:-}" ]]; then
  export SPKI_REALM_BIN="$(resolve_spki_bin spki_realm)"
fi
if [[ -z "${SPKI_AUDIT_BIN:-}" ]]; then
  export SPKI_AUDIT_BIN="$(resolve_spki_bin spki_audit)"
fi
if [[ -z "${SPKI_VAULT_BIN:-}" ]]; then
  export SPKI_VAULT_BIN="$(resolve_spki_bin spki_vault)"
fi
if [[ -z "${SPKI_CERTS_BIN:-}" ]]; then
  export SPKI_CERTS_BIN="$(resolve_spki_bin spki_certs)"
fi
if [[ -z "${SPKI_AUTHZ_BIN:-}" ]]; then
  export SPKI_AUTHZ_BIN="$(resolve_spki_bin spki_authz)"
fi
export SPKI_KEY_DIR="${SPKI_KEY_DIR:-$HOME/.spki/keys}"
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
