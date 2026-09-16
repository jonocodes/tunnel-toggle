#!/usr/bin/env bash
set -euo pipefail

# gcloud Application Default Credentials helper for Tunnel Toggle.
# The SQL proxy authenticates with ADC; when the refresh token expires or is
# revoked, tunnels die with an auth error and only an interactive login fixes
# them. The trays call `login` / `login-restart`; `needs-auth` is used to
# detect the condition from tunnel logs.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

ACTION="${1:-status}"

# Names of SQL tunnels whose most recent log shows an ADC auth failure.
needs_auth_tunnels() {
    local name
    for name in "${TUNNEL_NAMES[@]}"; do
        [[ "$(sql_status_of "$name")" == "needs-auth" ]] && echo "$name"
    done
    # Always succeed: callers capture this in a command substitution under
    # `set -e`, where a nonzero return (e.g. the last tunnel is fine) would
    # abort before the output is examined.
    return 0
}

adc_login() {
    if ! command -v "$GCLOUD_BINARY" &>/dev/null; then
        echo "ERROR: gcloud not found on PATH." >&2
        return 1
    fi
    "$GCLOUD_BINARY" auth application-default login
}

restart_needing_auth() {
    local name
    local restart=()
    while IFS= read -r name; do
        [[ -n "$name" ]] && restart+=("$name")
    done < <(needs_auth_tunnels)

    if [[ ${#restart[@]} -eq 0 ]]; then
        echo "No tunnels are waiting on a gcloud reauth."
        return 0
    fi

    echo "Restarting tunnel(s) that needed auth: ${restart[*]}"
    for name in "${restart[@]}"; do
        "${SCRIPT_DIR}/lib/proxy-ctl.sh" start "$name"
    done
}

case "$ACTION" in
    login)
        adc_login
        ;;
    login-restart)
        adc_login && restart_needing_auth
        ;;
    needs-auth)
        names="$(needs_auth_tunnels)"
        if [[ -n "$names" ]]; then
            echo "$names"
            exit 0
        fi
        exit 1
        ;;
    *)
        echo "Usage: $0 <login|login-restart|needs-auth>" >&2
        exit 1
        ;;
esac
