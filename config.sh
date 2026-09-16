#!/usr/bin/env bash
# Configuration for Tunnel Toggle
# Loads SQL and SSH tunnel definitions from tunnels.json

# SwiftBar runs menu actions with a minimal PATH that omits Homebrew, so tools
# like jq, cloud-sql-proxy, and pbcopy aren't found. Ensure common dirs are present.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

# Resolve script directory (works when sourced from any location)
if [[ -n "${SCRIPT_DIR:-}" ]]; then
    CONFIG_DIR="$SCRIPT_DIR"
elif [[ -n "${PROJECT_DIR:-}" ]]; then
    CONFIG_DIR="$PROJECT_DIR"
else
    CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

CONFIG_FILE="${CONFIG_DIR}/tunnels.json"
STATE_DIR="${HOME}/.tunnel-toggle"

# --- Validate dependencies ---

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not found. Install it with your package manager (brew install jq / apt install jq / pacman -S jq)." >&2
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

# --- SQL Proxy tunnels ---

# Read proxy binary (default: auto-detect from PATH)
PROXY_BINARY=$(jq -r '.proxy_binary // empty' "$CONFIG_FILE")
if [[ -z "$PROXY_BINARY" ]]; then
    PROXY_BINARY=$(command -v cloud-sql-proxy 2>/dev/null || echo "")
fi

# Read tunnel count
tunnel_count=$(jq '.tunnels | length' "$CONFIG_FILE")

# Populate tunnel arrays from JSON
TUNNEL_NAMES=()
TUNNEL_LABELS=()
TUNNEL_INSTANCES=()
TUNNEL_PORTS=()
TUNNEL_IAM=()
TUNNEL_ENGINES=()

for (( i=0; i<tunnel_count; i++ )); do
    name=$(jq -r ".tunnels[$i].name // empty" "$CONFIG_FILE")
    label=$(jq -r ".tunnels[$i].label // empty" "$CONFIG_FILE")
    instance=$(jq -r ".tunnels[$i].instance // empty" "$CONFIG_FILE")
    port=$(jq -r ".tunnels[$i].port // empty" "$CONFIG_FILE")
    iam=$(jq -r ".tunnels[$i].auto_iam_authn // false" "$CONFIG_FILE")
    engine=$(jq -r ".tunnels[$i].engine // \"mysql\"" "$CONFIG_FILE")

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
    if [[ "$engine" != "mysql" && "$engine" != "postgres" ]]; then
        echo "ERROR: Tunnel '${name}' has invalid 'engine' '${engine}' (expected 'mysql' or 'postgres')" >&2
        exit 1
    fi

    # Default label to capitalized name
    if [[ -z "$label" ]]; then
        label="${name^}"
    fi

    # Check for duplicate names
    for existing in ${TUNNEL_NAMES[@]+"${TUNNEL_NAMES[@]}"}; do
        if [[ "$existing" == "$name" ]]; then
            echo "ERROR: Duplicate tunnel name '${name}'" >&2
            exit 1
        fi
    done

    # Check for duplicate ports
    for existing in ${TUNNEL_PORTS[@]+"${TUNNEL_PORTS[@]}"}; do
        if [[ "$existing" == "$port" ]]; then
            echo "ERROR: Duplicate port ${port} (tunnel '${name}')" >&2
            exit 1
        fi
    done

    TUNNEL_NAMES+=("$name")
    TUNNEL_LABELS+=("$label")
    TUNNEL_INSTANCES+=("$instance")
    TUNNEL_PORTS+=("$port")
    TUNNEL_IAM+=("$iam")
    TUNNEL_ENGINES+=("$engine")
done

# Build a client connection string for a SQL tunnel index. MySQL and Postgres
# differ in the port flag casing (-P vs -p).
sql_conn_string() {
    local idx="$1"
    local host="127.0.0.1"
    local port="${TUNNEL_PORTS[$idx]}"
    case "${TUNNEL_ENGINES[$idx]:-mysql}" in
        postgres) echo "psql -h ${host} -p ${port}" ;;
        *)        echo "mysql -h ${host} -P ${port}" ;;
    esac
}

