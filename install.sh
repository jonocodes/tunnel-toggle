#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_NAME="sql-proxy.5s.sh"

echo "=== SQL Proxy Menubar — Installer ==="
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
    echo "ERROR: cloud-sql-proxy not found."
    echo "Install it: brew install cloud-sql-proxy"
    exit 1
fi
echo "[OK] cloud-sql-proxy found: $(command -v cloud-sql-proxy)"

# 3. Check gcloud ADC
if gcloud auth application-default print-access-token &>/dev/null 2>&1; then
    echo "[OK] gcloud Application Default Credentials configured"
else
    echo "[WARN] gcloud ADC not configured. Run: gcloud auth application-default login"
fi

# 4. Check for / install SwiftBar
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

# 5. Check for tunnels.json
CONFIG_FILE="${PROJECT_DIR}/tunnels.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo ""
    echo "[INFO] No tunnels.json found. Creating from example..."
    cp "${PROJECT_DIR}/tunnels.json.example" "$CONFIG_FILE"
    echo "       Created: ${CONFIG_FILE}"
    echo ""
    echo "  >>> Edit tunnels.json with your GCP instance details, then re-run install.sh <<<"
    echo ""
    exit 1
fi

# 6. Validate tunnel config (sources config.sh which does full validation)
echo ""
echo "Validating tunnel configuration..."
source "${PROJECT_DIR}/config.sh"
echo "[OK] Configuration valid (${#TUNNEL_NAMES[@]} tunnel(s) configured)"

# 7. Determine SwiftBar plugin directory
PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "")
if [[ -z "$PLUGIN_DIR" ]]; then
    PLUGIN_DIR="${HOME}/SwiftBarPlugins"
    echo ""
    echo "[INFO] SwiftBar plugin directory not configured yet."
    echo "       Using default: ${PLUGIN_DIR}"
    echo "       When SwiftBar launches for the first time, it will ask you to choose a plugin folder."
    echo "       Point it to: ${PLUGIN_DIR}"
fi

# 8. Create state directory
mkdir -p "$STATE_DIR"
echo "[OK] State directory: ${STATE_DIR}"

# 9. Make scripts executable
chmod +x "${PROJECT_DIR}/${PLUGIN_NAME}"
chmod +x "${PROJECT_DIR}/lib/proxy-ctl.sh"
echo "[OK] Scripts made executable"

# 10. Create symlink in plugin directory
mkdir -p "$PLUGIN_DIR"
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
echo "  3. The SQL Proxy toggle will appear in your menu bar"
echo ""
echo "Tunnels configured:"
for i in "${!TUNNEL_NAMES[@]}"; do
    echo "  ${TUNNEL_LABELS[$i]}: localhost:${TUNNEL_PORTS[$i]} → ${TUNNEL_INSTANCES[$i]}"
done
