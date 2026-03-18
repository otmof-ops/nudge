#!/usr/bin/env bash
# nudge installer — interactive settings wizard
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.
# Version: 1.1.0

set -euo pipefail

VERSION="1.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Defaults ---
USE_DEFAULTS=false
UNATTENDED=false
USE_COLOR=true
PREFIX="${HOME}"

# --- Config defaults ---
CFG_ENABLED=true
CFG_DELAY=45
CFG_CHECK_SECURITY=true
CFG_AUTO_DISMISS=0
CFG_UPDATE_COMMAND="sudo apt update && sudo apt full-upgrade"
CFG_NETWORK_HOST="archive.ubuntu.com"
CFG_NETWORK_TIMEOUT=5
CFG_NETWORK_RETRIES=2
CFG_NOTIFICATION_BACKEND="auto"
CFG_LOG_FILE=""

# --- Parse flags ---
for arg in "$@"; do
    case "$arg" in
        --defaults)
            USE_DEFAULTS=true
            ;;
        --unattended)
            UNATTENDED=true
            USE_DEFAULTS=true
            ;;
        --no-color)
            USE_COLOR=false
            ;;
        --prefix=*)
            PREFIX="${arg#--prefix=}"
            ;;
        --version)
            echo "nudge installer $VERSION"
            exit 0
            ;;
        --help|-h)
            echo "nudge installer $VERSION"
            echo ""
            echo "Usage: install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --defaults     Skip prompts, use default settings"
            echo "  --unattended   Non-interactive install (implies --defaults)"
            echo "  --no-color     Disable colored output"
            echo "  --prefix=PATH  Install prefix (default: \$HOME)"
            echo "  --version      Print version and exit"
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
    RED='\033[0;31m'
    RESET='\033[0m'
else
    BOLD=''
    GREEN=''
    YELLOW=''
    CYAN=''
    RED=''
    RESET=''
fi

info()    { echo -e "${GREEN}[✓]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
error()   { echo -e "${RED}[✗]${RESET} $1"; }
header()  { echo -e "${BOLD}${CYAN}$1${RESET}"; }
setting() { echo -e "    ${CYAN}$1${RESET} = ${BOLD}$2${RESET}"; }

# --- Header ---
echo ""
header "=== nudge installer v${VERSION} ==="
echo "A gentle nudge to keep your system fresh."
echo ""

# --- Dependency detection ---
header "Detecting dependencies..."

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
        echo "none"
    fi
}

detect_de() {
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        echo "$XDG_CURRENT_DESKTOP"
    elif [[ -n "${DESKTOP_SESSION:-}" ]]; then
        echo "$DESKTOP_SESSION"
    else
        echo "unknown"
    fi
}

DETECTED_BACKEND=$(detect_backend)
DETECTED_TERMINAL=$(detect_terminal)
DETECTED_DE=$(detect_de)

info "Desktop environment: ${BOLD}${DETECTED_DE}${RESET}"
info "Notification backend: ${BOLD}${DETECTED_BACKEND}${RESET}"
info "Terminal emulator: ${BOLD}${DETECTED_TERMINAL}${RESET}"

if [[ "$DETECTED_BACKEND" == "none" ]]; then
    error "No supported notification backend found."
    echo "  Install one of: kdialog, zenity, or libnotify-bin (notify-send)"
    echo "  Example: sudo apt install kdialog"
    exit 1
fi

if [[ "$DETECTED_TERMINAL" == "none" ]]; then
    warn "No supported terminal emulator found."
    echo "  Updates will not be able to open a terminal window."
    echo "  Install one of: konsole, gnome-terminal, xfce4-terminal"
fi

echo ""

# --- Interactive config walkthrough ---
prompt_value() {
    local prompt="$1"
    local default="$2"
    local result

    echo -ne "  ${prompt} ${CYAN}[${default}]${RESET}: "
    read -r result
    echo "${result:-$default}"
}

prompt_yesno() {
    local prompt="$1"
    local default="$2"
    local result

    if [[ "$default" == "true" ]]; then
        echo -ne "  ${prompt} ${CYAN}[Y/n]${RESET}: "
    else
        echo -ne "  ${prompt} ${CYAN}[y/N]${RESET}: "
    fi
    read -r result

    if [[ -z "$result" ]]; then
        echo "$default"
        return
    fi

    case "${result,,}" in
        y|yes) echo "true" ;;
        n|no) echo "false" ;;
        *) echo "$default" ;;
    esac
}

