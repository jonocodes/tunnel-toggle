#!/usr/bin/env bash
# Configuration for SQL Proxy Menubar
# Loads tunnel definitions from tunnels.json

# Resolve script directory (works when sourced from any location)
if [[ -n "${SCRIPT_DIR:-}" ]]; then
    CONFIG_DIR="$SCRIPT_DIR"
elif [[ -n "${PROJECT_DIR:-}" ]]; then
    CONFIG_DIR="$PROJECT_DIR"
else
    CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

CONFIG_FILE="${CONFIG_DIR}/tunnels.json"
STATE_DIR="${HOME}/.sql-proxy-menubar"

# --- Validate dependencies ---

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not found. Install it: brew install jq" >&2
    exit 1
fi

# --- Load and validate JSON config ---

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: ${CONFIG_FILE}" >&2
    echo "       Copy tunnels.json.example to tunnels.json and edit it." >&2
    exit 1
fi

if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo "ERROR: Invalid JSON in ${CONFIG_FILE}" >&2
    echo "       Check for syntax errors (missing commas, brackets, quotes)." >&2
    exit 1
fi

# Read proxy binary (default: auto-detect from PATH)
PROXY_BINARY=$(jq -r '.proxy_binary // empty' "$CONFIG_FILE")
if [[ -z "$PROXY_BINARY" ]]; then
    PROXY_BINARY=$(command -v cloud-sql-proxy 2>/dev/null || echo "")
fi

# Read tunnel count
tunnel_count=$(jq '.tunnels | length' "$CONFIG_FILE")
if [[ "$tunnel_count" -eq 0 ]]; then
    echo "ERROR: No tunnels defined in ${CONFIG_FILE}" >&2
    exit 1
fi

# Populate tunnel arrays from JSON
TUNNEL_NAMES=()
TUNNEL_LABELS=()
TUNNEL_INSTANCES=()
TUNNEL_PORTS=()

for i in $(seq 0 $((tunnel_count - 1))); do
    name=$(jq -r ".tunnels[$i].name // empty" "$CONFIG_FILE")
    label=$(jq -r ".tunnels[$i].label // empty" "$CONFIG_FILE")
    instance=$(jq -r ".tunnels[$i].instance // empty" "$CONFIG_FILE")
    port=$(jq -r ".tunnels[$i].port // empty" "$CONFIG_FILE")

    # Validate required fields
    if [[ -z "$name" ]]; then
        echo "ERROR: Tunnel at index ${i} is missing 'name'" >&2
        exit 1
    fi
    if [[ -z "$instance" ]]; then
        echo "ERROR: Tunnel '${name}' is missing 'instance'" >&2
        exit 1
    fi
    if [[ -z "$port" ]]; then
        echo "ERROR: Tunnel '${name}' is missing 'port'" >&2
        exit 1
    fi

    # Default label to capitalized name
    if [[ -z "$label" ]]; then
        label="${name^}"
    fi

    # Check for duplicate names
    for existing in "${TUNNEL_NAMES[@]}"; do
        if [[ "$existing" == "$name" ]]; then
            echo "ERROR: Duplicate tunnel name '${name}'" >&2
            exit 1
        fi
    done

    # Check for duplicate ports
    for existing in "${TUNNEL_PORTS[@]}"; do
        if [[ "$existing" == "$port" ]]; then
            echo "ERROR: Duplicate port ${port} (tunnel '${name}')" >&2
            exit 1
        fi
    done

    TUNNEL_NAMES+=("$name")
    TUNNEL_LABELS+=("$label")
    TUNNEL_INSTANCES+=("$instance")
    TUNNEL_PORTS+=("$port")
done

# --- Path helpers ---

pid_file() { echo "${STATE_DIR}/${1}.pid"; }
log_file() { echo "${STATE_DIR}/${1}.log"; }
