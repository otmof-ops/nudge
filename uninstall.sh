#!/usr/bin/env bash
# shellcheck disable=SC2088  # Tilde in display strings is intentional
# nudge uninstaller
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.
# Version: 2.0.0

set -euo pipefail

# --- Defaults ---
SKIP_CONFIRM=false
KEEP_CONFIG=false
USE_COLOR=true

# --- Parse flags ---
for arg in "$@"; do
    case "$arg" in
        --yes|-y)       SKIP_CONFIRM=true ;;
        --keep-config)  KEEP_CONFIG=true ;;
        --no-color)     USE_COLOR=false ;;
        --help|-h)
            cat <<'HELP'
nudge uninstaller

Usage: uninstall.sh [OPTIONS]

Options:
  --yes, -y      Skip confirmation prompts
  --keep-config  Preserve configuration directory
  --no-color     Disable colored output
  --help, -h     Show this help
HELP
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
    BOLD='' GREEN='' YELLOW='' CYAN='' RESET=''
fi

info()    { echo -e "${GREEN}[✓]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
header()  { echo -e "${BOLD}${CYAN}$1${RESET}"; }

echo ""
header "=== nudge uninstaller ==="
echo ""

# --- Disable systemd timer first ---
if command -v systemctl &>/dev/null; then
    if systemctl --user is-enabled nudge.timer &>/dev/null; then
        echo "  Disabling systemd timer..."
        systemctl --user stop nudge.timer 2>/dev/null || true
        systemctl --user disable nudge.timer 2>/dev/null || true
    fi
fi

# --- Show what will be removed ---
header "The following will be removed:"
FILES_TO_REMOVE=()
DIRS_TO_REMOVE=()

check_file() {
    if [[ -f "$1" ]]; then
        echo "  $2"
        FILES_TO_REMOVE+=("$1")
    fi
}

check_dir() {
    if [[ -d "$1" ]]; then
        echo "  $2"
        DIRS_TO_REMOVE+=("$1")
    fi
}

# Scripts
check_file "${HOME}/.local/bin/nudge.sh" "~/.local/bin/nudge.sh (main script)"

# Library
check_dir "${HOME}/.local/lib/nudge" "~/.local/lib/nudge/ (library modules)"

# Autostart
check_file "${HOME}/.config/autostart/nudge.desktop" "~/.config/autostart/nudge.desktop (XDG autostart)"

# systemd units
check_file "${HOME}/.config/systemd/user/nudge.timer" "~/.config/systemd/user/nudge.timer"
check_file "${HOME}/.config/systemd/user/nudge.service" "~/.config/systemd/user/nudge.service"

# Version stamp
check_file "${HOME}/.config/nudge.version" "~/.config/nudge.version (version stamp)"

# Bash completion
check_file "${HOME}/.local/share/bash-completion/completions/nudge" "bash completion"

# Man page
check_file "${HOME}/.local/share/man/man1/nudge.1" "man page"

# Lock file
LOCK="${XDG_RUNTIME_DIR:-/tmp}/nudge-${UID}.lock"
check_file "$LOCK" "$LOCK (lock file)"

# State/data directory
check_dir "${HOME}/.local/share/nudge" "~/.local/share/nudge/ (history + state)"

# Config handling
if [[ "$KEEP_CONFIG" != "true" ]]; then
    check_dir "${HOME}/.config/nudge" "~/.config/nudge/ (configuration)"
    # Legacy config
    check_file "${HOME}/.config/nudge.conf" "~/.config/nudge.conf (legacy config)"
else
    warn "Config will be preserved (--keep-config)"
fi

TOTAL_ITEMS=$(( ${#FILES_TO_REMOVE[@]} + ${#DIRS_TO_REMOVE[@]} ))
if [[ "$TOTAL_ITEMS" -eq 0 ]]; then
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

# --- Remove directories ---
for d in "${DIRS_TO_REMOVE[@]}"; do
    if [[ -d "$d" ]]; then
        rm -rf "$d"
        info "Removed: $d"
    fi
done

# --- Reload systemd if units were removed ---
if command -v systemctl &>/dev/null; then
    systemctl --user daemon-reload 2>/dev/null || true
fi

echo ""
info "nudge uninstalled."

if [[ "$KEEP_CONFIG" == "true" ]] && [[ -d "${HOME}/.config/nudge" ]]; then
    echo "  Config preserved at: ~/.config/nudge/"
fi
echo ""
