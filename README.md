# SQL Proxy Menubar

A macOS menu bar tool ([SwiftBar](https://swiftbar.app) plugin) to manage Google Cloud SQL Proxy tunnels with one click.

## Features

- Start/stop Cloud SQL Proxy tunnels from the menu bar
- Color-coded status: green (all connected), orange (partial), gray (none)
- Per-tunnel and bulk start/stop controls
- Copy `mysql` connection strings to clipboard
- View tunnel logs in Console.app
- Auto-refreshes every 5 seconds
- Configure any number of tunnels via a simple JSON file

## Prerequisites

Install the following via [Homebrew](https://brew.sh):

```bash
brew install cloud-sql-proxy jq
brew install --cask swiftbar
```

You also need the [gcloud CLI](https://cloud.google.com/sdk/docs/install) with Application Default Credentials:

```bash
gcloud auth application-default login
```

## Quick Start

```bash
git clone git@github.com:matpb/sql-proxy-menubar.git
cd sql-proxy-menubar
cp tunnels.json.example tunnels.json
# Edit tunnels.json with your GCP instance details
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
  ]
}
```

### Tunnel fields

| Field      | Required | Description                                                      |
|------------|----------|------------------------------------------------------------------|
| `name`     | Yes      | Short identifier (used in CLI and filenames, e.g. `dev`, `prod`) |
| `instance` | Yes      | GCP connection string: `project:region:instance`                 |
| `port`     | Yes      | Local port to bind (e.g. `3307`)                                 |
| `label`    | No       | Display name in menu bar (defaults to capitalized `name`)        |

### Top-level fields

| Field          | Required | Description                                            |
|----------------|----------|--------------------------------------------------------|
| `proxy_binary` | No       | Path to `cloud-sql-proxy` binary (auto-detected if omitted) |

### Adding a tunnel

Add an entry to the `tunnels` array in `tunnels.json`:

```json
{
  "name": "staging",
  "label": "Staging",
  "instance": "my-project:us-central1:my-db-staging",
  "port": 3309
}
```

The menu bar updates automatically on the next refresh cycle.

### Removing a tunnel

Remove the entry from the `tunnels` array. Stop the tunnel first if it's running.

## Usage

### Menu bar

Click the menu bar icon to:

- **Start/Stop** individual tunnels
- **Start All / Stop All**
- **Copy connection string** to clipboard
- **View logs** in Console.app

The icon shows each tunnel's status using the first letter of its label:
`D:+ P:-` means Dev is running, Prod is stopped.

### CLI

```bash
./lib/proxy-ctl.sh start dev      # Start a tunnel
./lib/proxy-ctl.sh stop prod      # Stop a tunnel
./lib/proxy-ctl.sh start all      # Start all tunnels
./lib/proxy-ctl.sh stop all       # Stop all tunnels
./lib/proxy-ctl.sh toggle dev     # Toggle a tunnel
./lib/proxy-ctl.sh status         # Show all tunnel statuses
./lib/proxy-ctl.sh copy dev       # Copy connection string
```

### Connecting

```bash
mysql -h 127.0.0.1 -P 3307 -u <user> -p
```

## Uninstall

```bash
./uninstall.sh
```

Stops running tunnels, removes the SwiftBar symlink, and cleans up state files. Project files are preserved.

## Troubleshooting

- **Tunnel won't start** — Check logs at `~/.sql-proxy-menubar/<name>.log`
- **Port already in use** — Check with `lsof -i :<port>`
- **Auth errors** — Run `gcloud auth application-default login`
- **Stale status** — Click "Refresh" in the menu, or wait for auto-refresh (5s)
- **Config errors** — Run `./lib/proxy-ctl.sh status` to see validation errors

## License

[MIT](LICENSE)
