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
export SPKI_BIN_DIR
# Keep harness data out of the repo and away from normal runtime state by default.
HARNESS_ROOT="${SPKI_REALM_HARNESS_ROOT:-$HOME/.cyberspace/testbed}"
HARNESS_LOG_FILE="${SPKI_REALM_HARNESS_LOG_FILE:-$HARNESS_ROOT/harness.log}"
DEFAULT_NODES=3
DEFAULT_REALM_NAME="${SPKI_REALM_HARNESS_NAME:-local-realm}"
DEFAULT_MASTER_HOST="${SPKI_REALM_HARNESS_HOST:-127.0.0.1}"
DEFAULT_MASTER_PORT="${SPKI_REALM_HARNESS_PORT:-7780}"

if [[ -z "$SPKI_ROOT" ]]; then
  echo "Error: could not locate repo root (missing macos/swiftui/Package.swift)." >&2
  exit 1
fi

if [[ ! -f "$UI_ROOT/Package.swift" ]]; then
  echo "Error: could not locate UI package at $UI_ROOT (missing Package.swift)." >&2
  exit 1
fi

json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf "%s" "$value"
}

log_event() {
  local level="$1"
  local action="$2"
  local result="$3"
  local message="${4:-}"
  local request_id="${SPKI_REQUEST_ID:-n/a}"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local line
  line="{\"ts\":\"$(json_escape "$ts")\",\"level\":\"$(json_escape "$level")\",\"component\":\"realm_harness\",\"action\":\"$(json_escape "$action")\",\"result\":\"$(json_escape "$result")\",\"request_id\":\"$(json_escape "$request_id")\",\"pid\":\"$$\""
  if [[ -n "$message" ]]; then
    line="${line},\"message\":\"$(json_escape "$message")\""
  fi
  line="${line}}"

  echo "$line" >&2
  mkdir -p "$(dirname "$HARNESS_LOG_FILE")" >/dev/null 2>&1 || true
  echo "$line" >>"$HARNESS_LOG_FILE" 2>/dev/null || true
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  init [N]           Create N isolated node workdirs (default: ${DEFAULT_NODES})
  status [N]         Show realm status for each node
  self-join [N]      Join node1 to the configured realm endpoint
  join-all [N]       Join nodes 2..N to node1 (${DEFAULT_MASTER_HOST}:${DEFAULT_MASTER_PORT})
  join-one <ID>      Join a single node by ID (ID must be >= 2)
  listen-bg [N]      Open join listener(s) for nodes 1..N in background (mDNS + TCP)
  stop-listen-bg [N] Stop background join listener(s) started by listen-bg
  vault-put <ID> <KEY> <VALUE>
                    Put VALUE at KEY for node ID using that node's isolated .vault
  vault-get <ID> <KEY>
                    Get KEY for node ID using that node's isolated .vault
  vault-commit <ID> [MESSAGE]
                    Commit current vault state for node ID (MESSAGE optional)
  seal-commit <ID> <MESSAGE>
                    Run Chez seal commit for node ID
  seal-release <ID> <VERSION> [MESSAGE]
                    Run Chez seal release for node ID
  seal-verify <ID> <VERSION>
                    Run Chez seal verify for node ID
  seal-archive <ID> <VERSION> [FORMAT]
                    Run Chez seal archive for node ID (default FORMAT: zstd-age)
  ui <NODE_ID>       Launch one SwiftUI instance using NODE_ID environment
  ui-all-bg [N]      Launch N SwiftUI instances in background with isolated env
  stop-all-bg [N]    Stop background SwiftUI instances started by ui-all-bg
  env <NODE_ID>      Print node env file path
  clean              Remove harness data at ${HARNESS_ROOT}

Notes:
  - Each machine gets its own top-level directory under:
      ${HARNESS_ROOT}/<machine-name>/
    Node runtime state is nested under:
      <machine-name>/<realm-name>/<node-name>/
    Machine names come from SPKI_REALM_HARNESS_NODE_NAMES (or SPKI_DEFAULT_NODE_NAMES),
    stored in machine.env as SPKI_MACHINE_NAME.
  - UI launch reuses run-local.sh with SPKI_ENV_FILE + SPKI_SKIP_BUILD=1.
EOF
}

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
  echo "Error: missing executable for $base" >&2
  echo "Checked PATH names: $hyphen_name, $base" >&2
  echo "Checked: $exe_path" >&2
  echo "Checked: $plain_path" >&2
  echo "Set the corresponding SPKI_*_BIN env var or install $hyphen_name on PATH." >&2
  exit 1
}

