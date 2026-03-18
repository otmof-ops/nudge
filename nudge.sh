#!/usr/bin/env bash
# nudge — A gentle nudge to keep your system fresh.
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

CONF="${HOME}/.config/nudge.conf"
LOCK="/tmp/nudge-${UID}.lock"

# --- Load config ---
ENABLED=true
DELAY=45

if [[ -f "$CONF" ]]; then
    # shellcheck source=/dev/null
    source "$CONF"
fi

if [[ "$ENABLED" != "true" ]]; then
    exit 0
fi

# --- PID lock ---
if [[ -f "$LOCK" ]]; then
    OLD_PID=$(cat "$LOCK" 2>/dev/null || true)
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        exit 0
    fi
    rm -f "$LOCK"
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# --- Delay ---
sleep "$DELAY"

# --- Network check ---
check_network() {
    ping -c 1 -W 5 archive.ubuntu.com &>/dev/null
}

if ! check_network; then
    sleep 15
    if ! check_network; then
        exit 0
    fi
fi

# --- apt lock check ---
if fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1; then
    exit 0
fi

# --- Count updates ---
UPDATES=0
SECURITY=0

if [[ -x /usr/lib/update-notifier/apt-check ]]; then
    APT_CHECK_OUTPUT=$(/usr/lib/update-notifier/apt-check 2>&1 || true)
    UPDATES=$(echo "$APT_CHECK_OUTPUT" | cut -d';' -f1)
    SECURITY=$(echo "$APT_CHECK_OUTPUT" | cut -d';' -f2)
else
    UPDATES=$(apt list --upgradable 2>/dev/null | grep -c 'upgradable' || true)
    SECURITY=0
fi

# --- Exit if up to date ---
if [[ "$UPDATES" -eq 0 ]]; then
    exit 0
fi

# --- Build dialog message ---
MSG="There are $UPDATES package update(s) available."
if [[ "$SECURITY" -gt 0 ]]; then
    MSG="$MSG\n$SECURITY of these are security updates."
fi
MSG="$MSG\n\nWould you like to update now?"

# --- Show prompt ---
if kdialog --icon system-software-update \
           --title "System Updates Available" \
           --yesno "$MSG" 2>/dev/null; then
    konsole --hold -e bash -c 'sudo apt update && sudo apt full-upgrade'
fi

exit 0
