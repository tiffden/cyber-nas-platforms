#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAYER_SCRIPT="$SCRIPT_DIR/../interface-layer/swiftui-spki-bridge/swiftui/scripts/run-local.sh"

if [[ ! -x "$LAYER_SCRIPT" ]]; then
  echo "Error: interface-layer script not found or not executable: $LAYER_SCRIPT" >&2
  exit 1
fi

exec "$LAYER_SCRIPT" "$@"