# Return the top-level directory for a virtual machine.
machine_dir() {
  local id="$1"
  local name
  name="$(resolve_node_name "$id")"
  printf "%s/%s" "$HARNESS_ROOT" "$name"
}

# Realm-scoped runtime root for a machine.
realm_dir() {
  local id="$1"
  printf "%s/%s" "$(machine_dir "$id")" "$DEFAULT_REALM_NAME"
}

# Node runtime root under machine/realm.
node_runtime_dir() {
  local id="$1"
  local name
  if [[ "$id" == "1" ]] && [[ -n "${SPKI_BOOTSTRAP_NODE_NAME:-}" ]]; then
    name="$SPKI_BOOTSTRAP_NODE_NAME"
  elif [[ "$id" != "1" ]] && [[ -n "${SPKI_JOIN_NODE_NAME:-}" ]]; then
    name="$SPKI_JOIN_NODE_NAME"
  else
    name="$(resolve_node_name "$id")"
  fi
  printf "%s/%s" "$(realm_dir "$id")" "$name"
}

node_dir() { machine_dir "$1"; }

harness_generated_dir() {
  local id="$1"
  printf "%s/harness-generated" "$(machine_dir "$id")"
}

node_env_file() {
  local id="$1"
  printf "%s/node.env" "$(harness_generated_dir "$id")"
}

machine_env_file() {
  local id="$1"
  printf "%s/machine.env" "$(harness_generated_dir "$id")"
}

write_machine_env() {
  local id="$1"
  local machine_root machine_name port
  machine_root="$(machine_dir "$id")"
  machine_name="$(resolve_node_name "$id")"
  port=$((DEFAULT_MASTER_PORT + id - 1))

  mkdir -p "$(harness_generated_dir "$id")"
  cat >"$(machine_env_file "$id")" <<EOF
# Generated by realm-harness.sh -- machine listener config for machine ${id}.
SPKI_MACHINE_ID="${id}"
SPKI_MACHINE_NAME="${machine_name}"
SPKI_NODE_PORT="${port}"
SPKI_JOIN_HOST="${DEFAULT_MASTER_HOST}"
SPKI_JOIN_PORT="${DEFAULT_MASTER_PORT}"
SPKI_REALM_HARNESS_ROOT="${HARNESS_ROOT}"
SPKI_TESTBED_MODE="1"
EOF
}

load_machine_env() {
  local id="$1"
  local env_file
  env_file="$(machine_env_file "$id")"
  if [[ ! -f "$env_file" ]]; then
    echo "Error: machine env not found: $env_file" >&2
    echo "Run: $(basename "$0") init" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$env_file"
}

