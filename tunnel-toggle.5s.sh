#!/usr/bin/env bash

# SwiftBar plugin: Tunnel Toggle
# Filename: tunnel-toggle.5s.sh (refreshes every 5 seconds)

# Resolve real script location (follows symlinks)
SELF="$0"
if [[ -L "$SELF" ]]; then
    SELF="$(readlink "$SELF")"
    # Handle relative symlink targets
    if [[ "$SELF" != /* ]]; then
        SELF="$(cd "$(dirname "$0")" && cd "$(dirname "$SELF")" && pwd)/$(basename "$SELF")"
    fi
fi
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"

source "${SCRIPT_DIR}/config.sh"
SQL_HELPER="${SCRIPT_DIR}/lib/proxy-ctl.sh"
SSH_HELPER="${SCRIPT_DIR}/lib/ssh-ctl.sh"
AUTH_HELPER="${SCRIPT_DIR}/lib/auth-ctl.sh"

# --- Detect status of SQL tunnels (running | needs-auth | stopped) ---
declare -a SQL_STATUSES=()
sql_running=0
sql_needs_auth=0

for i in "${!TUNNEL_NAMES[@]}"; do
    name="${TUNNEL_NAMES[$i]}"
    state="$(sql_status_of "$name")"
    SQL_STATUSES[$i]="$state"
    case "$state" in
        running)    ((sql_running++)) ;;
        needs-auth) ((sql_needs_auth++)) ;;
    esac
done

# --- Detect status of SSH tunnels ---
declare -a SSH_STATUSES=()
ssh_running=0

for i in "${!SSH_NAMES[@]}"; do
    name="${SSH_NAMES[$i]}"
    pf="$(ssh_pid_file "$name")"
    if [[ -f "$pf" ]] && kill -0 "$(cat "$pf" 2>/dev/null)" 2>/dev/null; then
        SSH_STATUSES[$i]="running"
        ((ssh_running++))
    else
        SSH_STATUSES[$i]="stopped"
    fi
done

sql_total=${#TUNNEL_NAMES[@]}
ssh_total=${#SSH_NAMES[@]}
total=$((sql_total + ssh_total))
running_count=$((sql_running + ssh_running))

# --- Menu bar title ---
title_parts=()

for i in "${!TUNNEL_NAMES[@]}"; do
    letter="${TUNNEL_LABELS[$i]:0:1}"
    case "${SQL_STATUSES[$i]}" in
        running)    icon="+" ;;
        needs-auth) icon="!" ;;
        *)          icon="-" ;;
    esac
    title_parts+=("${letter}:${icon}")
done

for i in "${!SSH_NAMES[@]}"; do
    letter="${SSH_LABELS[$i]:0:1}"
    icon=$([[ "${SSH_STATUSES[$i]}" == "running" ]] && echo "+" || echo "-")
    title_parts+=("${letter}:${icon}")
done

title=$(IFS=" "; echo "${title_parts[*]}")

if [[ $sql_needs_auth -gt 0 ]]; then
    color="#FF9500"
elif [[ $running_count -eq 0 ]]; then
    color="#888888"
elif [[ $running_count -eq $total ]]; then
    color="#34C759"
else
    color="#FF9500"
fi

echo "${title} | sfimage=network color=${color}"

# --- Dropdown menu ---
echo "---"

# SQL tunnel sections
if [[ $sql_total -gt 0 ]]; then
    echo "SQL Tunnels | sfimage=server.rack refresh=true"
    for i in "${!TUNNEL_NAMES[@]}"; do
        name="${TUNNEL_NAMES[$i]}"
        label="${TUNNEL_LABELS[$i]}"
        port="${TUNNEL_PORTS[$i]}"
        instance="${TUNNEL_INSTANCES[$i]}"
        state="${SQL_STATUSES[$i]}"

        if [[ "$state" == "running" ]]; then
            echo "--${label}: Connected | color=#34C759 sfimage=checkmark.circle.fill"
            echo "----localhost:${port} | color=#888888 size=12"
            echo "----${instance} | color=#888888 size=10"
            echo "----Stop ${label} | bash=${SQL_HELPER} param1=stop param2=${name} terminal=false refresh=true color=#FF3B30"
        elif [[ "$state" == "needs-auth" ]]; then
            echo "--${label}: Needs gcloud auth | color=#FF9500 sfimage=exclamationmark.circle"
            echo "----localhost:${port} | color=#888888 size=12"
            echo "----${instance} | color=#888888 size=10"
            echo "----Reauth gcloud & restart | bash=${AUTH_HELPER} param1=login-restart terminal=true refresh=true color=#FF9500"
        else
            echo "--${label}: Disconnected | color=#FF3B30 sfimage=xmark.circle"
            echo "----localhost:${port} | color=#888888 size=12"
            echo "----Start ${label} | bash=${SQL_HELPER} param1=start param2=${name} terminal=false refresh=true color=#34C759"
        fi
    done
fi

# SSH tunnel sections
if [[ $ssh_total -gt 0 ]]; then
    echo "---"
    echo "SSH Tunnels | sfimage=network.badge.shield.half.filled refresh=true"
    for i in "${!SSH_NAMES[@]}"; do
        name="${SSH_NAMES[$i]}"
        label="${SSH_LABELS[$i]}"
        forward="${SSH_FORWARDS[$i]}"
        host="${SSH_HOSTS[$i]}"
        state="${SSH_STATUSES[$i]}"

        # Extract local port from forward spec (e.g. "-L 8420:127.0.0.1:8420" -> 8420)
        local_port=$(echo "$forward" | grep -oE '[0-9]+' | head -1)

        if [[ "$state" == "running" ]]; then
            echo "--${label}: Connected | color=#34C759 sfimage=checkmark.circle.fill"
            echo "----localhost:${local_port} | color=#888888 size=12"
            echo "----${host} | color=#888888 size=10"
            echo "----Stop ${label} | bash=${SSH_HELPER} param1=stop param2=${name} terminal=false refresh=true color=#FF3B30"
        else
            echo "--${label}: Disconnected | color=#FF3B30 sfimage=xmark.circle"
            echo "----localhost:${local_port} | color=#888888 size=12"
            echo "----Start ${label} | bash=${SSH_HELPER} param1=start param2=${name} terminal=false refresh=true color=#34C759"
        fi
    done
fi

echo "---"

# Bulk actions — trigger both SQL and SSH helpers via bulk-ctl
if [[ $running_count -eq $total ]]; then
    echo "Stop All Tunnels | bash=${SCRIPT_DIR}/lib/bulk-ctl.sh param1=stop terminal=false refresh=true color=#FF3B30 sfimage=stop.circle"
elif [[ $running_count -eq 0 ]]; then
    echo "Start All Tunnels | bash=${SCRIPT_DIR}/lib/bulk-ctl.sh param1=start terminal=false refresh=true color=#34C759 sfimage=play.circle"
else
    echo "Start All Tunnels | bash=${SCRIPT_DIR}/lib/bulk-ctl.sh param1=start terminal=false refresh=true color=#34C759 sfimage=play.circle"
    echo "Stop All Tunnels | bash=${SCRIPT_DIR}/lib/bulk-ctl.sh param1=stop terminal=false refresh=true color=#FF3B30 sfimage=stop.circle"
fi

echo "---"

# Copy connection strings
echo "Copy Connection String | sfimage=square.on.square refresh=true"
for i in "${!TUNNEL_NAMES[@]}"; do
    name="${TUNNEL_NAMES[$i]}"
    label="${TUNNEL_LABELS[$i]}"
    echo "--${label} (SQL) | bash=${SQL_HELPER} param1=copy param2=${name} terminal=false"
done
for i in "${!SSH_NAMES[@]}"; do
    name="${SSH_NAMES[$i]}"
    label="${SSH_LABELS[$i]}"
    echo "--${label} (SSH) | bash=${SSH_HELPER} param1=copy param2=${name} terminal=false"
done

echo "---"

# View logs
echo "View Logs | sfimage=text.magnifyingglass refresh=true"
for i in "${!TUNNEL_NAMES[@]}"; do
    name="${TUNNEL_NAMES[$i]}"
    label="${TUNNEL_LABELS[$i]}"
    lf="$(log_file "$name")"
    echo "--${label} (SQL) | bash=/usr/bin/open param1=-a param2=Console param3=${lf} terminal=false"
done
for i in "${!SSH_NAMES[@]}"; do
    name="${SSH_NAMES[$i]}"
    label="${SSH_LABELS[$i]}"
    lf="$(ssh_log_file "$name")"
    echo "--${label} (SSH) | bash=/usr/bin/open param1=-a param2=Console param3=${lf} terminal=false"
done

echo "---"
echo "Reauth gcloud (ADC) | bash=${AUTH_HELPER} param1=login-restart terminal=true refresh=true sfimage=exclamationmark.circle"
echo "Edit Config | bash=/usr/bin/open param1=-e param2=${CONFIG_FILE} terminal=false sfimage=square.and.pencil"
echo "Refresh | refresh=true sfimage=arrow.clockwise.circle"

echo "---"
echo "About | sfimage=info.circle refresh=true"
echo "--Tunnel Toggle v2.0 | color=#888888"
echo "--SQL Proxies: ${sql_total} configured | color=#888888 size=12"
echo "--SSH Tunnels: ${ssh_total} configured | color=#888888 size=12"
echo "--Config: ${SCRIPT_DIR}/tunnels.json | color=#888888 size=12"
echo "--Logs: ${STATE_DIR}/ | color=#888888 size=12"
