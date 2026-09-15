#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

ACTION="${1:-status}"
TARGET="${2:-all}"

# Resolve SSH tunnel index from name
ssh_tunnel_index() {
    local name="$1"
    for i in "${!SSH_NAMES[@]}"; do
        [[ "${SSH_NAMES[$i]}" == "$name" ]] && echo "$i" && return
    done
    echo "ERROR: Unknown SSH tunnel '${name}'" >&2
    exit 1
}

# Check if an SSH tunnel process is running
ssh_is_running() {
    local name="$1"
    local pf
    pf="$(ssh_pid_file "$name")"
    if [[ -f "$pf" ]]; then
        local pid
        pid=$(cat "$pf")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            # Stale PID file — clean up
            rm -f "$pf"
        fi
    fi
    return 1
}

# Start an SSH tunnel
ssh_start_tunnel() {
    local name="$1"
    if ssh_is_running "$name"; then
        return 0
    fi

    local idx
    idx=$(ssh_tunnel_index "$name")
    local forward="${SSH_FORWARDS[$idx]}"
    local host="${SSH_HOSTS[$idx]}"
    local opts="${SSH_OPTS[$idx]}"
    local pf lf
    pf="$(ssh_pid_file "$name")"
    lf="$(ssh_log_file "$name")"

    mkdir -p "${STATE_DIR}/ssh"

    # Build the ssh command
    # shellcheck disable=SC2086
    nohup ssh -N \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        -o StrictHostKeyChecking=accept-new \
        ${opts} ${forward} "${host}" \
        > "$lf" 2>&1 &
    local pid=$!
    echo "$pid" > "$pf"

    # Verify the process started successfully
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$pf"
        notify-send "Tunnel Toggle" "Failed to start SSH tunnel '${name}'. Check logs." 2>/dev/null || true
        return 1
    fi
}

# Stop an SSH tunnel
ssh_stop_tunnel() {
    local name="$1"
    local pf
    pf="$(ssh_pid_file "$name")"
    if [[ -f "$pf" ]]; then
        local pid
        pid=$(cat "$pf")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            # Wait for graceful shutdown
            for _ in {1..10}; do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.2
            done
            # Force kill if still alive
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$pf"
    fi
}

# Toggle an SSH tunnel on/off
ssh_toggle_tunnel() {
    local name="$1"
    if ssh_is_running "$name"; then
        ssh_stop_tunnel "$name"
    else
        ssh_start_tunnel "$name"
    fi
}

# Copy connection info to clipboard
ssh_copy_connection() {
    local name="$1"
    local idx
    idx=$(ssh_tunnel_index "$name")
    local forward="${SSH_FORWARDS[$idx]}"
    local host="${SSH_HOSTS[$idx]}"
    local conn="ssh -N ${forward} ${host}"
    echo "$conn" | { pbcopy 2>/dev/null || xclip -selection clipboard 2>/dev/null || wl-copy 2>/dev/null; } || echo "$conn"
}

# Run an action on one or all SSH tunnels
ssh_run_on_targets() {
    local action="$1"
    local target="$2"
    if [[ "$target" == "all" ]]; then
        for name in "${SSH_NAMES[@]}"; do
            "$action" "$name"
        done
    else
        "$action" "$target"
    fi
}

if [[ ${#SSH_NAMES[@]} -eq 0 ]]; then
    echo "No SSH tunnels configured." >&2
    exit 0
fi

case "$ACTION" in
    start)  ssh_run_on_targets ssh_start_tunnel "$TARGET" ;;
    stop)   ssh_run_on_targets ssh_stop_tunnel "$TARGET" ;;
    toggle) ssh_run_on_targets ssh_toggle_tunnel "$TARGET" ;;
    copy)   ssh_copy_connection "$TARGET" ;;
    status)
        for name in "${SSH_NAMES[@]}"; do
            if ssh_is_running "$name"; then
                echo "${name}:running"
            else
                echo "${name}:stopped"
            fi
        done
        ;;
    *)
        names=$(IFS="|"; echo "${SSH_NAMES[*]}")
        echo "Usage: $0 <start|stop|toggle|status|copy> <${names}|all>" >&2
        exit 1
        ;;
esac
