#!/usr/bin/env bash
# nudge installer — interactive settings wizard
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.
# Version: 2.0.0

set -euo pipefail

VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Defaults ---
USE_DEFAULTS=false
UNATTENDED=false
USE_COLOR=true
PREFIX="${HOME}"
UPGRADE_MODE=false
CONFIG_ONLY=false
AUTOSTART_METHOD="auto"
INSTALL_COMPLETION=true
INSTALL_MAN=true

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
CFG_SCHEDULE_MODE="login"
CFG_SCHEDULE_INTERVAL_HOURS=24
CFG_HISTORY_ENABLED=true
CFG_HISTORY_MAX_LINES=500
CFG_FLATPAK_ENABLED="auto"
CFG_SNAP_ENABLED="auto"
CFG_PREVIEW_UPDATES=true
CFG_SECURITY_PRIORITY=true
CFG_REBOOT_CHECK=true
CFG_SNAPSHOT_ENABLED=false
CFG_SNAPSHOT_TOOL="auto"
CFG_SELF_UPDATE_CHECK=true
CFG_SELF_UPDATE_CHANNEL="stable"
CFG_OFFLINE_MODE="skip"
CFG_DEFERRAL_OPTIONS="1h,4h,1d"
CFG_PKGMGR_OVERRIDE=""
CFG_DUNST_APPNAME="nudge"
CFG_EXIT_ON_HELD=true
CFG_JSON_OUTPUT=false
CFG_LOG_LEVEL="info"

# --- Parse flags ---
for arg in "$@"; do
    case "$arg" in
        --defaults)      USE_DEFAULTS=true ;;
        --unattended)    UNATTENDED=true; USE_DEFAULTS=true ;;
        --no-color)      USE_COLOR=false ;;
        --upgrade)       UPGRADE_MODE=true ;;
        --config-only)   CONFIG_ONLY=true ;;
        --systemd)       AUTOSTART_METHOD="systemd" ;;
        --xdg)           AUTOSTART_METHOD="xdg" ;;
        --no-completion) INSTALL_COMPLETION=false ;;
        --no-man)        INSTALL_MAN=false ;;
        --prefix=*)      PREFIX="${arg#--prefix=}" ;;
        --version)
            echo "nudge installer $VERSION"
            exit 0
            ;;
        --help|-h)
            cat <<'HELP'
nudge installer 2.0.0

Usage: install.sh [OPTIONS]

Options:
  --defaults       Skip prompts, use default settings
  --unattended     Non-interactive install (implies --defaults)
  --upgrade        In-place upgrade, preserve config, run migration
  --config-only    Re-run wizard without reinstalling scripts
  --systemd        Use systemd user timer for autostart
  --xdg            Use XDG autostart entry
  --no-completion  Skip bash completion install
  --no-man         Skip man page install
  --no-color       Disable colored output
  --prefix=PATH    Install prefix (default: $HOME)
  --version        Print version and exit
  --help, -h       Show this help
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
    RED='\033[0;31m'
    RESET='\033[0m'
else
    BOLD='' GREEN='' YELLOW='' CYAN='' RED='' RESET=''
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

# --- Check for existing install ---
EXISTING_VERSION=""
if [[ -f "${PREFIX}/.config/nudge.version" ]]; then
    EXISTING_VERSION=$(cat "${PREFIX}/.config/nudge.version" 2>/dev/null || true)
fi

if [[ -n "$EXISTING_VERSION" ]] && [[ "$UPGRADE_MODE" != "true" ]] && [[ "$CONFIG_ONLY" != "true" ]]; then
    if [[ "$UNATTENDED" != "true" ]]; then
        echo "nudge v${EXISTING_VERSION} is already installed."
        echo ""
        echo "  [1] Upgrade to v${VERSION}"
        echo "  [2] Reinstall v${VERSION}"
        echo "  [3] Cancel"
        echo ""
        echo -ne "  Choose ${CYAN}[1]${RESET}: "
        read -r CHOICE
        case "${CHOICE:-1}" in
            1) UPGRADE_MODE=true ;;
            2) UPGRADE_MODE=false ;;
            *) echo "Installation cancelled."; exit 0 ;;
        esac
        echo ""
    else
        UPGRADE_MODE=true
    fi