write_node_env() {
  local id="$1"
  local machine_root runtime_root
  machine_root="$(machine_dir "$id")"
  runtime_root="$(node_runtime_dir "$id")"
  local workdir="$runtime_root"
  local keydir="$runtime_root/keys"
  local logdir="$runtime_root/logs"
  local node_name
  if [[ "$id" == "1" ]] && [[ -n "${SPKI_BOOTSTRAP_NODE_NAME:-}" ]]; then
    node_name="$SPKI_BOOTSTRAP_NODE_NAME"
  elif [[ "$id" != "1" ]] && [[ -n "${SPKI_JOIN_NODE_NAME:-}" ]]; then
    node_name="$SPKI_JOIN_NODE_NAME"
  else
    node_name="$(resolve_node_name "$id")"
  fi
  local port=$((DEFAULT_MASTER_PORT + id - 1))
  local node_uuid
  node_uuid="$(uuidgen | tr '[:upper:]' '[:lower:]')"

  rm -rf "$workdir/.vault" "$keydir"
  mkdir -p "$workdir/.vault" "$keydir" "$logdir"
  : >"$logdir/node.log"
  : >"$logdir/realm.log"
  rm -f "$logdir/ui.pid"

  cat >"$(node_env_file "$id")" <<EOF
# Generated by realm-harness.sh for node ${id}
SPKI_REALM_WORKDIR="${workdir}"
SPKI_KEY_DIR="${keydir}"
SPKI_NODE_ID="${id}"
SPKI_NODE_NAME="${node_name}"
SPKI_NODE_UUID="${node_uuid}"
SPKI_NODE_PORT="${port}"
SPKI_NODE_LOG_DIR="${logdir}"
SPKI_REALM_NAME="${DEFAULT_REALM_NAME}"
SPKI_JOIN_HOST="${DEFAULT_MASTER_HOST}"
SPKI_JOIN_PORT="${DEFAULT_MASTER_PORT}"
SPKI_REALM_HARNESS_ROOT="${HARNESS_ROOT}"
SPKI_TESTBED_MODE="1"
SPKI_BIN_DIR="${SPKI_BIN_DIR}"
EOF
}

