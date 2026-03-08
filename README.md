# Tunnel Toggle

A macOS menu bar tool ([SwiftBar](https://swiftbar.app) plugin) to manage Cloud SQL Proxy and SSH tunnels with one click.

## Features

- Start/stop Cloud SQL Proxy and SSH tunnels from the menu bar
- Color-coded status: green (all connected), orange (partial), gray (none)
- Per-tunnel and bulk start/stop controls
- Copy connection strings to clipboard
- View tunnel logs in Console.app
- Auto-refreshes every 5 seconds
- Configure any number of tunnels via a simple JSON file

## Prerequisites

Install the following via [Homebrew](https://brew.sh):

```bash
brew install jq
brew install cloud-sql-proxy  # for SQL tunnels
brew install --cask swiftbar
```

For SQL tunnels, you also need the [gcloud CLI](https://cloud.google.com/sdk/docs/install) with Application Default Credentials:

```bash
gcloud auth application-default login
```

For SSH tunnels, keys must be passphrase-free or loaded in `ssh-agent`.

## Quick Start

```bash
cd ~/Documents/sql-proxy-menubar
cp tunnels.json.example tunnels.json
# Edit tunnels.json with your tunnel details
./install.sh
```

## Configuration

All tunnel definitions live in `tunnels.json`. This file is gitignored so your credentials stay local.

### Format

```json
{
  "proxy_binary": "/usr/local/bin/cloud-sql-proxy",
  "tunnels": [
    {
      "name": "dev",
      "label": "Dev",
      "instance": "my-project:us-central1:my-db-dev",
      "port": 3307
    }
  ],
  "ssh_tunnels": [
    {
      "name": "cortex",
      "label": "C",
      "forward": "-L 8420:127.0.0.1:8420",
      "host": "cortex@89.167.86.10",
      "opts": ""
    }
  ]
}
```

### SQL tunnel fields

| Field      | Required | Description                                                      |
|------------|----------|------------------------------------------------------------------|
| `name`     | Yes      | Short identifier (used in CLI and filenames, e.g. `dev`, `prod`) |
| `instance` | Yes      | GCP connection string: `project:region:instance`                 |
| `port`     | Yes      | Local port to bind (e.g. `3307`)                                 |
| `label`    | No       | Display name in menu bar (defaults to capitalized `name`)        |

### SSH tunnel fields

| Field     | Required | Description                                               |
|-----------|----------|-----------------------------------------------------------|
| `name`    | Yes      | Short identifier (e.g. `cortex`)                          |
| `forward` | Yes      | Forward spec: `-L local:remote:port` or `-R remote:local` |
| `host`    | Yes      | SSH target: `[user@]host`                                 |
| `label`   | No       | Display name in menu bar (defaults to capitalized `name`) |
| `opts`    | No       | Extra SSH options (e.g. `"-p 2222 -i ~/.ssh/key"`)        |

The resulting SSH command is: `ssh -N ${opts} ${forward} ${host}`

### Top-level fields

| Field          | Required | Description                                            |
|----------------|----------|--------------------------------------------------------|
| `proxy_binary` | No       | Path to `cloud-sql-proxy` binary (auto-detected if omitted) |

## Usage

### Menu bar

Click the menu bar icon to:

- **Start/Stop** individual SQL or SSH tunnels
- **Start All / Stop All** (both types)
- **Copy connection string** to clipboard
- **View logs** in Console.app

The icon shows each tunnel's status using the first letter of its label:
`D:+ P:- C:+` means Dev SQL is running, Prod SQL is stopped, Cortex SSH is running.

### CLI

```bash
# SQL tunnels
./lib/proxy-ctl.sh start dev      # Start a SQL tunnel
./lib/proxy-ctl.sh stop all       # Stop all SQL tunnels
./lib/proxy-ctl.sh status         # Show SQL tunnel statuses

# SSH tunnels
./lib/ssh-ctl.sh start cortex     # Start an SSH tunnel
./lib/ssh-ctl.sh stop all         # Stop all SSH tunnels
./lib/ssh-ctl.sh status           # Show SSH tunnel statuses

# Both
./lib/bulk-ctl.sh start           # Start all tunnels
./lib/bulk-ctl.sh stop            # Stop all tunnels
```

## Uninstall

```bash
./uninstall.sh
```

Stops running tunnels, removes the SwiftBar symlink, and cleans up state files. Project files are preserved.

## Troubleshooting

- **Tunnel won't start** — Check logs at `~/.tunnel-toggle/sql/<name>.log` or `~/.tunnel-toggle/ssh/<name>.log`
- **Port already in use** — Check with `lsof -i :<port>`
- **SQL auth errors** — Run `gcloud auth application-default login`
- **SSH host key changed** — Remove the old key from `~/.ssh/known_hosts`
- **SSH key passphrase** — Load your key into ssh-agent: `ssh-add ~/.ssh/your_key`
- **Stale status** — Click "Refresh" in the menu, or wait for auto-refresh (5s)
- **Config errors** — Run `./lib/proxy-ctl.sh status` or `./lib/ssh-ctl.sh status` to see validation errors

## License

[MIT](LICENSE)