# --- SSH Tunnels ---

ssh_tunnel_count=$(jq '.ssh_tunnels // [] | length' "$CONFIG_FILE")

SSH_NAMES=()
SSH_LABELS=()
SSH_FORWARDS=()
SSH_HOSTS=()
SSH_OPTS=()

for (( i=0; i<ssh_tunnel_count; i++ )); do
    name=$(jq -r ".ssh_tunnels[$i].name // empty" "$CONFIG_FILE")
    label=$(jq -r ".ssh_tunnels[$i].label // empty" "$CONFIG_FILE")
    forward=$(jq -r ".ssh_tunnels[$i].forward // empty" "$CONFIG_FILE")
    host=$(jq -r ".ssh_tunnels[$i].host // empty" "$CONFIG_FILE")
    opts=$(jq -r ".ssh_tunnels[$i].opts // empty" "$CONFIG_FILE")

    # Validate required fields
    if [[ -z "$name" ]]; then
        echo "ERROR: SSH tunnel at index ${i} is missing 'name'" >&2
        exit 1
    fi
    if [[ -z "$forward" ]]; then
        echo "ERROR: SSH tunnel '${name}' is missing 'forward'" >&2
        exit 1
    fi
    if [[ -z "$host" ]]; then
        echo "ERROR: SSH tunnel '${name}' is missing 'host'" >&2
        exit 1
    fi

    # Default label to capitalized name
    if [[ -z "$label" ]]; then
        label="${name^}"
    fi

    # Check for duplicate names (across both SQL and SSH)
    for existing in ${TUNNEL_NAMES[@]+"${TUNNEL_NAMES[@]}"} ${SSH_NAMES[@]+"${SSH_NAMES[@]}"}; do
        if [[ "$existing" == "$name" ]]; then
            echo "ERROR: Duplicate tunnel name '${name}'" >&2
            exit 1
        fi
    done

    SSH_NAMES+=("$name")
    SSH_LABELS+=("$label")
    SSH_FORWARDS+=("$forward")
    SSH_HOSTS+=("$host")
    SSH_OPTS+=("$opts")
done

# --- Path helpers ---

sql_pid_file() { echo "${STATE_DIR}/sql/${1}.pid"; }
sql_log_file() { echo "${STATE_DIR}/sql/${1}.log"; }
ssh_pid_file() { echo "${STATE_DIR}/ssh/${1}.pid"; }
ssh_log_file() { echo "${STATE_DIR}/ssh/${1}.log"; }

# Legacy aliases for proxy-ctl.sh compatibility
pid_file() { sql_pid_file "$1"; }
log_file() { sql_log_file "$1"; }

# --- gcloud Application Default Credentials ---

# Strings cloud-sql-proxy emits when ADC is missing, expired, or revoked
# (an expired refresh token requires an interactive `gcloud auth
# application-default login` — a plain proxy restart can't fix it).
AUTH_ERROR_PATTERN='could not find default credentials|(application )?default credentials (are not available|were not found|could not be found)|invalid_grant|invalid_rapt|reauthentication is required|token has been expired or revoked|credentials have been revoked|problem refreshing your current auth tokens|(failed|unable) to (get|retrieve|fetch|load|find) (a )?(credential|credentials|token)|oauth2: cannot fetch token|no valid credentials'

GCLOUD_BINARY="${GCLOUD_BINARY:-$(command -v gcloud 2>/dev/null || echo gcloud)}"

# Does a SQL tunnel's most recent log look like an ADC auth failure?
sql_log_has_auth_error() {
    local lf
    lf="$(sql_log_file "$1")"
    [[ -f "$lf" ]] || return 1
    tail -n 40 "$lf" 2>/dev/null | grep -qiE "$AUTH_ERROR_PATTERN"
}

