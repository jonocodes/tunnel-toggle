#!/usr/bin/env bash

# SwiftBar plugin: SQL Proxy Menubar
# Filename: sql-proxy.5s.sh (refreshes every 5 seconds)

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
HELPER="${SCRIPT_DIR}/lib/proxy-ctl.sh"

# --- Detect status of each tunnel ---
declare -a STATUSES=()
running_count=0

for i in "${!TUNNEL_NAMES[@]}"; do
    name="${TUNNEL_NAMES[$i]}"
    pf="$(pid_file "$name")"
    if [[ -f "$pf" ]] && kill -0 "$(cat "$pf" 2>/dev/null)" 2>/dev/null; then
        STATUSES[$i]="running"
        ((running_count++))
    else
        STATUSES[$i]="stopped"
    fi
done

total=${#TUNNEL_NAMES[@]}

# --- Menu bar title (dynamic) ---
title_parts=()
for i in "${!TUNNEL_NAMES[@]}"; do
    letter="${TUNNEL_LABELS[$i]:0:1}"
    icon=$([[ "${STATUSES[$i]}" == "running" ]] && echo "+" || echo "-")
    title_parts+=("${letter}:${icon}")
done
title=$(IFS=" "; echo "${title_parts[*]}")

if [[ $running_count -eq 0 ]]; then
    color="#888888"
elif [[ $running_count -eq $total ]]; then
    color="#34C759"
else
    color="#FF9500"
fi

echo "${title} | sfimage=cylinder.split color=${color}"

# --- Dropdown menu ---
echo "---"

# Per-tunnel sections
for i in "${!TUNNEL_NAMES[@]}"; do
    name="${TUNNEL_NAMES[$i]}"
    label="${TUNNEL_LABELS[$i]}"
    port="${TUNNEL_PORTS[$i]}"
    instance="${TUNNEL_INSTANCES[$i]}"
    state="${STATUSES[$i]}"

    if [[ "$state" == "running" ]]; then
        echo "${label}: Connected | color=#34C759 sfimage=checkmark.circle.fill"
        echo "--localhost:${port} | color=#888888 size=12"
        echo "--${instance} | color=#888888 size=10"
        echo "--Stop ${label} Tunnel | bash=${HELPER} param1=stop param2=${name} terminal=false refresh=true color=#FF3B30"
    else
        echo "${label}: Disconnected | color=#FF3B30 sfimage=xmark.circle"
        echo "--localhost:${port} | color=#888888 size=12"
        echo "--Start ${label} Tunnel | bash=${HELPER} param1=start param2=${name} terminal=false refresh=true color=#34C759"
    fi
done

echo "---"

# Bulk actions
if [[ $running_count -eq $total ]]; then
    echo "Stop All Tunnels | bash=${HELPER} param1=stop param2=all terminal=false refresh=true color=#FF3B30 sfimage=stop.circle"
elif [[ $running_count -eq 0 ]]; then
    echo "Start All Tunnels | bash=${HELPER} param1=start param2=all terminal=false refresh=true color=#34C759 sfimage=play.circle"
else
    echo "Start All Tunnels | bash=${HELPER} param1=start param2=all terminal=false refresh=true color=#34C759 sfimage=play.circle"
    echo "Stop All Tunnels | bash=${HELPER} param1=stop param2=all terminal=false refresh=true color=#FF3B30 sfimage=stop.circle"
fi

echo "---"

# Copy connection strings
echo "Copy Connection String | sfimage=doc.on.doc"
for i in "${!TUNNEL_NAMES[@]}"; do
    name="${TUNNEL_NAMES[$i]}"
    label="${TUNNEL_LABELS[$i]}"
    echo "--${label} | bash=${HELPER} param1=copy param2=${name} terminal=false"
done

echo "---"

# View logs
echo "View Logs | sfimage=doc.text.magnifyingglass"
for i in "${!TUNNEL_NAMES[@]}"; do
    name="${TUNNEL_NAMES[$i]}"
    label="${TUNNEL_LABELS[$i]}"
    lf="$(log_file "$name")"
    echo "--${label} Log | bash=/usr/bin/open param1=-a param2=Console param3=${lf} terminal=false"
done

echo "---"
echo "Refresh | refresh=true sfimage=arrow.clockwise"

echo "---"
echo "About | sfimage=info.circle"
echo "--SQL Proxy Menubar v1.1 | color=#888888"
echo "--Cloud SQL Proxy: $(cloud-sql-proxy --version 2>/dev/null | head -1 || echo 'not found') | color=#888888 size=12"
echo "--Auth: gcloud ADC | color=#888888 size=12"
echo "--Config: ${SCRIPT_DIR}/tunnels.json | color=#888888 size=12"
echo "--Logs: ${STATE_DIR}/ | color=#888888 size=12"
