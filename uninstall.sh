#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${PROJECT_DIR}/config.sh"

echo "=== Tunnel Toggle — Uninstaller ==="
echo ""

# 1. Stop all running SQL tunnels
for name in "${TUNNEL_NAMES[@]}"; do
    pf="$(pid_file "$name")"
    if [[ -f "$pf" ]]; then
        pid=$(cat "$pf")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            echo "Stopped SQL tunnel ${name} (PID ${pid})"
        fi
        rm -f "$pf"
    fi
done

# 2. Stop all running SSH tunnels
for name in "${SSH_NAMES[@]}"; do
    pf="$(ssh_pid_file "$name")"
    if [[ -f "$pf" ]]; then
        pid=$(cat "$pf")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            echo "Stopped SSH tunnel ${name} (PID ${pid})"
        fi
        rm -f "$pf"
    fi
done

# 3. Remove symlinks from plugin directory
PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "${HOME}/SwiftBarPlugins")
for link_name in "tunnel-toggle.5s.sh" "sql-proxy.5s.sh"; do
    LINK="${PLUGIN_DIR}/${link_name}"
    if [[ -L "$LINK" ]]; then
        rm "$LINK"
        echo "Removed plugin symlink: ${LINK}"
    fi
done

# 4. Remove state directory
if [[ -d "$STATE_DIR" ]]; then
    rm -rf "$STATE_DIR"
    echo "Removed state directory: ${STATE_DIR}"
fi

# 5. Also clean up old state directory if present
OLD_STATE_DIR="${HOME}/.sql-proxy-menubar"
if [[ -d "$OLD_STATE_DIR" ]]; then
    rm -rf "$OLD_STATE_DIR"
    echo "Removed old state directory: ${OLD_STATE_DIR}"
fi

echo ""
echo "=== Uninstall Complete ==="
echo "Project files in ${PROJECT_DIR} were not removed."