fi

# --- Dependency detection ---
header "Detecting dependencies..."

detect_backend() {
    if command -v dunstify &>/dev/null; then echo "dunstify"
    elif command -v kdialog &>/dev/null; then echo "kdialog"
    elif command -v zenity &>/dev/null; then echo "zenity"
    elif command -v gdbus &>/dev/null; then echo "gdbus"
    elif command -v notify-send &>/dev/null; then echo "notify-send"
    else echo "none"
    fi
}

detect_terminal() {
    if command -v konsole &>/dev/null; then echo "konsole"
    elif command -v gnome-terminal &>/dev/null; then echo "gnome-terminal"
    elif command -v xfce4-terminal &>/dev/null; then echo "xfce4-terminal"
    elif command -v x-terminal-emulator &>/dev/null; then echo "x-terminal-emulator"
    else echo "none"
    fi
}

detect_de() {
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then echo "$XDG_CURRENT_DESKTOP"
    elif [[ -n "${DESKTOP_SESSION:-}" ]]; then echo "$DESKTOP_SESSION"
    else echo "unknown"
    fi
}

detect_pkgmgr() {
    if command -v apt &>/dev/null && [[ -d /var/lib/dpkg ]]; then echo "apt"
    elif command -v dnf &>/dev/null; then echo "dnf"
    elif command -v pacman &>/dev/null; then echo "pacman"
    elif command -v zypper &>/dev/null; then echo "zypper"
    else echo "unknown"
    fi
}

DETECTED_BACKEND=$(detect_backend)
DETECTED_TERMINAL=$(detect_terminal)
DETECTED_DE=$(detect_de)
DETECTED_PKG=$(detect_pkgmgr)

info "Desktop environment: ${BOLD}${DETECTED_DE}${RESET}"
info "Notification backend: ${BOLD}${DETECTED_BACKEND}${RESET}"
info "Terminal emulator: ${BOLD}${DETECTED_TERMINAL}${RESET}"
info "Package manager: ${BOLD}${DETECTED_PKG}${RESET}"

# Detect flatpak/snap
HAVE_FLATPAK=false
HAVE_SNAP=false
if command -v flatpak &>/dev/null; then
    HAVE_FLATPAK=true
    info "Flatpak: ${BOLD}detected${RESET}"
fi
if command -v snap &>/dev/null; then
    HAVE_SNAP=true
    info "Snap: ${BOLD}detected${RESET}"
fi

# Detect snapshot tools
HAVE_TIMESHIFT=false
HAVE_SNAPPER=false
command -v timeshift &>/dev/null && HAVE_TIMESHIFT=true
command -v snapper &>/dev/null && HAVE_SNAPPER=true

if [[ "$DETECTED_BACKEND" == "none" ]]; then
    error "No supported notification backend found."
    echo "  Install one of: kdialog, zenity, dunst, or libnotify-bin"
    exit 1
fi

if [[ "$DETECTED_TERMINAL" == "none" ]]; then
    warn "No supported terminal emulator found."
fi

echo ""

# --- Set default update command based on package manager ---
case "$DETECTED_PKG" in
    apt)    CFG_UPDATE_COMMAND="sudo apt update && sudo apt full-upgrade" ;;
    dnf)    CFG_UPDATE_COMMAND="sudo dnf upgrade -y" ;;
    pacman) CFG_UPDATE_COMMAND="sudo pacman -Syu --noconfirm" ;;
    zypper) CFG_UPDATE_COMMAND="sudo zypper update -y" ;;
esac