resolve_node_name() {
  local id="$1"
  local fallback="node${id}"
  local csv="${SPKI_DEFAULT_NODE_NAMES:-}"
  if [[ -z "$csv" ]]; then
    printf "%s" "$fallback"
    return 0
  fi

  local index=$((id - 1))
  local raw
  IFS=',' read -r -a names <<<"$csv"
  if (( index < 0 || index >= ${#names[@]} )); then
    printf "%s" "$fallback"
    return 0
  fi

  raw="${names[$index]}"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  if [[ -z "$raw" ]]; then
    printf "%s" "$fallback"
    return 0
  fi
  printf "%s" "$raw"
}

load_node_env() {
  local id="$1"
  local env_file
  env_file="$(node_env_file "$id")"
  if [[ ! -f "$env_file" ]]; then
    echo "Error: node env not found: $env_file" >&2
    echo "Run bootstrap first: $(basename "$0") self-join 1 (then join-all as needed)." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$env_file"
  export SPKI_REALM_WORKDIR SPKI_BIN_DIR SPKI_NODE_NAME SPKI_NODE_UUID \
         SPKI_NODE_PORT SPKI_KEY_DIR SPKI_NODE_LOG_DIR SPKI_TESTBED_MODE \
         SPKI_REALM_NAME SPKI_JOIN_HOST SPKI_JOIN_PORT
}

ensure_build() {
  if [[ -n "${SPKI_SKIP_BUILD:-}" ]]; then
    return 0
  fi
  if command -v spki-realm >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "${SPKI_BIN_DIR:-}/spki-realm" ]]; then
    return 0
  fi
  if [[ -x "${SPKI_BIN_DIR:-}/spki_realm.exe" ]]; then
    return 0
  fi
  if ! command -v dune >/dev/null 2>&1; then
    echo "Error: spki-realm not found on PATH and dune is not installed." >&2
    echo "Install with: cd ~/dev/cyber-nas-overlay/spki && make install" >&2
    exit 1
  fi
  if [[ ! -f "$DEFAULT_OVERLAY_ROOT/dune-project" ]]; then
    echo "Error: could not find dune-project at $DEFAULT_OVERLAY_ROOT" >&2
    echo "Set SPKI_OVERLAY_ROOT or SPKI_BIN_DIR to your overlay build output." >&2
    exit 1
  fi
  echo "Building SPKI binaries in $DEFAULT_OVERLAY_ROOT..."
  (cd "$DEFAULT_OVERLAY_ROOT" && dune build)
}

run_realm_for_node() {
  local id="$1"
  shift
  load_node_env "$id"
  local realm_bin
  local node_log
  realm_bin="${SPKI_REALM_BIN:-$(resolve_spki_bin spki_realm)}"
  node_log="${SPKI_NODE_LOG_DIR:-$(node_runtime_dir "$id")/logs}/realm.log"
  mkdir -p "$(dirname "$node_log")"
  (
    "$realm_bin" "$@" \
      > >(tee -a "$node_log") \
      2> >(tee -a "$node_log" >&2)
  )
}

run_vault_for_node() {
  local id="$1"
  shift
  load_node_env "$id"
  local vault_bin
  local node_log
  local vault_root
  vault_bin="${SPKI_VAULT_BIN:-$(resolve_spki_bin spki_vault)}"
  node_log="${SPKI_NODE_LOG_DIR:-$(node_runtime_dir "$id")/logs}/realm.log"
  vault_root="${SPKI_REALM_WORKDIR}/.vault"
  mkdir -p "$(dirname "$node_log")"
  mkdir -p "$vault_root"
  (
    cd "$vault_root"
    "$vault_bin" --json "$@" \
      > >(tee -a "$node_log") \
      2> >(tee -a "$node_log" >&2)
  )
}

run_seal_for_node() {
  local id="$1"
  shift
  load_node_env "$id"
  local seal_bin
  local node_log
  local crypto_bridge
  local candidate
  seal_bin="${SPKI_SEAL_BIN:-$DEFAULT_OVERLAY_ROOT/spki/scheme/chez/bin/seal.sps}"
  node_log="${SPKI_NODE_LOG_DIR:-$(node_runtime_dir "$id")/logs}/realm.log"
  mkdir -p "$(dirname "$node_log")"
  if [[ ! -x "$seal_bin" ]]; then
    echo "Error: Chez seal binary not found or not executable: $seal_bin" >&2
    echo "Set SPKI_SEAL_BIN to your overlay Chez seal executable." >&2
    exit 1
  fi
  # Initialize .vault/ directory structure used by seal flows.
  mkdir -p "${SPKI_REALM_WORKDIR}/.vault/objects" \
           "${SPKI_REALM_WORKDIR}/.vault/metadata" \
           "${SPKI_REALM_WORKDIR}/.vault/releases" \
           "${SPKI_REALM_WORKDIR}/.vault/audit" \
           "${SPKI_REALM_WORKDIR}/.vault/subscriptions" \
           "${SPKI_REALM_WORKDIR}/migrations"
  # Resolve crypto bridge dylib and expose it via:
  # 1) workdir symlink: ./libcrypto-bridge.dylib (first path checked by crypto-ffi)
  # 2) DYLD_LIBRARY_PATH fallback for bare-name loading.
  for candidate in \
    "${SPKI_CRYPTO_BRIDGE_DYLIB:-}" \
    "$DEFAULT_OVERLAY_ROOT/spki/scheme/chez/libcrypto-bridge.dylib" \
    "$DEFAULT_OVERLAY_ROOT/spki/scheme/swift/chez/Cyberspace.app/Contents/Resources/libcrypto-bridge.dylib"
  do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      crypto_bridge="$candidate"
      break
    fi
  done
  if [[ -z "${crypto_bridge:-}" ]]; then
    echo "Error: libcrypto-bridge.dylib not found." >&2
    echo "Checked SPKI_CRYPTO_BRIDGE_DYLIB, chez/, and swift/chez app resources under: $DEFAULT_OVERLAY_ROOT" >&2
    echo "Build it with: $DEFAULT_OVERLAY_ROOT/spki/scheme/chez/build-crypto-bridge.sh" >&2
    exit 1
  fi
  ln -sf "$crypto_bridge" "${SPKI_REALM_WORKDIR}/libcrypto-bridge.dylib"
  local dylib_dir
  dylib_dir="$(dirname "$crypto_bridge")"
  (
    cd "$SPKI_REALM_WORKDIR"
    DYLD_LIBRARY_PATH="${dylib_dir}${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
      "$seal_bin" "$@" \
      > >(tee -a "$node_log") \
      2> >(tee -a "$node_log" >&2)
  )
}

cmd_init() {
  local count="${1:-$DEFAULT_NODES}"
  if ! [[ "$count" =~ ^[0-9]+$ ]] || (( count < 1 )); then
    echo "Error: node count must be a positive integer" >&2
    exit 1
  fi
  log_event "info" "harness.init" "start" "nodes=${count}"
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  mkdir -p "$HARNESS_ROOT"
  for id in $(seq 1 "$count"); do
    write_machine_env "$id"
    log_event "info" "harness.init" "machine_ready" "id=${id} path=$(machine_dir "$id")"
  done
  echo "Created ${count} machine directories under ${HARNESS_ROOT}"
  log_event "info" "harness.init" "ok" "nodes=${count}"
}

cmd_self_join() {
  log_event "info" "harness.self_join" "start" "node=1"
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  ensure_build
  load_machine_env 1
  write_node_env 1
  load_node_env 1
  echo "Bootstrapping realm ${DEFAULT_REALM_NAME} on machine 1 (${DEFAULT_MASTER_HOST}:${SPKI_NODE_PORT})"
  cmd_stop_listen_bg 1 2>/dev/null || true
  run_realm_for_node 1 --json --start-realm --name "$SPKI_NODE_NAME" --port "$SPKI_NODE_PORT"
  cmd_listen_bg 1
  log_event "info" "harness.self_join" "ok" "node=1"
}

cmd_join_all() {
  local count="${1:-$DEFAULT_NODES}"
  if (( count < 2 )); then
    echo "Need at least 2 nodes for join-all" >&2
    exit 1
  fi
  log_event "info" "harness.join_all" "start" "nodes=${count}"
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  ensure_build
  for id in $(seq 2 "$count"); do
    load_machine_env "$id"
    write_node_env "$id"
    load_node_env "$id"
    echo "Joining machine ${id} (${SPKI_MACHINE_NAME}) -> ${DEFAULT_MASTER_HOST}:${DEFAULT_MASTER_PORT}"
    run_realm_for_node "$id" --json --join --name "$SPKI_NODE_NAME" --host "$DEFAULT_MASTER_HOST" --port "$DEFAULT_MASTER_PORT"
    _start_listener_for_node "$id"
  done
  log_event "info" "harness.join_all" "ok" "nodes=${count}"
}

cmd_join_one() {
  local id="${1:-}"
  if [[ -z "$id" ]] || ! [[ "$id" =~ ^[0-9]+$ ]] || (( id < 2 )); then
    echo "Usage: $(basename "$0") join-one <ID>  (ID must be >= 2)" >&2
    exit 1
  fi
  log_event "info" "harness.join_one" "start" "node=${id}"
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  ensure_build
  load_machine_env "$id"
  write_node_env "$id"
  load_node_env "$id"
  echo "Joining machine ${id} (${SPKI_MACHINE_NAME}) -> ${DEFAULT_MASTER_HOST}:${DEFAULT_MASTER_PORT}"
  run_realm_for_node "$id" --json --join --name "$SPKI_NODE_NAME" --host "$DEFAULT_MASTER_HOST" --port "$DEFAULT_MASTER_PORT"
  _start_listener_for_node "$id"
  log_event "info" "harness.join_one" "ok" "node=${id}"
}

cmd_stop_all_bg() {
  local count="${1:-$DEFAULT_NODES}"
  log_event "info" "harness.stop_all_bg" "start" "nodes=${count}"
  for id in $(seq 1 "$count"); do
    local env_file log_file pid_file
    env_file="$(node_env_file "$id")"
    if [[ ! -f "$env_file" ]]; then
      echo "node${id} no env file (already cleaned)"
      continue
    fi
    load_node_env "$id"
    log_file="${SPKI_NODE_LOG_DIR:-$(node_runtime_dir "$id")/logs}/node.log"
    pid_file="${SPKI_NODE_LOG_DIR:-$(node_runtime_dir "$id")/logs}/ui.pid"
    if [[ ! -f "$pid_file" ]]; then
      echo "node${id} no PID file (already stopped)"
      continue
    fi

    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -z "$pid" ]]; then
      rm -f "$pid_file"
      echo "node${id} PID file empty (cleaned)"
      continue
    fi

    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      echo "node${id} stopped PID ${pid} (log: $log_file)"
    else
      echo "node${id} PID ${pid} not running (cleaned)"
    fi
    rm -f "$pid_file"
  done
  log_event "info" "harness.stop_all_bg" "ok" "nodes=${count}"
}

