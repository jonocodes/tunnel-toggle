#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${PROJECT_DIR}/config.sh"

echo "=== SQL Proxy Menubar — Uninstaller ==="
echo ""

# 1. Stop all running tunnels
for name in "${TUNNEL_NAMES[@]}"; do
    pf="$(pid_file "$name")"
    if [[ -f "$pf" ]]; then
        pid=$(cat "$pf")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            echo "Stopped ${name} tunnel (PID ${pid})"
        fi
        rm -f "$pf"
    fi
done

# 2. Remove symlink from plugin directory
PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "${HOME}/SwiftBarPlugins")
LINK="${PLUGIN_DIR}/sql-proxy.5s.sh"
if [[ -L "$LINK" ]]; then
    rm "$LINK"
    echo "Removed plugin symlink: ${LINK}"
fi

# 3. Remove state directory
if [[ -d "$STATE_DIR" ]]; then
    rm -rf "$STATE_DIR"
    echo "Removed state directory: ${STATE_DIR}"
fi

echo ""
echo "=== Uninstall Complete ==="
echo "Project files in ${PROJECT_DIR} were not removed."