# --- Load existing config for upgrade ---
if [[ "$UPGRADE_MODE" == "true" ]]; then
    # Source existing values if available
    OLD_CONF="${PREFIX}/.config/nudge/nudge.conf"
    [[ ! -f "$OLD_CONF" ]] && OLD_CONF="${PREFIX}/.config/nudge.conf"
    if [[ -f "$OLD_CONF" ]]; then
        info "Loading existing configuration from: $OLD_CONF"
        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"
            [[ -z "$line" ]] && continue
            [[ "$line" == \#* ]] && continue
            if [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
                key="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"
                value="${value//\"/}"
                value="${value//\'/}"
                declare "CFG_$key=$value" 2>/dev/null || true
            fi
        done < "$OLD_CONF"
    fi
fi

# --- Interactive prompts ---
prompt_value() {
    local prompt="$1" default="$2" result
    echo -ne "  ${prompt} ${CYAN}[${default}]${RESET}: "
    read -r result
    echo "${result:-$default}"
}

prompt_yesno() {
    local prompt="$1" default="$2" result
    if [[ "$default" == "true" ]]; then
        echo -ne "  ${prompt} ${CYAN}[Y/n]${RESET}: "
    else
        echo -ne "  ${prompt} ${CYAN}[y/N]${RESET}: "
    fi
    read -r result
    [[ -z "$result" ]] && echo "$default" && return
    case "${result,,}" in
        y|yes) echo "true" ;;
        n|no)  echo "false" ;;
        *)     echo "$default" ;;
    esac
}

prompt_choice() {
    local prompt="$1" default="$2"
    shift 2
    local options=("$@")
    echo -e "  ${prompt}"
    local i=1
    for opt in "${options[@]}"; do
        local marker=""
        [[ "$opt" == "$default" ]] && marker=" (default)"
        echo -e "    ${CYAN}[$i]${RESET} ${opt}${marker}"
        i=$((i + 1))
    done
    echo -ne "  Choice ${CYAN}[1]${RESET}: "
    read -r result
    local idx=$((${result:-1} - 1))
    if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "${#options[@]}" ]]; then
        echo "${options[$idx]}"
    else
        echo "$default"
    fi
}

