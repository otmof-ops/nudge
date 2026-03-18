#!/usr/bin/env bash
# nudge — A gentle nudge to keep your system fresh.
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.
# Version: 1.1.0

set -euo pipefail

VERSION="1.1.0"
CONF="${HOME}/.config/nudge.conf"
LOCK="/tmp/nudge-${UID}.lock"

# --- Default config values ---
ENABLED=true
DELAY=45
CHECK_SECURITY=true
AUTO_DISMISS=0
UPDATE_COMMAND="sudo apt update && sudo apt full-upgrade"
NETWORK_HOST="archive.ubuntu.com"
NETWORK_TIMEOUT=5
NETWORK_RETRIES=2
NOTIFICATION_BACKEND="auto"
LOG_FILE=""

# --- CLI flags ---
DRY_RUN=false
CHECK_ONLY=false

# --- Parse arguments ---
for arg in "$@"; do
    case "$arg" in
        --version)
            echo "nudge $VERSION"
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --check-only)
            CHECK_ONLY=true
            ;;
        --help|-h)
            echo "nudge $VERSION — A gentle nudge to keep your system fresh."
            echo ""
            echo "Usage: nudge.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --version      Print version and exit"
            echo "  --dry-run      Run checks but don't show dialogs or update"
            echo "  --check-only   Print update count and exit"
            echo "  --help, -h     Show this help"
            exit 0
            ;;
    esac
done

# --- Logging helper ---
log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    if [[ -n "$LOG_FILE" ]]; then
        echo "$msg" >> "$LOG_FILE"
    fi
    if [[ "$DRY_RUN" == "true" ]] || [[ "$CHECK_ONLY" == "true" ]]; then
        echo "$msg"
    fi
}

# --- Load config ---
if [[ -f "$CONF" ]]; then
    # shellcheck source=/dev/null
    source "$CONF"
fi

if [[ "$ENABLED" != "true" ]]; then
    log "nudge is disabled. Exiting."
    exit 0
fi

# --- PID lock (skip for check-only) ---
if [[ "$CHECK_ONLY" != "true" ]]; then
    if [[ -f "$LOCK" ]]; then
        OLD_PID=$(cat "$LOCK" 2>/dev/null || true)
        if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
            log "Another instance is running (PID $OLD_PID). Exiting."
            exit 0
        fi
        rm -f "$LOCK"
    fi
    echo $$ > "$LOCK"
    trap 'rm -f "$LOCK"' EXIT
fi

# --- Delay (skip for dry-run and check-only) ---
if [[ "$DRY_RUN" != "true" ]] && [[ "$CHECK_ONLY" != "true" ]]; then
    log "Waiting ${DELAY}s before checking for updates."
    sleep "$DELAY"
fi

# --- Network check ---
check_network() {
    ping -c 1 -W "$NETWORK_TIMEOUT" "$NETWORK_HOST" &>/dev/null
}

RETRIES=0
while ! check_network; do
    RETRIES=$((RETRIES + 1))
    if [[ "$RETRIES" -gt "$NETWORK_RETRIES" ]]; then
        log "Network check failed after $NETWORK_RETRIES retries. Exiting."
        exit 0
    fi
    log "Network check failed. Retry $RETRIES/$NETWORK_RETRIES in 15s."
    if [[ "$DRY_RUN" != "true" ]] && [[ "$CHECK_ONLY" != "true" ]]; then
        sleep 15
    fi
done

log "Network check passed."

# --- apt lock check ---
if fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1; then
    log "APT lock held by another process. Exiting."
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

log "Updates available: $UPDATES (security: $SECURITY)"

# --- Exit if up to date ---
if [[ "$UPDATES" -eq 0 ]]; then
    log "System is up to date."
    exit 0
fi

# --- Check-only mode ---
if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "$UPDATES updates available ($SECURITY security)"
    exit 0
fi