# State of a SQL tunnel: running | needs-auth | port-conflict | stopped
sql_status_of() {
    local name="$1" pf pid port shadow
    pf="$(sql_pid_file "$name")"
    if [[ -f "$pf" ]] && pid="$(cat "$pf" 2>/dev/null)" \
        && [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        # Running, but is another process intercepting localhost?
        port="$(sql_port_of "$name" || true)"
        if [[ -n "$port" ]] && shadow="$(port_shadow_pids "$port" "$pid")" \
            && [[ -n "$shadow" ]]; then
            echo "port-conflict"
        else
            echo "running"
        fi
    elif sql_log_has_auth_error "$name"; then
        echo "needs-auth"
    elif sql_log_has_port_conflict "$name"; then
        echo "port-conflict"
    else
        echo "stopped"
    fi
}

# Pre-flight ADC check. cloud-sql-proxy stays alive and keeps retrying when
# credentials are missing or expired, so a launched process would look
# "running" while never connecting. Callers check this before starting.
# Echoes: ok | needs-auth | unknown (couldn't determine — don't block on it).
# Cached per process so a bulk start only pays for one gcloud call.
adc_state() {
    if [[ -n "${_ADC_STATE_CACHE:-}" ]]; then
        echo "$_ADC_STATE_CACHE"
        return 0
    fi

    if ! command -v "$GCLOUD_BINARY" &>/dev/null; then
        _ADC_STATE_CACHE="unknown"
    else
        local err
        if err="$("$GCLOUD_BINARY" auth application-default print-access-token 2>&1 >/dev/null)"; then
            _ADC_STATE_CACHE="ok"
        elif grep -qiE "$AUTH_ERROR_PATTERN" <<<"$err"; then
            _ADC_STATE_CACHE="needs-auth"
        else
            # A non-auth failure (e.g. a network blip) — let the proxy try.
            _ADC_STATE_CACHE="unknown"
        fi
    fi

    echo "$_ADC_STATE_CACHE"
}

# --- Loopback port conflicts ---

# The proxy binds 0.0.0.0 so containers can reach it, but that means another
# process can hold the *specific* 127.0.0.1 address on the same port: our bind
# still succeeds, yet localhost clients are routed to the other process — a
# tunnel that reports "running" but that nothing local can use. This marker
# goes in the tunnel log when a start is refused for that reason.
PORT_CONFLICT_PATTERN='port conflict: 127\.0\.0\.1'

# PIDs holding the specific 127.0.0.1:<port> address, excluding our own proxy.
# Echoes the blocking PIDs (empty when loopback is free). Uses lsof, falling
# back to ss; reports nothing if neither is available.
port_shadow_pids() {
    local port="$1" our_pid="${2:-}"
    local pids="" p out=""
    if command -v lsof &>/dev/null; then
        pids="$(lsof -nP -tiTCP@"127.0.0.1":"$port" -sTCP:LISTEN 2>/dev/null || true)"
    elif command -v ss &>/dev/null; then
        pids="$(ss -ltnpH "sport = :${port}" 2>/dev/null \
            | awk '$4 ~ /^127\.0\.0\.1:/ {print}' \
            | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)"
    fi
    for p in $pids; do
        [[ -n "$our_pid" && "$p" == "$our_pid" ]] && continue
        out="${out}${out:+ }${p}"
    done
    [[ -n "$out" ]] && echo "$out"
    return 0
}

# Port configured for a SQL tunnel name (returns non-zero if unknown).
sql_port_of() {
    local name="$1" i
    for i in "${!TUNNEL_NAMES[@]}"; do
        if [[ "${TUNNEL_NAMES[$i]}" == "$name" ]]; then
            echo "${TUNNEL_PORTS[$i]}"
            return 0
        fi
    done
    return 1
}

# Did a SQL tunnel's most recent log record a loopback port conflict?
sql_log_has_port_conflict() {
    local lf
    lf="$(sql_log_file "$1")"
    [[ -f "$lf" ]] || return 1
    tail -n 40 "$lf" 2>/dev/null | grep -qiE "$PORT_CONFLICT_PATTERN"
}