listener_pid_file() {
  local id="$1"
  printf "%s/listener.pid" "$(harness_generated_dir "$id")"
}

listener_mdns_pid_file() {
  local id="$1"
  printf "%s/listener-mdns.pid" "$(harness_generated_dir "$id")"
}

_start_listener_for_node() {
  local id="$1"
  local realm_bin="${SPKI_REALM_BIN:-$(resolve_spki_bin spki_realm)}"
  local pid_file
  pid_file="$(listener_pid_file "$id")"
  if [[ -f "$pid_file" ]]; then
    local existing_pid
    existing_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" >/dev/null 2>&1; then
      echo "node${id} listener already running as PID ${existing_pid}"
      return 0
    fi
    rm -f "$pid_file"
  fi
  load_machine_env "$id"
  load_node_env "$id"
  local log_file="${SPKI_NODE_LOG_DIR}/realm.log"
  mkdir -p "$(dirname "$log_file")"
  local stale_pids
  stale_pids="$(lsof -ti "tcp:${SPKI_NODE_PORT}" 2>/dev/null || true)"
  if [[ -n "$stale_pids" ]]; then
    echo "$stale_pids" | xargs kill 2>/dev/null || true
    sleep 0.3
    log_event "info" "harness.listen_bg" "killed_stale" "node=${id} port=${SPKI_NODE_PORT} pids=${stale_pids}"
  fi
  "$realm_bin" --listen --name "$SPKI_NODE_NAME" --port "$SPKI_NODE_PORT" \
    >> "$log_file" 2>&1 &
  echo "$!" > "$pid_file"
  echo "node${id} listener PID $! (port ${SPKI_NODE_PORT}, log: $log_file)"
  log_event "info" "harness.listen_bg" "ok" "node=${id} pid=$! port=${SPKI_NODE_PORT}"
  local mdns_pid_file
  mdns_pid_file="$(listener_mdns_pid_file "$id")"
  if [[ -f "$mdns_pid_file" ]]; then
    local old_mdns_pid
    old_mdns_pid="$(cat "$mdns_pid_file" 2>/dev/null || true)"
    [[ -n "$old_mdns_pid" ]] && kill "$old_mdns_pid" 2>/dev/null || true
    rm -f "$mdns_pid_file"
  fi
  if command -v /usr/bin/dns-sd >/dev/null 2>&1; then
    local mdns_title="${SPKI_REALM_NAME} : ${SPKI_NODE_NAME}"
    /usr/bin/dns-sd -R "$mdns_title" _cyberspace._tcp local "$SPKI_NODE_PORT" \
      "Realm=${SPKI_REALM_NAME}" "UUID=${SPKI_NODE_UUID}" \
      >> "$log_file" 2>&1 &
    echo "$!" > "$mdns_pid_file"
    echo "node${id} mDNS registered '${mdns_title}' _cyberspace._tcp port ${SPKI_NODE_PORT} realm=${SPKI_REALM_NAME} uuid=${SPKI_NODE_UUID} (PID $!)"
    log_event "info" "harness.listen_bg" "mdns_registered" "node=${id} name=${SPKI_NODE_NAME} port=${SPKI_NODE_PORT} realm=${SPKI_REALM_NAME} uuid=${SPKI_NODE_UUID} pid=$!"
  else
    log_event "warn" "harness.listen_bg" "mdns_skipped" "node=${id} dns-sd not found at /usr/bin/dns-sd"
  fi
}