if [[ "$USE_DEFAULTS" != "true" ]] && [[ "$CONFIG_ONLY" != "true" || "$USE_DEFAULTS" != "true" ]]; then
    header "Configure nudge settings"
    echo "Press Enter to accept the default value shown in brackets."
    echo ""

    # Core settings
    header "  — Core —"
    CFG_DELAY=$(prompt_value "Post-login delay (seconds)" "$CFG_DELAY")
    CFG_CHECK_SECURITY=$(prompt_yesno "Highlight security updates separately?" "$CFG_CHECK_SECURITY")
    CFG_AUTO_DISMISS=$(prompt_value "Auto-dismiss dialog after N seconds (0 = never)" "$CFG_AUTO_DISMISS")
    echo ""

    # Notification
    header "  — Notification —"
    echo -e "  Detected backend: ${BOLD}${DETECTED_BACKEND}${RESET}"
    CFG_NOTIFICATION_BACKEND=$(prompt_value "Notification backend (auto/kdialog/zenity/dunstify/notify-send)" "auto")
    CFG_PREVIEW_UPDATES=$(prompt_yesno "Show package list before prompting?" "$CFG_PREVIEW_UPDATES")
    echo ""

    # Network
    header "  — Network —"
    CFG_NETWORK_HOST=$(prompt_value "Network check host" "$CFG_NETWORK_HOST")
    CFG_OFFLINE_MODE=$(prompt_choice "Behavior when offline:" "$CFG_OFFLINE_MODE" "skip" "notify" "queue")
    echo ""

    # Schedule
    header "  — Schedule —"
    CFG_SCHEDULE_MODE=$(prompt_choice "Check frequency:" "$CFG_SCHEDULE_MODE" "login" "daily" "weekly")
    if [[ "$CFG_SCHEDULE_MODE" != "login" ]]; then
        CFG_SCHEDULE_INTERVAL_HOURS=$(prompt_value "Hours between checks" "$CFG_SCHEDULE_INTERVAL_HOURS")
    fi
    CFG_DEFERRAL_OPTIONS=$(prompt_value "Deferral choices (comma-separated)" "$CFG_DEFERRAL_OPTIONS")
    echo ""

    # Package managers
    header "  — Package Managers —"
    if [[ "$HAVE_FLATPAK" == "true" ]]; then
        CFG_FLATPAK_ENABLED=$(prompt_choice "Flatpak updates:" "$CFG_FLATPAK_ENABLED" "auto" "true" "false")
    fi
    if [[ "$HAVE_SNAP" == "true" ]]; then
        CFG_SNAP_ENABLED=$(prompt_choice "Snap updates:" "$CFG_SNAP_ENABLED" "auto" "true" "false")
    fi
    echo ""

    # Safety
    header "  — Safety —"
    CFG_REBOOT_CHECK=$(prompt_yesno "Detect if reboot needed after upgrade?" "$CFG_REBOOT_CHECK")
    if [[ "$HAVE_TIMESHIFT" == "true" ]] || [[ "$HAVE_SNAPPER" == "true" ]]; then
        CFG_SNAPSHOT_ENABLED=$(prompt_yesno "Take snapshot before upgrade?" "$CFG_SNAPSHOT_ENABLED")
    fi
    echo ""

    # Self-update
    header "  — Self-Update —"
    CFG_SELF_UPDATE_CHECK=$(prompt_yesno "Check for nudge updates?" "$CFG_SELF_UPDATE_CHECK")
    echo ""

    # Logging
    header "  — Logging —"
    WANT_LOG=$(prompt_yesno "Enable file logging?" "false")
    if [[ "$WANT_LOG" == "true" ]]; then
        CFG_LOG_FILE=$(prompt_value "Log file path" "${PREFIX}/.local/share/nudge/nudge.log")
    fi
    echo ""

    # Autostart method
    if [[ "$AUTOSTART_METHOD" == "auto" ]]; then
        header "  — Autostart Method —"
        AUTOSTART_METHOD=$(prompt_choice "Autostart method:" "xdg" "xdg" "systemd")
    fi

    # --- Summary ---
    echo ""
    header "Configuration summary:"
    setting "ENABLED" "$CFG_ENABLED"
    setting "DELAY" "$CFG_DELAY"
    setting "CHECK_SECURITY" "$CFG_CHECK_SECURITY"
    setting "AUTO_DISMISS" "$CFG_AUTO_DISMISS"
    setting "UPDATE_COMMAND" "$CFG_UPDATE_COMMAND"
    setting "SCHEDULE_MODE" "$CFG_SCHEDULE_MODE"
    setting "NOTIFICATION_BACKEND" "$CFG_NOTIFICATION_BACKEND"
    setting "FLATPAK_ENABLED" "$CFG_FLATPAK_ENABLED"
    setting "SNAP_ENABLED" "$CFG_SNAP_ENABLED"
    setting "REBOOT_CHECK" "$CFG_REBOOT_CHECK"
    setting "SNAPSHOT_ENABLED" "$CFG_SNAPSHOT_ENABLED"
    setting "SELF_UPDATE_CHECK" "$CFG_SELF_UPDATE_CHECK"
    setting "AUTOSTART" "$AUTOSTART_METHOD"
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
    info "Using default settings."
    [[ "$AUTOSTART_METHOD" == "auto" ]] && AUTOSTART_METHOD="xdg"
fi

echo ""
header "Installing nudge v${VERSION}..."

# --- Create directories ---
mkdir -p "${PREFIX}/.local/bin"
mkdir -p "${PREFIX}/.local/lib/nudge"
mkdir -p "${PREFIX}/.config/nudge"
mkdir -p "${PREFIX}/.local/share/nudge"
mkdir -p "${PREFIX}/.config/autostart"

if [[ -n "$CFG_LOG_FILE" ]]; then
    mkdir -p "$(dirname "$CFG_LOG_FILE")"
fi

# --- Backup existing config ---
OLD_CONFIG="${PREFIX}/.config/nudge/nudge.conf"
[[ ! -f "$OLD_CONFIG" ]] && OLD_CONFIG="${PREFIX}/.config/nudge.conf"

if [[ -f "$OLD_CONFIG" ]]; then
    BACKUP="${OLD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$OLD_CONFIG" "$BACKUP"
    warn "Existing config backed up to: $BACKUP"
fi

