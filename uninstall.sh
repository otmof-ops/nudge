#!/usr/bin/env bash
# nudge uninstaller
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

# --- Defaults ---
SKIP_CONFIRM=false
KEEP_CONFIG=false
USE_COLOR=true

# --- Parse flags ---
for arg in "$@"; do
    case "$arg" in
        --yes|-y)
            SKIP_CONFIRM=true
            ;;
        --keep-config)
            KEEP_CONFIG=true
            ;;
        --no-color)
            USE_COLOR=false
            ;;
        --help|-h)
            echo "nudge uninstaller"
            echo ""
            echo "Usage: uninstall.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --yes, -y      Skip confirmation prompts"
            echo "  --keep-config  Preserve configuration file"
            echo "  --no-color     Disable colored output"
            echo "  --help, -h     Show this help"
            exit 0
            ;;
    esac
done

# --- Color helpers ---
if [[ "$USE_COLOR" == "true" ]] && [[ -t 1 ]]; then
    BOLD='\033[1m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    BOLD=''
    GREEN=''
    YELLOW=''
    CYAN=''
    RESET=''
fi

info()    { echo -e "${GREEN}[✓]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
header()  { echo -e "${BOLD}${CYAN}$1${RESET}"; }

echo ""
header "=== nudge uninstaller ==="
echo ""

# --- Show what will be removed ---
header "The following files will be removed:"
FILES_TO_REMOVE=()

check_file() {
    if [[ -f "$1" ]]; then
        echo "  $2"
        FILES_TO_REMOVE+=("$1")
    fi
}

check_file "${HOME}/.local/bin/nudge.sh" "${HOME}/.local/bin/nudge.sh (main script)"
check_file "${HOME}/.config/autostart/nudge.desktop" "${HOME}/.config/autostart/nudge.desktop (autostart entry)"
check_file "${HOME}/.config/nudge.version" "${HOME}/.config/nudge.version (version stamp)"

LOCK="/tmp/nudge-${UID}.lock"
if [[ -f "$LOCK" ]]; then
    echo "  $LOCK (lock file)"
    FILES_TO_REMOVE+=("$LOCK")
fi

# --- Check for log file ---
LOG_FILE=""
if [[ -f "${HOME}/.config/nudge.conf" ]]; then
    LOG_FILE=$(grep -oP '^LOG_FILE="\K[^"]*' "${HOME}/.config/nudge.conf" 2>/dev/null || true)
    if [[ -n "$LOG_FILE" ]] && [[ -f "$LOG_FILE" ]]; then
        echo "  $LOG_FILE (log file)"
        FILES_TO_REMOVE+=("$LOG_FILE")
    fi
fi

# --- Config handling ---
if [[ "$KEEP_CONFIG" != "true" ]] && [[ -f "${HOME}/.config/nudge.conf" ]]; then
    echo "  ${HOME}/.config/nudge.conf (configuration)"
    FILES_TO_REMOVE+=("${HOME}/.config/nudge.conf")
elif [[ -f "${HOME}/.config/nudge.conf" ]]; then
    warn "Config will be preserved (--keep-config)."
fi

if [[ ${#FILES_TO_REMOVE[@]} -eq 0 ]]; then
    echo "  (no nudge files found)"
    echo ""
    echo "Nothing to uninstall."
    exit 0
fi

echo ""

# --- Confirm ---
if [[ "$SKIP_CONFIRM" != "true" ]]; then
    echo -ne "Proceed with uninstall? ${CYAN}[y/N]${RESET}: "
    read -r ANSWER
    if [[ "${ANSWER,,}" != "y" ]]; then
        echo "Uninstall cancelled."
        exit 0
    fi
    echo ""
fi

# --- Remove files ---
for f in "${FILES_TO_REMOVE[@]}"; do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        info "Removed: $f"
    fi
done

# --- Handle config separately if not --keep-config and not --yes ---
if [[ "$KEEP_CONFIG" != "true" ]] && [[ "$SKIP_CONFIRM" != "true" ]]; then
    # Config was already in the list, already removed
    true
elif [[ "$KEEP_CONFIG" != "true" ]] && [[ "$SKIP_CONFIRM" == "true" ]]; then
    # Config was already in the list, already removed
    true
fi

echo ""
info "nudge uninstalled."

if [[ "$KEEP_CONFIG" == "true" ]] && [[ -f "${HOME}/.config/nudge.conf" ]]; then
    echo "  Config preserved at: ~/.config/nudge.conf"
fi
echo ""
