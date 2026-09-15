#!/usr/bin/python3
"""System tray indicator for tunnel-toggle (Linux).

Polls proxy-ctl.sh and ssh-ctl.sh every 5s, exposes per-tunnel start/stop
plus bulk actions through a StatusNotifierItem. Works on any SNI-capable tray:
KDE Plasma natively, GNOME with the AppIndicator extension, and wlroots bars
like Waybar.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import AyatanaAppIndicator3 as AppIndicator  # noqa: E402
from gi.repository import GLib, Gtk  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_FILE = REPO_ROOT / "tunnels.json"
SQL_CTL = REPO_ROOT / "lib" / "proxy-ctl.sh"
SSH_CTL = REPO_ROOT / "lib" / "ssh-ctl.sh"
BULK_CTL = REPO_ROOT / "lib" / "bulk-ctl.sh"
AUTH_CTL = REPO_ROOT / "lib" / "auth-ctl.sh"

POLL_SECONDS = 5

ICON_ALL = "network-connect"
ICON_SOME = "network-limited"
ICON_NONE = "network-disconnect"


def load_config():
    with open(CONFIG_FILE) as f:
        cfg = json.load(f)
    sql = cfg.get("tunnels", []) or []
    ssh = cfg.get("ssh_tunnels", []) or []
    return sql, ssh


def config_mtime():
    try:
        return CONFIG_FILE.stat().st_mtime
    except OSError:
        return None


def parse_status(script: Path):
    try:
        out = subprocess.check_output(
            [str(script), "status"],
            text=True,
            timeout=5,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return {}
    states = {}
    for line in out.splitlines():
        if ":" not in line:
            continue
        name, state = line.split(":", 1)
        states[name.strip()] = state.strip() or "stopped"
    return states


def run_ctl(script: Path, *args):
    subprocess.Popen(
        [str(script), *args],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


TERMINALS = (
    ("xdg-terminal-exec", lambda a: ["xdg-terminal-exec", *a]),
    ("gnome-terminal", lambda a: ["gnome-terminal", "--", *a]),
    ("kgx", lambda a: ["kgx", "--", *a]),
    ("konsole", lambda a: ["konsole", "-e", *a]),
    ("kitty", lambda a: ["kitty", *a]),
    ("alacritty", lambda a: ["alacritty", "-e", *a]),
    ("xterm", lambda a: ["xterm", "-e", *a]),
)


def run_in_terminal(argv):
    """Run an interactive command in a terminal emulator.

    Reauthing gcloud needs a TTY so the user can complete the browser flow.
    Falls back to a detached run if no known terminal is installed.
    """
    for binary, build in TERMINALS:
        if shutil.which(binary):
            subprocess.Popen(
                build(argv),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            return
    subprocess.Popen(
        argv,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


class TunnelTray:
    def __init__(self):
        self.sql, self.ssh = load_config()
        self._mtime = config_mtime()
        self.indicator = AppIndicator.Indicator.new(
            "tunnel-toggle",
            ICON_NONE,
            AppIndicator.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE)
        self.indicator.set_title("Tunnel Toggle")
        self.menu = Gtk.Menu()
        self.indicator.set_menu(self.menu)
        self.refresh()
        GLib.timeout_add_seconds(POLL_SECONDS, self._tick)

    def _tick(self):
        self._reload_if_changed()
        self.refresh()
        return True

    def _reload_if_changed(self):
        mtime = config_mtime()
        if mtime is None or mtime == self._mtime:
            return
        try:
            self.sql, self.ssh = load_config()
        except (OSError, json.JSONDecodeError) as exc:
            print(f"config reload failed, keeping previous config: {exc}", file=sys.stderr)
            return
        self._mtime = mtime

    def refresh(self):
        sql_state = parse_status(SQL_CTL)
        ssh_state = parse_status(SSH_CTL)

        for child in self.menu.get_children():
            self.menu.remove(child)

        running = sum(v == "running" for v in sql_state.values())
        running += sum(v == "running" for v in ssh_state.values())
        total = len(self.sql) + len(self.ssh)
        if total == 0:
            self.indicator.set_icon_full(ICON_NONE, "no tunnels configured")
        elif running == 0:
            self.indicator.set_icon_full(ICON_NONE, "all tunnels stopped")
        elif running == total:
            self.indicator.set_icon_full(ICON_ALL, "all tunnels running")
        else:
            self.indicator.set_icon_full(ICON_SOME, f"{running}/{total} tunnels running")

        label = f"{running}/{total} running"
        self.indicator.set_label(label, "tunnel-toggle")

        if self.sql:
            self._section_header("SQL Tunnels")
            for t in self.sql:
                self._tunnel_item(t, sql_state, SQL_CTL, kind="sql")

        if self.ssh:
            if self.sql:
                self.menu.append(Gtk.SeparatorMenuItem())
            self._section_header("SSH Tunnels")
            for t in self.ssh:
                self._tunnel_item(t, ssh_state, SSH_CTL, kind="ssh")

        self.menu.append(Gtk.SeparatorMenuItem())
        self._action("Start all", lambda *_: run_ctl(BULK_CTL, "start"))
        self._action("Stop all", lambda *_: run_ctl(BULK_CTL, "stop"))
        self.menu.append(Gtk.SeparatorMenuItem())

        copy_root = Gtk.MenuItem(label="Copy connection string")
        copy_sub = Gtk.Menu()
        copy_root.set_submenu(copy_sub)
        for t in self.sql:
            mi = Gtk.MenuItem(label=f"{t.get('label', t['name'])} (SQL)")
            mi.connect("activate", self._copy_sql, t)
            copy_sub.append(mi)
        for t in self.ssh:
            mi = Gtk.MenuItem(label=f"{t.get('label', t['name'])} (SSH)")
            mi.connect("activate", self._copy_ssh, t)
            copy_sub.append(mi)
        self.menu.append(copy_root)

        self.menu.append(Gtk.SeparatorMenuItem())
        self._action("Reauth gcloud (ADC)", self._reauth)
        self._action("Edit config", self._edit_config)
        self._action("Reload config", self._reload_now)
        self.menu.append(Gtk.SeparatorMenuItem())
        self._action("Quit", Gtk.main_quit)

        self.menu.show_all()

    def _section_header(self, text: str):
        item = Gtk.MenuItem(label=text)
        item.set_sensitive(False)
        self.menu.append(item)

    def _tunnel_item(self, t, state_map, script: Path, kind: str):
        name = t["name"]
        label = t.get("label", name)
        state = state_map.get(name, "stopped")
        if kind == "sql":
            detail = f"localhost:{t['port']} → {t['instance']}"
        else:
            forward = t.get("forward", "")
            local_port = next((tok for tok in forward.split() if tok.isdigit()), "?")
            if local_port == "?":
                for tok in forward.replace(":", " ").split():
                    if tok.isdigit():
                        local_port = tok
                        break
            detail = f"localhost:{local_port} → {t.get('host', '')}"

        if state == "running":
            prefix, action = "● ", ("stop", name)
        elif state == "needs-auth":
            prefix, action = "⚠ ", ("login-restart", None)
        else:
            prefix, action = "○ ", ("start", name)

        item = Gtk.MenuItem(label=f"{prefix}{label} — {detail}")
        if action[0] == "login-restart":
            item.connect("activate", self._reauth)
        else:
            item.connect(
                "activate",
                lambda *_: run_ctl(script, action[0], action[1]),
            )
        self.menu.append(item)

    def _action(self, label: str, callback):
        item = Gtk.MenuItem(label=label)
        item.connect("activate", callback)
        self.menu.append(item)

    def _reauth(self, *_):
        run_in_terminal([str(AUTH_CTL), "login-restart"])

    def _edit_config(self, *_):
        if shutil.which("xdg-open"):
            opener = ["xdg-open", str(CONFIG_FILE)]
        else:
            opener = [os.environ.get("EDITOR") or "nano", str(CONFIG_FILE)]
        subprocess.Popen(
            opener,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

    def _reload_now(self, *_):
        self._mtime = None
        self._reload_if_changed()
        self.refresh()

    def _copy_sql(self, _item, t):
        port = t["port"]
        if t.get("engine", "mysql") == "postgres":
            self._copy(f"psql -h 127.0.0.1 -p {port}")
        else:
            self._copy(f"mysql -h 127.0.0.1 -P {port}")

    def _copy_ssh(self, _item, t):
        forward = t.get("forward", "")
        local_port = "?"
        for tok in forward.replace(":", " ").split():
            if tok.isdigit():
                local_port = tok
                break
        self._copy(f"localhost:{local_port}")

    def _copy(self, text: str):
        clipboard = Gtk.Clipboard.get_default(Gtk.Window().get_display())
        clipboard.set_text(text, -1)
        clipboard.store()


def main():
    if not CONFIG_FILE.exists():
        print(f"missing config: {CONFIG_FILE}", file=sys.stderr)
        sys.exit(1)
    TunnelTray()
    Gtk.main()


if __name__ == "__main__":
    main()