# --- Detect notification backend ---
detect_backend() {
    if command -v kdialog &>/dev/null; then
        echo "kdialog"
    elif command -v zenity &>/dev/null; then
        echo "zenity"
    elif command -v notify-send &>/dev/null; then
        echo "notify-send"
    else
        echo "none"
    fi
}

BACKEND="$NOTIFICATION_BACKEND"
if [[ "$BACKEND" == "auto" ]]; then
    BACKEND=$(detect_backend)
fi

log "Using notification backend: $BACKEND"

# --- Build dialog message ---
MSG="There are $UPDATES package update(s) available."
if [[ "$CHECK_SECURITY" == "true" ]] && [[ "$SECURITY" -gt 0 ]]; then
    MSG="$MSG\n$SECURITY of these are security updates."
fi
MSG="$MSG\n\nWould you like to update now?"

# --- Dry run exits here ---
if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry run — would show $BACKEND dialog."
    echo "Backend: $BACKEND"
    echo "Message: $(echo -e "$MSG")"
    exit 0
fi

# --- Detect terminal emulator ---
detect_terminal() {
    if command -v konsole &>/dev/null; then
        echo "konsole"
    elif command -v gnome-terminal &>/dev/null; then
        echo "gnome-terminal"
    elif command -v xfce4-terminal &>/dev/null; then
        echo "xfce4-terminal"
    elif command -v x-terminal-emulator &>/dev/null; then
        echo "x-terminal-emulator"
    else
        echo "xterm"
    fi
}

# --- Run update in terminal ---
run_update() {
    local term
    term=$(detect_terminal)
    case "$term" in
        konsole)
            konsole --hold -e bash -c "$UPDATE_COMMAND"
            ;;
        gnome-terminal)
            gnome-terminal -- bash -c "$UPDATE_COMMAND; echo; echo 'Press Enter to close.'; read -r"
            ;;
        xfce4-terminal)
            xfce4-terminal --hold -e bash -c "$UPDATE_COMMAND"
            ;;
        *)
            $term -e bash -c "$UPDATE_COMMAND; echo; echo 'Press Enter to close.'; read -r"
            ;;
    esac
}

# --- Show prompt ---
RESPONSE=false
case "$BACKEND" in
    kdialog)
        DIALOG_ARGS=(--icon system-software-update --title "System Updates Available" --yesno "$MSG")
        if [[ "$AUTO_DISMISS" -gt 0 ]]; then
            if kdialog "${DIALOG_ARGS[@]}" 2>/dev/null & then
                DIALOG_PID=$!
                sleep "$AUTO_DISMISS" 2>/dev/null || true
                if kill -0 "$DIALOG_PID" 2>/dev/null; then
                    kill "$DIALOG_PID" 2>/dev/null || true
                    log "Dialog auto-dismissed after ${AUTO_DISMISS}s."
                else
                    if wait "$DIALOG_PID"; then
                        RESPONSE=true
                    fi
                fi
            fi
        else
            if kdialog "${DIALOG_ARGS[@]}" 2>/dev/null; then
                RESPONSE=true
            fi
        fi
        ;;
    zenity)
        if zenity --question --icon-name=system-software-update \
                  --title="System Updates Available" \
                  --text="$(echo -e "$MSG")" \
                  --timeout="$( [[ "$AUTO_DISMISS" -gt 0 ]] && echo "$AUTO_DISMISS" || echo "0" )" \
                  2>/dev/null; then
            RESPONSE=true
        fi
        ;;
    notify-send)
        notify-send -i system-software-update "System Updates Available" \
            "$UPDATES update(s) available. Run: nudge.sh --check-only" 2>/dev/null || true
        log "Sent desktop notification (notify-send does not support interactive prompts)."
        exit 0
        ;;
    none)
        log "No notification backend available. Exiting."
        exit 0
        ;;
esac

if [[ "$RESPONSE" == "true" ]]; then
    log "User accepted update. Running: $UPDATE_COMMAND"
    run_update
else
    log "User declined update."
fi

exit 0