# --- Write config file ---
CONFIG_FILE="${PREFIX}/.config/nudge/nudge.conf"
cat > "$CONFIG_FILE" << CONF
# nudge — configuration
# A gentle nudge to keep your system fresh.
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.
# Generated by installer v${VERSION} on $(date '+%Y-%m-%d %H:%M:%S')

# Config format version (do not edit)
CONF_VERSION="${VERSION}"

# --- Core Settings ---
ENABLED=${CFG_ENABLED}
DELAY=${CFG_DELAY}
CHECK_SECURITY=${CFG_CHECK_SECURITY}
AUTO_DISMISS=${CFG_AUTO_DISMISS}
UPDATE_COMMAND="${CFG_UPDATE_COMMAND}"

# --- Network Settings ---
NETWORK_HOST="${CFG_NETWORK_HOST}"
NETWORK_TIMEOUT=${CFG_NETWORK_TIMEOUT}
NETWORK_RETRIES=${CFG_NETWORK_RETRIES}
OFFLINE_MODE="${CFG_OFFLINE_MODE}"

# --- Notification Settings ---
NOTIFICATION_BACKEND="${CFG_NOTIFICATION_BACKEND}"
DUNST_APPNAME="${CFG_DUNST_APPNAME}"
PREVIEW_UPDATES=${CFG_PREVIEW_UPDATES}
SECURITY_PRIORITY=${CFG_SECURITY_PRIORITY}

# --- Schedule Settings ---
SCHEDULE_MODE="${CFG_SCHEDULE_MODE}"
SCHEDULE_INTERVAL_HOURS=${CFG_SCHEDULE_INTERVAL_HOURS}
DEFERRAL_OPTIONS="${CFG_DEFERRAL_OPTIONS}"

# --- Package Manager Settings ---
PKGMGR_OVERRIDE="${CFG_PKGMGR_OVERRIDE}"
FLATPAK_ENABLED="${CFG_FLATPAK_ENABLED}"
SNAP_ENABLED="${CFG_SNAP_ENABLED}"
EXIT_ON_HELD=${CFG_EXIT_ON_HELD}

# --- History & Logging ---
HISTORY_ENABLED=${CFG_HISTORY_ENABLED}
HISTORY_MAX_LINES=${CFG_HISTORY_MAX_LINES}
LOG_FILE="${CFG_LOG_FILE}"
LOG_LEVEL="${CFG_LOG_LEVEL}"
JSON_OUTPUT=${CFG_JSON_OUTPUT}

# --- Safety Settings ---
REBOOT_CHECK=${CFG_REBOOT_CHECK}
SNAPSHOT_ENABLED=${CFG_SNAPSHOT_ENABLED}
SNAPSHOT_TOOL="${CFG_SNAPSHOT_TOOL}"

# --- Self-Update Settings ---
SELF_UPDATE_CHECK=${CFG_SELF_UPDATE_CHECK}
SELF_UPDATE_CHANNEL="${CFG_SELF_UPDATE_CHANNEL}"
CONF
info "Written: ~/.config/nudge/nudge.conf"

# --- Config-only mode stops here ---
if [[ "$CONFIG_ONLY" == "true" ]]; then
    echo ""
    info "Configuration updated. No scripts reinstalled (--config-only)."
    exit 0
fi

# --- Install main script ---
cp "${SCRIPT_DIR}/nudge.sh" "${PREFIX}/.local/bin/nudge.sh"
chmod +x "${PREFIX}/.local/bin/nudge.sh"
info "Installed: ~/.local/bin/nudge.sh"

