#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_NAME="tunnel-toggle.5s.sh"
OLD_PLUGIN_NAME="sql-proxy.5s.sh"

echo "=== Tunnel Toggle — Installer ==="
echo ""

# 1. Check for jq
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq not found."
    echo "Install it: brew install jq"
    exit 1
fi
echo "[OK] jq found: $(command -v jq)"

# 2. Check for cloud-sql-proxy
if ! command -v cloud-sql-proxy &>/dev/null; then
    echo "[WARN] cloud-sql-proxy not found. SQL tunnels won't work."
    echo "       Install it: brew install cloud-sql-proxy"
else
    echo "[OK] cloud-sql-proxy found: $(command -v cloud-sql-proxy)"
fi

# 3. Check for ssh
if ! command -v ssh &>/dev/null; then
    echo "[WARN] ssh not found. SSH tunnels won't work."
else
    echo "[OK] ssh found: $(command -v ssh)"
fi

# 4. Check gcloud ADC
if gcloud auth application-default print-access-token &>/dev/null 2>&1; then
    echo "[OK] gcloud Application Default Credentials configured"
else
    echo "[WARN] gcloud ADC not configured. Run: gcloud auth application-default login"
fi

# 5. Check for / install SwiftBar
if [[ -d "/Applications/SwiftBar.app" ]]; then
    echo "[OK] SwiftBar installed"
else
    echo "SwiftBar is not installed."
    read -rp "Install SwiftBar via Homebrew? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        brew install --cask swiftbar
        echo "[OK] SwiftBar installed"
    else
        echo "Please install SwiftBar manually: https://swiftbar.app"
        exit 1
    fi
fi

# 6. Check for tunnels.json
CONFIG_FILE="${PROJECT_DIR}/tunnels.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo ""
    echo "[INFO] No tunnels.json found. Creating from example..."
    cp "${PROJECT_DIR}/tunnels.json.example" "$CONFIG_FILE"
    echo "       Created: ${CONFIG_FILE}"
    echo ""
    echo "  >>> Edit tunnels.json with your tunnel details, then re-run install.sh <<<"
    echo ""
    exit 1
fi

# 7. Validate tunnel config (sources config.sh which does full validation)
echo ""
echo "Validating tunnel configuration..."
source "${PROJECT_DIR}/config.sh"
echo "[OK] Configuration valid (${#TUNNEL_NAMES[@]} SQL + ${#SSH_NAMES[@]} SSH tunnel(s))"

# 8. Determine SwiftBar plugin directory
PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "")
if [[ -z "$PLUGIN_DIR" ]]; then
    PLUGIN_DIR="${HOME}/SwiftBarPlugins"
    echo ""
    echo "[INFO] SwiftBar plugin directory not configured yet."
    echo "       Using default: ${PLUGIN_DIR}"
    echo "       When SwiftBar launches for the first time, it will ask you to choose a plugin folder."
    echo "       Point it to: ${PLUGIN_DIR}"
fi

# 9. Migrate from old state directory if needed
OLD_STATE_DIR="${HOME}/.sql-proxy-menubar"
if [[ -d "$OLD_STATE_DIR" ]]; then
    echo ""
    echo "Migrating from ${OLD_STATE_DIR}..."
    mkdir -p "${STATE_DIR}/sql"
    # Move existing PID and log files to sql/ subdirectory
    for f in "${OLD_STATE_DIR}"/*.pid "${OLD_STATE_DIR}"/*.log; do
        [[ -f "$f" ]] && mv "$f" "${STATE_DIR}/sql/"
    done
    rmdir "$OLD_STATE_DIR" 2>/dev/null || rm -rf "$OLD_STATE_DIR"
    echo "[OK] Migrated state to ${STATE_DIR}/sql/"
fi

# 10. Create state directories
mkdir -p "${STATE_DIR}/sql" "${STATE_DIR}/ssh"
echo "[OK] State directory: ${STATE_DIR}"

# 11. Make scripts executable
chmod +x "${PROJECT_DIR}/${PLUGIN_NAME}"
chmod +x "${PROJECT_DIR}/lib/proxy-ctl.sh"
chmod +x "${PROJECT_DIR}/lib/ssh-ctl.sh"
chmod +x "${PROJECT_DIR}/lib/bulk-ctl.sh"
chmod +x "${PROJECT_DIR}/lib/auth-ctl.sh"
echo "[OK] Scripts made executable"

# 12. Remove old symlink if present
mkdir -p "$PLUGIN_DIR"
OLD_LINK="${PLUGIN_DIR}/${OLD_PLUGIN_NAME}"
if [[ -L "$OLD_LINK" ]]; then
    rm "$OLD_LINK"
    echo "[OK] Removed old plugin symlink: ${OLD_LINK}"
fi

# 13. Create symlink in plugin directory
LINK="${PLUGIN_DIR}/${PLUGIN_NAME}"
if [[ -L "$LINK" ]]; then
    rm "$LINK"
    echo "     (updated existing symlink)"
elif [[ -e "$LINK" ]]; then
    echo "WARNING: ${LINK} already exists and is not a symlink. Skipping."
    echo "         Remove it manually and re-run install.sh."
    exit 1
fi
ln -s "${PROJECT_DIR}/${PLUGIN_NAME}" "$LINK"
echo "[OK] Plugin symlinked: ${LINK}"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. Launch SwiftBar from Applications (if not already running)"
echo "  2. When prompted, set the plugin folder to: ${PLUGIN_DIR}"
echo "  3. The Tunnel Toggle will appear in your menu bar"
echo ""
echo "Tunnels configured:"
for i in "${!TUNNEL_NAMES[@]}"; do
    echo "  [SQL] ${TUNNEL_LABELS[$i]}: localhost:${TUNNEL_PORTS[$i]} → ${TUNNEL_INSTANCES[$i]}"
done
for i in "${!SSH_NAMES[@]}"; do
    echo "  [SSH] ${SSH_LABELS[$i]}: ${SSH_FORWARDS[$i]} → ${SSH_HOSTS[$i]}"
done