cmd_listen_bg() {
  local count="${1:-1}"
  log_event "info" "harness.listen_bg" "start" "nodes=${count}"
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  for id in $(seq 1 "$count"); do
    _start_listener_for_node "$id"
  done
}

cmd_stop_listen_bg() {
  local count="${1:-1}"
  log_event "info" "harness.stop_listen_bg" "start" "nodes=${count}"
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  for id in $(seq 1 "$count"); do
    local pid_file
    pid_file="$(listener_pid_file "$id")"
    if [[ ! -f "$pid_file" ]]; then
      echo "node${id} no listener PID file (already stopped)"
    else
      local pid
      pid="$(cat "$pid_file" 2>/dev/null || true)"
      if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid"
        echo "node${id} listener stopped (PID ${pid})"
        log_event "info" "harness.stop_listen_bg" "ok" "node=${id} pid=${pid}"
      else
        echo "node${id} listener not running (PID ${pid:-unknown})"
      fi
      rm -f "$pid_file"
    fi
    local mdns_pid_file
    mdns_pid_file="$(listener_mdns_pid_file "$id")"
    if [[ -f "$mdns_pid_file" ]]; then
      local mdns_pid
      mdns_pid="$(cat "$mdns_pid_file" 2>/dev/null || true)"
      if [[ -n "$mdns_pid" ]] && kill -0 "$mdns_pid" >/dev/null 2>&1; then
        kill "$mdns_pid"
        echo "node${id} mDNS unregistered (PID ${mdns_pid})"
        log_event "info" "harness.stop_listen_bg" "mdns_stopped" "node=${id} pid=${mdns_pid}"
      fi
      rm -f "$mdns_pid_file"
    fi
  done
}