# --- Install library modules ---
cp "${SCRIPT_DIR}"/lib/*.sh "${PREFIX}/.local/lib/nudge/"
info "Installed: ~/.local/lib/nudge/ (10 modules)"

# --- Install autostart ---
if [[ "$AUTOSTART_METHOD" == "systemd" ]]; then
    # systemd user timer
    mkdir -p "${PREFIX}/.config/systemd/user"

    # Adjust timer interval from config
    timer_interval="${CFG_SCHEDULE_INTERVAL_HOURS}h"
    [[ "$CFG_SCHEDULE_MODE" == "weekly" ]] && timer_interval="$((CFG_SCHEDULE_INTERVAL_HOURS * 7))h"

    sed "s|OnUnitActiveSec=24h|OnUnitActiveSec=${timer_interval}|g" \
        "${SCRIPT_DIR}/nudge.timer" > "${PREFIX}/.config/systemd/user/nudge.timer"
    sed "s|%h|${PREFIX}|g" \
        "${SCRIPT_DIR}/nudge.service" > "${PREFIX}/.config/systemd/user/nudge.service"

    # Enable timer if systemctl is available
    if command -v systemctl &>/dev/null; then
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable nudge.timer 2>/dev/null || true
        systemctl --user start nudge.timer 2>/dev/null || true
    fi

    # Remove XDG autostart if switching from it
    rm -f "${PREFIX}/.config/autostart/nudge.desktop" 2>/dev/null || true

    info "Installed: systemd user timer"
else
    # XDG autostart
    sed "s|HOME_PLACEHOLDER|${PREFIX}|g" "${SCRIPT_DIR}/nudge.desktop" \
        > "${PREFIX}/.config/autostart/nudge.desktop"

    # Remove systemd units if switching
    if command -v systemctl &>/dev/null; then
        systemctl --user disable nudge.timer 2>/dev/null || true
        systemctl --user stop nudge.timer 2>/dev/null || true
    fi
    rm -f "${PREFIX}/.config/systemd/user/nudge.timer" 2>/dev/null || true
    rm -f "${PREFIX}/.config/systemd/user/nudge.service" 2>/dev/null || true

    info "Installed: ~/.config/autostart/nudge.desktop"
fi

# --- Install bash completion ---
if [[ "$INSTALL_COMPLETION" == "true" ]] && [[ -f "${SCRIPT_DIR}/nudge-completion.bash" ]]; then
    COMP_DIR="${PREFIX}/.local/share/bash-completion/completions"
    mkdir -p "$COMP_DIR"
    cp "${SCRIPT_DIR}/nudge-completion.bash" "${COMP_DIR}/nudge"
    info "Installed: bash completion"
fi

# --- Install man page ---
if [[ "$INSTALL_MAN" == "true" ]] && [[ -f "${SCRIPT_DIR}/nudge.1" ]]; then
    MAN_DIR="${PREFIX}/.local/share/man/man1"
    mkdir -p "$MAN_DIR"
    cp "${SCRIPT_DIR}/nudge.1" "${MAN_DIR}/nudge.1"
    # Update mandb if available
    mandb -q 2>/dev/null || true
    info "Installed: man page"
fi

# --- Version stamp ---
echo "$VERSION" > "${PREFIX}/.config/nudge.version"

# --- Post-install verification ---
if [[ "$UNATTENDED" != "true" ]]; then
    echo ""
    header "Verifying installation..."
    if "${PREFIX}/.local/bin/nudge.sh" --version &>/dev/null; then
        info "Verification passed (nudge --version works)"
    else
        warn "Verification: nudge.sh --version returned non-zero"
    fi
fi

# --- Success ---
echo ""
header "nudge v${VERSION} installed successfully!"
echo ""
echo "  Autostart: ${BOLD}${AUTOSTART_METHOD}${RESET}"
echo "  Backend:   ${BOLD}${DETECTED_BACKEND}${RESET}"
echo "  Package:   ${BOLD}${DETECTED_PKG}${RESET}"
echo ""
echo "  Test now:"
echo "    ${CYAN}nudge.sh --dry-run${RESET}       (test without dialogs)"
echo "    ${CYAN}nudge.sh --check-only${RESET}    (just print update count)"
echo "    ${CYAN}nudge.sh --config${RESET}        (show resolved config)"
echo "    ${CYAN}nudge.sh --validate${RESET}      (validate config)"
echo "    ${CYAN}nudge.sh --history${RESET}       (view update history)"
echo "    ${CYAN}nudge.sh --version${RESET}       (print version)"
if [[ "$INSTALL_MAN" == "true" ]]; then
    echo "    ${CYAN}man nudge${RESET}               (read manual)"
fi
echo ""
