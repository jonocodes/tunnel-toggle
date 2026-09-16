#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACTION="${1:-start}"

"${SCRIPT_DIR}/lib/proxy-ctl.sh" "$ACTION" all || true
"${SCRIPT_DIR}/lib/ssh-ctl.sh" "$ACTION" all || true