cmd_vault_put() {
  local id="${1:-}"
  local key="${2:-}"
  local value="${3:-}"
  if [[ -z "$id" || -z "$key" ]]; then
    echo "Usage: $(basename "$0") vault-put <NODE_ID> <KEY> <VALUE>" >&2
    exit 1
  fi
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  log_event "info" "harness.vault_put" "start" "node=${id} key=${key}"
  run_vault_for_node "$id" --put --key "$key" --value "$value"
  log_event "info" "harness.vault_put" "ok" "node=${id} key=${key}"
}

cmd_vault_get() {
  local id="${1:-}"
  local key="${2:-}"
  if [[ -z "$id" || -z "$key" ]]; then
    echo "Usage: $(basename "$0") vault-get <NODE_ID> <KEY>" >&2
    exit 1
  fi
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  log_event "info" "harness.vault_get" "start" "node=${id} key=${key}"
  run_vault_for_node "$id" --get --key "$key"
  log_event "info" "harness.vault_get" "ok" "node=${id} key=${key}"
}

cmd_vault_commit() {
  local id="${1:-}"
  local message="${2:-}"
  if [[ -z "$id" ]]; then
    echo "Usage: $(basename "$0") vault-commit <NODE_ID> [MESSAGE]" >&2
    exit 1
  fi
  if [[ -z "$message" ]]; then
    message="UI vault commit node${id} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fi
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  log_event "info" "harness.vault_commit" "start" "node=${id} message=${message}"
  run_vault_for_node "$id" --commit --message "$message"
  log_event "info" "harness.vault_commit" "ok" "node=${id} message=${message}"
}

