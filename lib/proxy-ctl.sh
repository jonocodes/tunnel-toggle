#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

ACTION="${1:-status}"
TARGET="${2:-all}"

# Resolve tunnel index from name
tunnel_index() {
    local name="$1"
    for i in "${!TUNNEL_NAMES[@]}"; do
        [[ "${TUNNEL_NAMES[$i]}" == "$name" ]] && echo "$i" && return
    done
    echo "ERROR: Unknown tunnel '${name}'" >&2
    exit 1
}

# Find a live proxy process for a tunnel by matching its command line.
# Used when the PID file is missing (e.g. the tunnel was renamed), so a
# running tunnel can't be orphaned under a stale name.
proxy_find_pid() {
    local idx="$1"
    local port="${TUNNEL_PORTS[$idx]}"
    local instance="${TUNNEL_INSTANCES[$idx]}"
    local proc pid cmd
    proc="$(basename "${PROXY_BINARY:-cloud-sql-proxy}")"
    for pid in $(pgrep -x "$proc" 2>/dev/null || true); do
        cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
        if [[ "$cmd" == *"--port ${port} "* && "$cmd" == *"${instance}"* ]]; then
            echo "$pid"
            return 0
        fi
    done
    return 1
}

# Resolve a tunnel's live PID, healing the PID file when the process is found
# by command line. Echoes the PID and returns 0 when running.
proxy_resolve_pid() {
    local name="$1"
    local pf pid idx
    pf="$(pid_file "$name")"

    if [[ -f "$pf" ]]; then
        pid="$(cat "$pf" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
        # Stale PID file — clean up
        rm -f "$pf"
    fi

    idx="$(tunnel_index "$name")"
    if pid="$(proxy_find_pid "$idx")" && [[ -n "$pid" ]]; then
        echo "$pid" > "$pf"
        echo "$pid"
        return 0
    fi

    return 1
}

# Check if a tunnel's proxy process is running
is_running() {
    proxy_resolve_pid "$1" >/dev/null 2>&1
}

# Start a tunnel
start_tunnel() {
    local name="$1"
    if is_running "$name"; then
        return 0
    fi

    local idx
    idx=$(tunnel_index "$name")
    local instance="${TUNNEL_INSTANCES[$idx]}"
    local port="${TUNNEL_PORTS[$idx]}"
    local pf lf shadow
    pf="$(pid_file "$name")"
    lf="$(log_file "$name")"

    mkdir -p "${STATE_DIR}/sql"

    # Refuse to start when another process already holds the specific
    # 127.0.0.1:port address. Our wildcard (0.0.0.0) bind would succeed, but
    # localhost clients would be routed to that other process, leaving a
    # "running" tunnel that nothing local can actually use.
    if shadow="$(port_shadow_pids "$port")" && [[ -n "$shadow" ]]; then
        echo "ERROR: port conflict: 127.0.0.1:${port} is already in use by PID ${shadow}. Stop that process (e.g. a monorepo 'just db-proxies' tunnel) or change this tunnel's port." > "$lf"
        rm -f "$pf"
        notify-send "Tunnel Toggle" "${name} cannot start: localhost:${port} is already in use by another process." 2>/dev/null || true
        return 1
    fi

    # Refuse to start when ADC is unusable. The proxy keeps running (and
    # retrying) through auth failures, so launching anyway would report a
    # healthy "running" tunnel that can't connect. Leaving no PID plus an
    # auth-error log makes sql_status_of report "needs-auth" everywhere.
    if [[ "$(adc_state)" == "needs-auth" ]]; then
        echo "ERROR: gcloud ADC is missing, expired, or revoked - reauthentication is required. Run 'tunnel auth'." > "$lf"
        rm -f "$pf"
        notify-send "Tunnel Toggle" "${name} needs gcloud reauth. Run 'tunnel auth'." 2>/dev/null || true
        return 1
    fi

    # Enable IAM database authentication when the tunnel opts in
    local iam_flag=""
    [[ "${TUNNEL_IAM[$idx]:-false}" == "true" ]] && iam_flag="--auto-iam-authn"

    nohup "$PROXY_BINARY" $iam_flag --address 0.0.0.0 --port "$port" "$instance" \
        > "$lf" 2>&1 &
    local pid=$!
    echo "$pid" > "$pf"

    # Verify the process started successfully
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$pf"
        notify-send "Tunnel Toggle" "Failed to start ${name} tunnel. Check logs." 2>/dev/null || true
        return 1
    fi
}

# Stop a tunnel
stop_tunnel() {
    local name="$1"
    local pf pid
    pf="$(pid_file "$name")"
    if pid="$(proxy_resolve_pid "$name")" && [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        # Wait for graceful shutdown
        for _ in {1..10}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        # Force kill if still alive
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pf"
}

# Toggle a tunnel on/off
toggle_tunnel() {
    local name="$1"
    if is_running "$name"; then
        stop_tunnel "$name"
    else
        start_tunnel "$name"
    fi
}

# Copy connection string to clipboard
copy_connection() {
    local name="$1"
    local idx
    idx=$(tunnel_index "$name")
    local conn
    conn="$(sql_conn_string "$idx")"
    echo "$conn" | { pbcopy 2>/dev/null || xclip -selection clipboard 2>/dev/null || wl-copy 2>/dev/null; } || echo "$conn"
}

# Run an action on one or all tunnels
run_on_targets() {
    local action="$1"
    local target="$2"
    local rc=0
    if [[ "$target" == "all" ]]; then
        # Attempt every tunnel even if one fails, so a single bad tunnel
        # (e.g. one that needs gcloud reauth) doesn't mask the rest.
        for name in "${TUNNEL_NAMES[@]}"; do
            "$action" "$name" || rc=1
        done
    else
        "$action" "$target" || rc=1
    fi
    return $rc
}

case "$ACTION" in
    start)  run_on_targets start_tunnel "$TARGET" ;;
    stop)   run_on_targets stop_tunnel "$TARGET" ;;
    toggle) run_on_targets toggle_tunnel "$TARGET" ;;
    copy)   copy_connection "$TARGET" ;;
    status)
        for name in "${TUNNEL_NAMES[@]}"; do
            # Resolve first so a missing PID file is healed before reporting;
            # sql_status_of then distinguishes running from port-conflict.
            proxy_resolve_pid "$name" >/dev/null 2>&1 || true
            echo "${name}:$(sql_status_of "$name")"
        done
        ;;
    *)
        names=$(IFS="|"; echo "${TUNNEL_NAMES[*]}")
        echo "Usage: $0 <start|stop|toggle|status|copy> <${names}|all>" >&2
        exit 1
        ;;
esac
