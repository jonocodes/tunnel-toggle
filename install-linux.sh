#!/usr/bin/env bash
set -euo pipefail

# Tunnel Toggle — Linux installer
# Installs the system-tray daemon (StatusNotifierItem) as a systemd --user
# service. Works on any desktop with an SNI tray: KDE Plasma natively, GNOME
# with the AppIndicator extension, wlroots compositors via a bar like Waybar.

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_NAME="tunnel-tray.service"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

echo "=== Tunnel Toggle — Linux Installer ==="
echo ""

# 1. Core CLI dependencies
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq not found. Install it with your package manager (e.g. sudo pacman -S jq)."
    exit 1
fi
echo "[OK] jq: $(command -v jq)"

if ! command -v cloud-sql-proxy &>/dev/null; then
    echo "[WARN] cloud-sql-proxy not found on PATH. SQL tunnels won't start until it's installed"
    echo "       or 'proxy_binary' is set in tunnels.json."
else
    echo "[OK] cloud-sql-proxy: $(command -v cloud-sql-proxy)"
fi

# 2. Python + GObject bindings for the tray daemon.
# Prefer the system interpreter — distro packages install the GTK/AppIndicator
# bindings for /usr/bin/python3, NOT for pyenv/conda/venv pythons that may shadow
# it on PATH. Fall back to PATH only if there's no system python.
PYTHON="/usr/bin/python3"
[[ -x "$PYTHON" ]] || PYTHON="$(command -v python3 || true)"
if [[ -z "$PYTHON" ]]; then
    echo "ERROR: python3 not found."
    exit 1
fi
if ! "$PYTHON" - <<'PY' &>/dev/null
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import Gtk, AyatanaAppIndicator3
PY
then
    echo "ERROR: Python GTK/AppIndicator bindings missing."
    echo "       Arch:   sudo pacman -S python-gobject gtk3 libayatana-appindicator"
    echo "       Debian: sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1"
    echo "       Fedora: sudo dnf install python3-gobject gtk3 libayatana-appindicator-gtk3"
    exit 1
fi
echo "[OK] Python GTK/AppIndicator bindings present"

# 3. gcloud Application Default Credentials (needed by the SQL proxy)
if command -v gcloud &>/dev/null; then
    if gcloud auth application-default print-access-token &>/dev/null 2>&1; then
        echo "[OK] gcloud Application Default Credentials configured"
    else
        echo "[WARN] gcloud ADC not configured. Run: gcloud auth application-default login"
    fi
else
    echo "[WARN] gcloud not found — required for Cloud SQL tunnels."
fi

# 4. tunnels.json
CONFIG_FILE="${PROJECT_DIR}/tunnels.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    cp "${PROJECT_DIR}/tunnels.json.example" "$CONFIG_FILE"
    echo ""
    echo "[INFO] Created ${CONFIG_FILE} from the example."
    echo "  >>> Edit tunnels.json with your tunnels, then re-run ./install-linux.sh <<<"
    exit 1
fi
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo "ERROR: Invalid JSON in ${CONFIG_FILE}."
    exit 1
fi
echo "[OK] Config: ${CONFIG_FILE}"

# 5. Make scripts executable
chmod +x "${PROJECT_DIR}/lib/proxy-ctl.sh" \
         "${PROJECT_DIR}/lib/ssh-ctl.sh" \
         "${PROJECT_DIR}/lib/bulk-ctl.sh" \
         "${PROJECT_DIR}/lib/auth-ctl.sh" \
         "${PROJECT_DIR}/lib/tunnel-tray.py" \
         "${PROJECT_DIR}/tunnel" 2>/dev/null || true
echo "[OK] Scripts made executable"

# 6. Write the systemd user unit with the REAL repo path (no hardcoded assumption)
mkdir -p "$USER_UNIT_DIR"
cat > "${USER_UNIT_DIR}/${SERVICE_NAME}" <<UNIT
[Unit]
Description=Tunnel Toggle SNI tray indicator
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=${PYTHON} ${PROJECT_DIR}/lib/tunnel-tray.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
UNIT
echo "[OK] Installed ${USER_UNIT_DIR}/${SERVICE_NAME}"

# 7. Enable + start
systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME"
echo "[OK] Service enabled and started"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "A tray icon should appear in your system tray (SNI-capable tray required:"
echo "KDE Plasma native, GNOME needs the AppIndicator extension, Waybar has a tray module)."
echo ""
echo "Manage tunnels from the tray, or from the CLI:"
echo "  ${PROJECT_DIR}/tunnel status"
echo "  ${PROJECT_DIR}/tunnel up | down [name]"
echo ""
echo "Service logs:  journalctl --user -u ${SERVICE_NAME} -f"