cmd_seal_commit() {
  local id="${1:-}"
  shift || true
  local message="${*:-}"
  if [[ -z "$id" || -z "$message" ]]; then
    echo "Usage: $(basename "$0") seal-commit <NODE_ID> <MESSAGE>" >&2
    exit 1
  fi
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  log_event "info" "harness.seal_commit" "start" "node=${id} message=${message}"
  run_seal_for_node "$id" commit "$message"
  log_event "info" "harness.seal_commit" "ok" "node=${id} message=${message}"
}

cmd_seal_release() {
  local id="${1:-}"
  local version="${2:-}"
  shift 2 || true
  local message="${*:-}"
  if [[ -z "$id" || -z "$version" ]]; then
    echo "Usage: $(basename "$0") seal-release <NODE_ID> <VERSION> [MESSAGE]" >&2
    exit 1
  fi
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  log_event "info" "harness.seal_release" "start" "node=${id} version=${version}"
  if [[ -n "$message" ]]; then
    run_seal_for_node "$id" release "$version" --message "$message"
  else
    run_seal_for_node "$id" release "$version"
  fi
  log_event "info" "harness.seal_release" "ok" "node=${id} version=${version}"
}

cmd_seal_verify() {
  local id="${1:-}"
  local version="${2:-}"
  if [[ -z "$id" || -z "$version" ]]; then
    echo "Usage: $(basename "$0") seal-verify <NODE_ID> <VERSION>" >&2
    exit 1
  fi
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  log_event "info" "harness.seal_verify" "start" "node=${id} version=${version}"
  run_seal_for_node "$id" verify "$version"
  log_event "info" "harness.seal_verify" "ok" "node=${id} version=${version}"
}

cmd_seal_archive() {
  local id="${1:-}"
  local version="${2:-}"
  local format="${3:-zstd-age}"
  if [[ -z "$id" || -z "$version" ]]; then
    echo "Usage: $(basename "$0") seal-archive <NODE_ID> <VERSION> [FORMAT]" >&2
    exit 1
  fi
  SPKI_DEFAULT_NODE_NAMES="${SPKI_REALM_HARNESS_NODE_NAMES:-${SPKI_DEFAULT_NODE_NAMES:-}}"
  log_event "info" "harness.seal_archive" "start" "node=${id} version=${version} format=${format}"
  run_seal_for_node "$id" archive "$version" --format "$format"
  log_event "info" "harness.seal_archive" "ok" "node=${id} version=${version} format=${format}"
}

cmd_clean() {
  log_event "info" "harness.clean" "start" "root=${HARNESS_ROOT}"
  for pid_file in "$HARNESS_ROOT"/*/listener.pid; do
    [[ -f "$pid_file" ]] || continue
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      echo "Stopped listener PID ${pid}"
    fi
  done
  pkill -f "dns-sd -R.*_cyberspace" 2>/dev/null || true
  rm -rf "$HARNESS_ROOT"
  echo "Removed $HARNESS_ROOT"
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    init) cmd_init "$@" ;;
    self-join) cmd_self_join "$@" ;;
    join-all) cmd_join_all "$@" ;;
    join-one) cmd_join_one "$@" ;;
    listen-bg) cmd_listen_bg "$@" ;;
    stop-listen-bg) cmd_stop_listen_bg "$@" ;;
    vault-put) cmd_vault_put "$@" ;;
    vault-get) cmd_vault_get "$@" ;;
    vault-commit) cmd_vault_commit "$@" ;;
    seal-commit) cmd_seal_commit "$@" ;;
    seal-release) cmd_seal_release "$@" ;;
    seal-verify) cmd_seal_verify "$@" ;;
    seal-archive) cmd_seal_archive "$@" ;;
    stop-all-bg) cmd_stop_all_bg "$@" ;;
    clean) cmd_clean ;;
    ""|-h|--help|help) usage ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