if [[ "$USE_DEFAULTS" != "true" ]]; then
    header "Configure nudge settings"
    echo "Press Enter to accept the default value shown in brackets."
    echo ""

    CFG_DELAY=$(prompt_value "Post-login delay (seconds)" "$CFG_DELAY")

    CFG_CHECK_SECURITY=$(prompt_yesno "Highlight security updates separately?" "$CFG_CHECK_SECURITY")

    CFG_AUTO_DISMISS=$(prompt_value "Auto-dismiss dialog after N seconds (0 = never)" "$CFG_AUTO_DISMISS")

    echo ""
    echo -e "  Detected backend: ${BOLD}${DETECTED_BACKEND}${RESET}"
    CFG_NOTIFICATION_BACKEND=$(prompt_value "Notification backend (kdialog/zenity/notify-send/auto)" "auto")

    CFG_NETWORK_HOST=$(prompt_value "Network check host" "$CFG_NETWORK_HOST")

    echo ""
    WANT_LOG=$(prompt_yesno "Enable logging?" "false")
    if [[ "$WANT_LOG" == "true" ]]; then
        CFG_LOG_FILE=$(prompt_value "Log file path" "${PREFIX}/.local/share/nudge/nudge.log")
    fi

    # --- Summary ---
    echo ""
    header "Configuration summary:"
    setting "ENABLED" "$CFG_ENABLED"
    setting "DELAY" "$CFG_DELAY"
    setting "CHECK_SECURITY" "$CFG_CHECK_SECURITY"
    setting "AUTO_DISMISS" "$CFG_AUTO_DISMISS"
    setting "UPDATE_COMMAND" "$CFG_UPDATE_COMMAND"
    setting "NETWORK_HOST" "$CFG_NETWORK_HOST"
    setting "NETWORK_TIMEOUT" "$CFG_NETWORK_TIMEOUT"
    setting "NETWORK_RETRIES" "$CFG_NETWORK_RETRIES"
    setting "NOTIFICATION_BACKEND" "$CFG_NOTIFICATION_BACKEND"
    setting "LOG_FILE" "${CFG_LOG_FILE:-<none>}"
    echo ""

    if [[ "$UNATTENDED" != "true" ]]; then
        CONFIRM=$(prompt_yesno "Proceed with installation?" "true")
        if [[ "$CONFIRM" != "true" ]]; then
            echo "Installation cancelled."
            exit 0
        fi
    fi
else
    info "Using default settings (--defaults)."
fi

echo ""
header "Installing nudge..."

# --- Create directories ---
mkdir -p "${PREFIX}/.local/bin"
mkdir -p "${PREFIX}/.config/autostart"

if [[ -n "$CFG_LOG_FILE" ]]; then
    mkdir -p "$(dirname "$CFG_LOG_FILE")"
fi

# --- Backup existing config ---
if [[ -f "${PREFIX}/.config/nudge.conf" ]]; then
    BACKUP="${PREFIX}/.config/nudge.conf.bak.$(date +%Y%m%d%H%M%S)"
    cp "${PREFIX}/.config/nudge.conf" "$BACKUP"
    warn "Existing config backed up to: $BACKUP"
fi

# --- Write config file ---
cat > "${PREFIX}/.config/nudge.conf" << CONF
# nudge — configuration
# A gentle nudge to keep your system fresh.
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.
# Generated by installer v${VERSION} on $(date '+%Y-%m-%d %H:%M:%S')

# Enable or disable nudge (true/false)
ENABLED=${CFG_ENABLED}

# Delay in seconds after login before checking for updates
DELAY=${CFG_DELAY}

# Highlight security updates separately (true/false)
CHECK_SECURITY=${CFG_CHECK_SECURITY}

# Auto-dismiss dialog after N seconds (0 = never dismiss)
AUTO_DISMISS=${CFG_AUTO_DISMISS}

# Command to run for system update
UPDATE_COMMAND="${CFG_UPDATE_COMMAND}"

# Host to ping for network connectivity check
NETWORK_HOST="${CFG_NETWORK_HOST}"

# Network ping timeout in seconds
NETWORK_TIMEOUT=${CFG_NETWORK_TIMEOUT}

# Number of network check retries before giving up
NETWORK_RETRIES=${CFG_NETWORK_RETRIES}

# Notification backend: kdialog, zenity, notify-send, or auto
NOTIFICATION_BACKEND="${CFG_NOTIFICATION_BACKEND}"

# Log file path (empty = no logging)
LOG_FILE="${CFG_LOG_FILE}"
CONF
info "Written: ~/.config/nudge.conf"

# --- Install nudge.sh ---
cp "${SCRIPT_DIR}/nudge.sh" "${PREFIX}/.local/bin/nudge.sh"
chmod +x "${PREFIX}/.local/bin/nudge.sh"
info "Installed: ~/.local/bin/nudge.sh"

# --- Install desktop entry ---
sed "s|HOME_PLACEHOLDER|${PREFIX}|g" "${SCRIPT_DIR}/nudge.desktop" \
    > "${PREFIX}/.config/autostart/nudge.desktop"
info "Installed: ~/.config/autostart/nudge.desktop"

# --- Version stamp ---
echo "$VERSION" > "${PREFIX}/.config/nudge.version"

# --- Success ---
echo ""
header "nudge installed successfully!"
echo ""
echo "  It will run automatically on your next login."
echo "  Notification backend: ${BOLD}${DETECTED_BACKEND}${RESET}"
echo ""
echo "  Test now:"
echo "    ${CYAN}~/.local/bin/nudge.sh --dry-run${RESET}    (test without dialogs)"
echo "    ${CYAN}~/.local/bin/nudge.sh --check-only${RESET} (just print update count)"
echo "    ${CYAN}~/.local/bin/nudge.sh --version${RESET}    (print version)"
echo ""
