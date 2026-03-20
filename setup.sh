#!/usr/bin/env bash
# nudge — unified setup
# Install, uninstall, configure, update, and status — all in one place.
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.
# Version: 2.0.0

# shellcheck disable=SC2034  # NUDGE_VERSION is read by selfupdate.sh
set -euo pipefail

VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Bootstrap: piped execution fallback ---
if [[ ! -d "$SCRIPT_DIR/lib" ]]; then
    _SETUP_TMPDIR=$(mktemp -d)
    trap 'rm -rf "$_SETUP_TMPDIR"' EXIT
    echo "Downloading nudge..."
    if command -v git &>/dev/null; then
        git clone --depth 1 https://github.com/otmof-ops/nudge.git "$_SETUP_TMPDIR/nudge" 2>/dev/null
    elif command -v curl &>/dev/null; then
        curl -sL https://github.com/otmof-ops/nudge/archive/refs/heads/main.tar.gz | tar xz -C "$_SETUP_TMPDIR"
        mv "$_SETUP_TMPDIR"/nudge-* "$_SETUP_TMPDIR/nudge"
    else
        echo "Error: git or curl required for remote install" >&2
        exit 4
    fi
    exec bash "$_SETUP_TMPDIR/nudge/setup.sh" "$@"
fi

# --- Source libraries ---
source "$SCRIPT_DIR/lib/output.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/selfupdate.sh"
source "$SCRIPT_DIR/lib/tui.sh"

# --- Defaults ---
_MODE=""
_USE_DEFAULTS=false
_UNATTENDED=false
_DRY_RUN=false
_KEEP_CONFIG=false
_UPGRADE=false
_UPDATE_CHECK_ONLY=false
_TUI_NO_COLOR=false
_PREFIX="${HOME}"
_AUTOSTART_METHOD="auto"
_IS_REINSTALL=false
_CONFIGURE_RETURN="MAIN_MENU"
_STATE="MAIN_MENU"

# --- Exit codes ---
readonly _EXIT_OK=0
readonly _EXIT_CANCELLED=1
readonly _EXIT_DETECT_FAIL=2
readonly _EXIT_ACTION_FAIL=3
readonly _EXIT_INVALID_ARGS=4

# --- Parse CLI flags ---
for arg in "$@"; do
    case "$arg" in
        --install)       _MODE="install" ;;
        --uninstall)     _MODE="uninstall" ;;
        --update)        _MODE="update" ;;
        --config-only)   _MODE="config-only" ;;
        --defaults)      _USE_DEFAULTS=true ;;
        --unattended)    _UNATTENDED=true; _USE_DEFAULTS=true ;;
        --dry-run)       _DRY_RUN=true ;;
        --keep-config)   _KEEP_CONFIG=true ;;
        --upgrade)       _UPGRADE=true ;;
        --check)         _UPDATE_CHECK_ONLY=true ;;
        --no-color)      _TUI_NO_COLOR=true ;;
        --systemd)       _AUTOSTART_METHOD="systemd" ;;
        --xdg)           _AUTOSTART_METHOD="xdg" ;;
        --prefix=*)      _PREFIX="${arg#--prefix=}" ;;
        --yes|-y)        _UNATTENDED=true ;;
        --version)
            echo "nudge setup $VERSION"
            exit 0
            ;;
        --help|-h)
            cat <<'HELPTEXT'
 (\__/)
 (='.'=)  nudge setup 2.0.0
 (")_(")  unified installer, updater, and configurator

Usage: setup.sh [OPTIONS]

  No flags          Launch interactive TUI
  --install         Install nudge
  --uninstall       Uninstall nudge
  --update          Check and install updates
  --config-only     Open configure flow only

Install options:
  --defaults        Use smart defaults, skip prompts
  --unattended      Non-interactive (implies --defaults)
  --upgrade         Preserve existing config
  --systemd         Use systemd user timer
  --xdg             Use XDG autostart
  --prefix=PATH     Custom install prefix (default: $HOME)

Uninstall options:
  --yes, -y         Skip confirmation
  --keep-config     Preserve config directory

Update options:
  --check           Just check, print version, exit

General:
  --dry-run         Show what would happen, change nothing
  --no-color        Disable ANSI colors
  --version         Print version and exit
  --help, -h        Show this help
HELPTEXT
            exit 0
            ;;
        *)
            echo "Unknown flag: $arg" >&2
            echo "Run setup.sh --help for usage." >&2
            exit "$_EXIT_INVALID_ARGS"
            ;;
    esac
done

# --- Initialize TUI ---
_tui_init

# --- Detection functions ---
_detect_backend() {
    if command -v dunstify &>/dev/null; then echo "dunstify"
    elif command -v kdialog &>/dev/null; then echo "kdialog"
    elif command -v zenity &>/dev/null; then echo "zenity"
    elif command -v gdbus &>/dev/null; then echo "gdbus"
    elif command -v notify-send &>/dev/null; then echo "notify-send"
    else echo "none"
    fi
}

_detect_terminal() {
    if command -v konsole &>/dev/null; then echo "konsole"
    elif command -v gnome-terminal &>/dev/null; then echo "gnome-terminal"
    elif command -v xfce4-terminal &>/dev/null; then echo "xfce4-terminal"
    elif command -v x-terminal-emulator &>/dev/null; then echo "x-terminal-emulator"
    else echo "none"
    fi
}

_detect_de() {
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then echo "$XDG_CURRENT_DESKTOP"
    elif [[ -n "${DESKTOP_SESSION:-}" ]]; then echo "$DESKTOP_SESSION"
    else echo "unknown"
    fi
}

_detect_pkgmgr() {
    if command -v apt &>/dev/null && [[ -d /var/lib/dpkg ]]; then echo "apt"
    elif command -v dnf &>/dev/null; then echo "dnf"
    elif command -v pacman &>/dev/null; then echo "pacman"
    elif command -v zypper &>/dev/null; then echo "zypper"
    else echo "unknown"
    fi
}

_detect_all() {
    _DETECTED_BACKEND=$(_detect_backend)
    _DETECTED_TERMINAL=$(_detect_terminal)
    _DETECTED_DE=$(_detect_de)
    _DETECTED_PKG=$(_detect_pkgmgr)
    _HAVE_FLATPAK=false
    _HAVE_SNAP=false
    _HAVE_TIMESHIFT=false
    _HAVE_SNAPPER=false
    command -v flatpak &>/dev/null && _HAVE_FLATPAK=true
    command -v snap &>/dev/null && _HAVE_SNAP=true
    command -v timeshift &>/dev/null && _HAVE_TIMESHIFT=true
    command -v snapper &>/dev/null && _HAVE_SNAPPER=true
}

# --- Bunny farewell art ---
_bunny_farewell() {
    local face="${1:-}"
    local msg="${2:-}"
    [[ -z "$face" ]] && face='(T.'"'"'T)'
    if [[ -n "$msg" ]]; then
        printf ' (\\__/)\n %s  %s\n (")_(")ノ\n' "$face" "$msg"
    else
        printf ' (\\__/)\n %s\n (")_(")ノ\n' "$face"
    fi
}

# --- Config defaults ---
_init_config_defaults() {
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
    CFG_JSON_OUTPUT=false
    CFG_LOG_LEVEL="info"
    CFG_BUNNY_PERSONALITY="disney"

    case "${_DETECTED_PKG:-apt}" in
        apt)    CFG_UPDATE_COMMAND="sudo apt update && sudo apt full-upgrade" ;;
        dnf)    CFG_UPDATE_COMMAND="sudo dnf upgrade -y" ;;
        pacman) CFG_UPDATE_COMMAND="sudo pacman -Syu --noconfirm" ;;
        zypper) CFG_UPDATE_COMMAND="sudo zypper update -y" ;;
    esac
}

# --- Config categories ---
declare -A CONFIG_CATEGORIES=(
    [core]="ENABLED DELAY CHECK_SECURITY AUTO_DISMISS UPDATE_COMMAND"
    [notification]="NOTIFICATION_BACKEND DUNST_APPNAME PREVIEW_UPDATES SECURITY_PRIORITY BUNNY_PERSONALITY"
    [network]="NETWORK_HOST NETWORK_TIMEOUT NETWORK_RETRIES OFFLINE_MODE"
    [schedule]="SCHEDULE_MODE SCHEDULE_INTERVAL_HOURS DEFERRAL_OPTIONS"
    [packages]="PKGMGR_OVERRIDE FLATPAK_ENABLED SNAP_ENABLED"
    [safety]="REBOOT_CHECK SNAPSHOT_ENABLED SNAPSHOT_TOOL"
    [updates]="SELF_UPDATE_CHECK SELF_UPDATE_CHANNEL"
    [logging]="HISTORY_ENABLED HISTORY_MAX_LINES LOG_FILE LOG_LEVEL JSON_OUTPUT"
)

_CATEGORY_NAMES=(core notification network schedule packages safety updates logging)
_CATEGORY_LABELS=("Core settings" "Notifications" "Network" "Schedule" "Package managers" "Safety" "Updates & auto-update" "Logging")

# --- Load existing config ---
_load_existing_config() {
    local conf="${_PREFIX}/.config/nudge/nudge.conf"
    [[ ! -f "$conf" ]] && conf="${_PREFIX}/.config/nudge.conf"
    if [[ -f "$conf" ]]; then
        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"
            [[ -z "$line" ]] && continue
            [[ "$line" == \#* ]] && continue
            if [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                value="${value//\"/}"
                value="${value//\'/}"
                printf -v "CFG_$key" '%s' "$value" 2>/dev/null || true
            fi
        done < "$conf"
        return 0
    fi
    return 1
}

# --- Edit a single config key ---
_edit_config_key() {
    local key="$1"
    local current_var="CFG_${key}"
    local current="${!current_var:-${CONFIG_DEFAULTS[$key]:-}}"
    local type="${CONFIG_TYPES[$key]:-string}"

    case "$type" in
        bool)
            if [[ "$current" == "true" ]]; then
                printf -v "$current_var" '%s' "false"
                _tui_info "$key = false"
            else
                printf -v "$current_var" '%s' "true"
                _tui_info "$key = true"
            fi
            ;;
        enum:*)
            local valid="${type#enum:}"
            IFS=',' read -ra opts <<< "$valid"
            local result
            result=$(_tui_choice "$key:" "$current" "${opts[@]}")
            printf -v "$current_var" '%s' "$result"
            _tui_info "$key = $result"
            ;;
        int)
            local result
            result=$(_tui_input "$key" "$current")
            if [[ "$result" =~ ^[0-9]+$ ]]; then
                printf -v "$current_var" '%s' "$result"
                _tui_info "$key = $result"
            else
                _tui_warn "Invalid integer, keeping $current"
            fi
            ;;
        string)
            local result
            result=$(_tui_input "$key" "$current")
            printf -v "$current_var" '%s' "$result"
            _tui_info "$key = $result"
            ;;
    esac
}

# --- Action functions ---

_action_create_dirs() {
    local dirs=(
        "${_PREFIX}/.local/bin"
        "${_PREFIX}/.local/lib/nudge"
        "${_PREFIX}/.config/nudge"
        "${_PREFIX}/.local/share/nudge"
        "${_PREFIX}/.config/autostart"
    )
    for d in "${dirs[@]}"; do
        if [[ "$_DRY_RUN" == "true" ]]; then
            _tui_info "[dry-run] mkdir -p $d"
        else
            mkdir -p "$d"
        fi
    done
    if [[ -n "$CFG_LOG_FILE" ]] && [[ "$CFG_LOG_FILE" != "" ]]; then
        if [[ "$_DRY_RUN" == "true" ]]; then
            _tui_info "[dry-run] mkdir -p $(dirname "$CFG_LOG_FILE")"
        else
            mkdir -p "$(dirname "$CFG_LOG_FILE")"
        fi
    fi
}

_action_backup_config() {
    local old_config="${_PREFIX}/.config/nudge/nudge.conf"
    [[ ! -f "$old_config" ]] && old_config="${_PREFIX}/.config/nudge.conf"
    if [[ -f "$old_config" ]]; then
        local backup
        backup="${old_config}.bak.$(date +%Y%m%d%H%M%S)"
        if [[ "$_DRY_RUN" == "true" ]]; then
            _tui_info "[dry-run] backup $old_config → $backup"
        else
            cp "$old_config" "$backup"
            _tui_warn "Config backed up to: $backup"
        fi
    fi
}

_action_write_config() {
    local config_file="${_PREFIX}/.config/nudge/nudge.conf"
    if [[ "$_DRY_RUN" == "true" ]]; then
        _tui_info "[dry-run] write config → $config_file"
        return
    fi
    local generated_date
    generated_date=$(date '+%Y-%m-%d %H:%M:%S')
    {
        printf '# nudge — configuration\n'
        printf '# A gentle nudge to keep your system fresh.\n'
        printf '# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.\n'
        printf '# Generated by setup.sh v%s on %s\n\n' "$VERSION" "$generated_date"
        printf '# Config format version (do not edit)\n'
        printf 'CONF_VERSION="%s"\n\n' "$VERSION"
        printf '# --- Core Settings ---\n'
        printf 'ENABLED=%s\n' "$CFG_ENABLED"
        printf 'DELAY=%s\n' "$CFG_DELAY"
        printf 'CHECK_SECURITY=%s\n' "$CFG_CHECK_SECURITY"
        printf 'AUTO_DISMISS=%s\n' "$CFG_AUTO_DISMISS"
        printf 'UPDATE_COMMAND="%s"\n\n' "$CFG_UPDATE_COMMAND"
        printf '# --- Network Settings ---\n'
        printf 'NETWORK_HOST="%s"\n' "$CFG_NETWORK_HOST"
        printf 'NETWORK_TIMEOUT=%s\n' "$CFG_NETWORK_TIMEOUT"
        printf 'NETWORK_RETRIES=%s\n' "$CFG_NETWORK_RETRIES"
        printf 'OFFLINE_MODE="%s"\n\n' "$CFG_OFFLINE_MODE"
        printf '# --- Notification Settings ---\n'
        printf 'NOTIFICATION_BACKEND="%s"\n' "$CFG_NOTIFICATION_BACKEND"
        printf 'DUNST_APPNAME="%s"\n' "$CFG_DUNST_APPNAME"
        printf 'PREVIEW_UPDATES=%s\n' "$CFG_PREVIEW_UPDATES"
        printf 'SECURITY_PRIORITY=%s\n\n' "$CFG_SECURITY_PRIORITY"
        printf '# --- Schedule Settings ---\n'
        printf 'SCHEDULE_MODE="%s"\n' "$CFG_SCHEDULE_MODE"
        printf 'SCHEDULE_INTERVAL_HOURS=%s\n' "$CFG_SCHEDULE_INTERVAL_HOURS"
        printf 'DEFERRAL_OPTIONS="%s"\n\n' "$CFG_DEFERRAL_OPTIONS"
        printf '# --- Package Manager Settings ---\n'
        printf 'PKGMGR_OVERRIDE="%s"\n' "$CFG_PKGMGR_OVERRIDE"
        printf 'FLATPAK_ENABLED="%s"\n' "$CFG_FLATPAK_ENABLED"
        printf 'SNAP_ENABLED="%s"\n\n' "$CFG_SNAP_ENABLED"
        printf '# --- History & Logging ---\n'
        printf 'HISTORY_ENABLED=%s\n' "$CFG_HISTORY_ENABLED"
        printf 'HISTORY_MAX_LINES=%s\n' "$CFG_HISTORY_MAX_LINES"
        printf 'LOG_FILE="%s"\n' "$CFG_LOG_FILE"
        printf 'LOG_LEVEL="%s"\n' "$CFG_LOG_LEVEL"
        printf 'JSON_OUTPUT=%s\n\n' "$CFG_JSON_OUTPUT"
        printf '# --- Safety Settings ---\n'
        printf 'REBOOT_CHECK=%s\n' "$CFG_REBOOT_CHECK"
        printf 'SNAPSHOT_ENABLED=%s\n' "$CFG_SNAPSHOT_ENABLED"
        printf 'SNAPSHOT_TOOL="%s"\n\n' "$CFG_SNAPSHOT_TOOL"
        printf '# --- Self-Update Settings ---\n'
        printf 'SELF_UPDATE_CHECK=%s\n' "$CFG_SELF_UPDATE_CHECK"
        printf 'SELF_UPDATE_CHANNEL="%s"\n\n' "$CFG_SELF_UPDATE_CHANNEL"
        printf '# --- Personality Settings ---\n'
        printf 'BUNNY_PERSONALITY="%s"\n' "$CFG_BUNNY_PERSONALITY"
    } > "$config_file"
    _tui_info "Written: ~/.config/nudge/nudge.conf"
}

_action_install_scripts() {
    if [[ "$_DRY_RUN" == "true" ]]; then
        _tui_info "[dry-run] copy nudge.sh → ~/.local/bin/nudge.sh"
        _tui_info "[dry-run] copy lib/*.sh → ~/.local/lib/nudge/"
        _tui_info "[dry-run] copy setup.sh → ~/.local/bin/nudge-setup.sh"
        return
    fi
    cp "${SCRIPT_DIR}/nudge.sh" "${_PREFIX}/.local/bin/nudge.sh"
    chmod +x "${_PREFIX}/.local/bin/nudge.sh"
    _tui_info "Installed: ~/.local/bin/nudge.sh"

    cp "${SCRIPT_DIR}"/lib/*.sh "${_PREFIX}/.local/lib/nudge/"
    chmod 0644 "${_PREFIX}/.local/lib/nudge/"*.sh
    local mod_count
    mod_count=$(find "${_PREFIX}/.local/lib/nudge/" -name '*.sh' | wc -l)
    _tui_info "Installed: ~/.local/lib/nudge/ — ${mod_count} modules"

    cp "${SCRIPT_DIR}/setup.sh" "${_PREFIX}/.local/bin/nudge-setup.sh"
    chmod +x "${_PREFIX}/.local/bin/nudge-setup.sh"
    _tui_info "Installed: ~/.local/bin/nudge-setup.sh"
}

_action_install_autostart() {
    local method="${_AUTOSTART_METHOD}"
    [[ "$method" == "auto" ]] && method="xdg"

    if [[ "$method" == "systemd" ]]; then
        if [[ "$_DRY_RUN" == "true" ]]; then
            _tui_info "[dry-run] install systemd user timer"
            return
        fi
        mkdir -p "${_PREFIX}/.config/systemd/user"
        local timer_interval="${CFG_SCHEDULE_INTERVAL_HOURS}h"
        [[ "$CFG_SCHEDULE_MODE" == "weekly" ]] && timer_interval="$((CFG_SCHEDULE_INTERVAL_HOURS * 7))h"
        sed "s|OnUnitActiveSec=24h|OnUnitActiveSec=${timer_interval}|g" \
            "${SCRIPT_DIR}/share/systemd/nudge.timer" > "${_PREFIX}/.config/systemd/user/nudge.timer"
        sed "s|%h|${_PREFIX}|g" \
            "${SCRIPT_DIR}/share/systemd/nudge.service" > "${_PREFIX}/.config/systemd/user/nudge.service"
        if command -v systemctl &>/dev/null; then
            systemctl --user daemon-reload 2>/dev/null || true
            systemctl --user enable nudge.timer 2>/dev/null || true
            systemctl --user start nudge.timer 2>/dev/null || true
        fi
        rm -f "${_PREFIX}/.config/autostart/nudge.desktop" 2>/dev/null || true
        _tui_info "Installed: systemd user timer"
    else
        if [[ "$_DRY_RUN" == "true" ]]; then
            _tui_info "[dry-run] install XDG autostart entry"
            return
        fi
        sed "s|HOME_PLACEHOLDER|${_PREFIX}|g" "${SCRIPT_DIR}/nudge.desktop" \
            > "${_PREFIX}/.config/autostart/nudge.desktop"
        if command -v systemctl &>/dev/null; then
            systemctl --user disable nudge.timer 2>/dev/null || true
            systemctl --user stop nudge.timer 2>/dev/null || true
        fi
        rm -f "${_PREFIX}/.config/systemd/user/nudge.timer" 2>/dev/null || true
        rm -f "${_PREFIX}/.config/systemd/user/nudge.service" 2>/dev/null || true
        _tui_info "Installed: ~/.config/autostart/nudge.desktop"
    fi
}

_action_install_completion() {
    if [[ -f "${SCRIPT_DIR}/share/bash-completion/nudge" ]]; then
        local comp_dir="${_PREFIX}/.local/share/bash-completion/completions"
        if [[ "$_DRY_RUN" == "true" ]]; then
            _tui_info "[dry-run] install bash completion"
            return
        fi
        mkdir -p "$comp_dir"
        cp "${SCRIPT_DIR}/share/bash-completion/nudge" "${comp_dir}/nudge"
        _tui_info "Installed: bash completion"
    fi
}

_action_install_man() {
    if [[ -f "${SCRIPT_DIR}/share/man/nudge.1" ]]; then
        local man_dir="${_PREFIX}/.local/share/man/man1"
        if [[ "$_DRY_RUN" == "true" ]]; then
            _tui_info "[dry-run] install man page"
            return
        fi
        mkdir -p "$man_dir"
        cp "${SCRIPT_DIR}/share/man/nudge.1" "${man_dir}/nudge.1"
        mandb -q 2>/dev/null || true
        _tui_info "Installed: man page"
    fi
}

_action_stamp_version() {
    if [[ "$_DRY_RUN" == "true" ]]; then
        _tui_info "[dry-run] stamp version $VERSION"
        return
    fi
    echo "$VERSION" > "${_PREFIX}/.config/nudge.version"
    _tui_info "Version: $VERSION"
}

_action_verify() {
    if [[ "$_DRY_RUN" == "true" ]]; then
        _tui_info "[dry-run] verify nudge.sh --version"
        return
    fi
    if "${_PREFIX}/.local/bin/nudge.sh" --version &>/dev/null; then
        _tui_info "Verification passed"
    else
        _tui_warn "Verification: nudge.sh --version returned non-zero"
    fi
}

_is_nudge_source_dir() {
    local dir="$1"
    [[ -d "$dir" ]] \
        && [[ -f "$dir/nudge.sh" ]] \
        && [[ -d "$dir/lib" ]] \
        && [[ -f "$dir/setup.sh" ]]
}

_action_uninstall() {
    # Disable systemd timer
    if command -v systemctl &>/dev/null; then
        if systemctl --user is-enabled nudge.timer &>/dev/null; then
            if [[ "$_DRY_RUN" != "true" ]]; then
                systemctl --user stop nudge.timer 2>/dev/null || true
                systemctl --user disable nudge.timer 2>/dev/null || true
            else
                _tui_info "[dry-run] disable systemd timer"
            fi
        fi
    fi

    local files_to_remove=()
    local dirs_to_remove=()

    [[ -f "${_PREFIX}/.local/bin/nudge.sh" ]] && files_to_remove+=("${_PREFIX}/.local/bin/nudge.sh")
    [[ -f "${_PREFIX}/.local/bin/nudge-setup.sh" ]] && files_to_remove+=("${_PREFIX}/.local/bin/nudge-setup.sh")
    [[ -d "${_PREFIX}/.local/lib/nudge" ]] && dirs_to_remove+=("${_PREFIX}/.local/lib/nudge")
    [[ -f "${_PREFIX}/.config/autostart/nudge.desktop" ]] && files_to_remove+=("${_PREFIX}/.config/autostart/nudge.desktop")
    [[ -f "${_PREFIX}/.config/systemd/user/nudge.timer" ]] && files_to_remove+=("${_PREFIX}/.config/systemd/user/nudge.timer")
    [[ -f "${_PREFIX}/.config/systemd/user/nudge.service" ]] && files_to_remove+=("${_PREFIX}/.config/systemd/user/nudge.service")
    [[ -f "${_PREFIX}/.config/nudge.version" ]] && files_to_remove+=("${_PREFIX}/.config/nudge.version")
    [[ -f "${_PREFIX}/.local/share/bash-completion/completions/nudge" ]] && files_to_remove+=("${_PREFIX}/.local/share/bash-completion/completions/nudge")
    [[ -f "${_PREFIX}/.local/share/man/man1/nudge.1" ]] && files_to_remove+=("${_PREFIX}/.local/share/man/man1/nudge.1")

    local lock="${XDG_RUNTIME_DIR:-/tmp}/nudge-${UID}.lock"
    [[ -f "$lock" ]] && files_to_remove+=("$lock")

    [[ -d "${_PREFIX}/.local/share/nudge" ]] && dirs_to_remove+=("${_PREFIX}/.local/share/nudge")

    if [[ "$_KEEP_CONFIG" != "true" ]]; then
        [[ -d "${_PREFIX}/.config/nudge" ]] && dirs_to_remove+=("${_PREFIX}/.config/nudge")
        [[ -f "${_PREFIX}/.config/nudge.conf" ]] && files_to_remove+=("${_PREFIX}/.config/nudge.conf")
    fi

    if [[ $(( ${#files_to_remove[@]} + ${#dirs_to_remove[@]} )) -eq 0 ]]; then
        _tui_info "No nudge files found — nothing to remove."
        return 0
    fi

    for f in "${files_to_remove[@]}"; do
        if [[ "$_DRY_RUN" == "true" ]]; then
            _tui_info "[dry-run] remove: $f"
        else
            rm -f "$f"
            _tui_info "Removed: $f"
        fi
    done
    for d in "${dirs_to_remove[@]}"; do
        if [[ "$_DRY_RUN" == "true" ]]; then
            _tui_info "[dry-run] remove: $d/"
        else
            rm -rf "$d"
            _tui_info "Removed: $d/"
        fi
    done

    if command -v systemctl &>/dev/null && [[ "$_DRY_RUN" != "true" ]]; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi
}

_action_update() {
    selfupdate_install
}

# ========================================================
# TUI Screens
# ========================================================

_screen_main_menu() {
    _tui_bunny "hey! i'm nudge." "what would you like to do?"
    _tui_menu "Install nudge" "Configure settings" "Check status" "Update nudge" "Uninstall" "Exit"
    case "${_MENU_CHOICE}" in
        1) _STATE="INSTALL_DETECT" ;;
        2) _STATE="CONFIGURE" ;;
        3) _STATE="STATUS" ;;
        4) _STATE="UPDATE_CHECK" ;;
        5) _STATE="UNINSTALL" ;;
        *) _STATE="EXIT" ;;
    esac
}

_screen_install_detect() {
    _detect_all
    _init_config_defaults

    _tui_bunny "detecting your system..." ""
    _tui_info "Desktop: ${_DETECTED_DE}"
    _tui_info "Notification: ${_DETECTED_BACKEND}"
    _tui_info "Terminal: ${_DETECTED_TERMINAL}"
    _tui_info "Package manager: ${_DETECTED_PKG}"
    [[ "$_HAVE_FLATPAK" == "true" ]] && _tui_info "Flatpak: detected"
    [[ "$_HAVE_SNAP" == "true" ]] && _tui_info "Snap: detected"

    if [[ "$_DETECTED_BACKEND" == "none" ]]; then
        _tui_error "No notification backend found."
        _tui_info "Install one of: kdialog, zenity, dunst, or libnotify-bin"
        _tui_wait
        _STATE="MAIN_MENU"
        return
    fi

    local existing_version=""
    if [[ -f "${_PREFIX}/.config/nudge.version" ]]; then
        existing_version=$(cat "${_PREFIX}/.config/nudge.version" 2>/dev/null || true)
    fi
    if [[ -n "$existing_version" ]]; then
        _tui_warn "nudge v${existing_version} is already installed."
    fi

    if [[ -z "$existing_version" ]] && [[ -f "${_PREFIX}/.config/nudge/nudge.conf" ]]; then
        _IS_REINSTALL=true
        _load_existing_config || true
    fi

    if [[ "$_IS_REINSTALL" == "true" ]] && [[ "${CFG_BUNNY_PERSONALITY:-disney}" != "classic" ]]; then
        _tui_info "YOU CAME BACK!! i knew you would!! i missed you so much!!"
    fi

    echo ""
    _tui_menu "Install now (smart defaults)" "Customize first" "Back"
    case "${_MENU_CHOICE}" in
        1)
            if [[ -n "$existing_version" ]]; then
                _UPGRADE=true
                _load_existing_config || true
            fi
            _STATE="INSTALL_EXEC"
            ;;
        2)
            if [[ -n "$existing_version" ]]; then
                _UPGRADE=true
                _load_existing_config || true
            fi
            _CONFIGURE_RETURN="INSTALL_EXEC"
            _STATE="CONFIGURE"
            ;;
        *) _STATE="MAIN_MENU" ;;
    esac
}

_screen_install_exec() {
    _tui_bunny "installing nudge v${VERSION}..." ""

    _action_create_dirs
    _action_backup_config
    _action_write_config
    _action_install_scripts
    _action_install_autostart
    _action_install_completion
    _action_install_man
    _action_stamp_version
    _action_verify

    _STATE="INSTALL_DONE"
}

_screen_install_done() {
    local personality="${CFG_BUNNY_PERSONALITY:-disney}"
    echo ""
    if [[ "${_IS_REINSTALL:-false}" == "true" ]] && [[ "$personality" != "classic" ]]; then
        _tui_info "i promise i'll take even better care of you this time!!"
    else
        _tui_info "all done! nudge is installed."
        _tui_info "run nudge.sh --dry-run to test."
    fi
    _tui_setting "Version" "$VERSION"
    _tui_setting "Autostart" "${_AUTOSTART_METHOD}"
    _tui_setting "Backend" "${_DETECTED_BACKEND}"
    _tui_setting "Package mgr" "${_DETECTED_PKG}"
    _tui_wait
    _STATE="MAIN_MENU"
}

_screen_uninstall() {
    local personality="${CFG_BUNNY_PERSONALITY:-disney}"

    local files=""
    [[ -f "${_PREFIX}/.local/bin/nudge.sh" ]] && files+=$'\n'"  ~/.local/bin/nudge.sh"
    [[ -f "${_PREFIX}/.local/bin/nudge-setup.sh" ]] && files+=$'\n'"  ~/.local/bin/nudge-setup.sh"
    [[ -d "${_PREFIX}/.local/lib/nudge" ]] && files+=$'\n'"  ~/.local/lib/nudge/"
    [[ -f "${_PREFIX}/.config/autostart/nudge.desktop" ]] && files+=$'\n'"  ~/.config/autostart/nudge.desktop"
    [[ -d "${_PREFIX}/.local/share/nudge" ]] && files+=$'\n'"  ~/.local/share/nudge/"
    [[ -d "${_PREFIX}/.config/nudge" ]] && files+=$'\n'"  ~/.config/nudge/"

    if [[ "$personality" == "classic" ]]; then
        _tui_bunny "Uninstall nudge" ""
    else
        _tui_bunny "you... you're removing me?" ""
    fi

    echo " Files to remove:${files}"
    echo ""

    _tui_menu "Uninstall now" "Uninstall (keep config)" "Back"
    case "${_MENU_CHOICE}" in
        1) _KEEP_CONFIG=false; _STATE="UNINSTALL_EXEC" ;;
        2) _KEEP_CONFIG=true; _STATE="UNINSTALL_EXEC" ;;
        *) _STATE="MAIN_MENU" ;;
    esac
}

_screen_uninstall_exec() {
    local personality="${CFG_BUNNY_PERSONALITY:-disney}"

    if [[ "$personality" != "classic" ]]; then
        _tui_bunny "but... who will check for the updates?" ""
        sleep 1
        _tui_bunny "i tried my best... i really did" ""
        sleep 1
    fi

    _action_uninstall

    if [[ "$personality" != "classic" ]]; then
        echo ""
        _bunny_farewell "(T.'T)" "okay... bye bye fren. stay safe out there."
        echo ""
        echo " *waves tiny paw*"
    fi

    echo ""
    _tui_info "nudge has been removed."
    _tui_info "Your system will no longer check for updates at login."

    if [[ "$_KEEP_CONFIG" == "true" ]] && [[ -d "${_PREFIX}/.config/nudge" ]]; then
        if [[ "$personality" != "classic" ]]; then
            _tui_info "you kept my config... does that mean you might come back? (:'.'=)"
        else
            _tui_info "Config preserved at: ~/.config/nudge/"
        fi
    fi

    # Offer to delete source directory
    if _is_nudge_source_dir "$SCRIPT_DIR"; then
        echo ""
        _tui_info "Source directory still exists: ${SCRIPT_DIR}/"
        _tui_menu "Delete it too (rm -rf ${SCRIPT_DIR}/)" "Keep it"
        case "${_MENU_CHOICE}" in
            1)
                local confirmed
                confirmed=$(_tui_confirm "This will permanently delete ${SCRIPT_DIR}. Are you sure?" "false")
                if [[ "$confirmed" == "true" ]]; then
                    rm -rf "$SCRIPT_DIR"
                    _tui_info "Deleted: ${SCRIPT_DIR}/"
                    exit 0
                else
                    _tui_info "Source directory kept."
                fi
                ;;
            *)
                _tui_info "Source directory kept."
                ;;
        esac
    fi

    _tui_wait
    _STATE="MAIN_MENU"
}

_screen_configure() {
    local return_state="${_CONFIGURE_RETURN}"
    _CONFIGURE_RETURN="MAIN_MENU"

    _load_existing_config 2>/dev/null || true

    while true; do
        _tui_bunny "configure nudge" "pick a category"
        local items=()
        for i in "${!_CATEGORY_NAMES[@]}"; do
            items+=("${_CATEGORY_LABELS[$i]}")
        done
        items+=("Save & back")
        _tui_menu "${items[@]}"

        if [[ "$_MENU_CHOICE" == "0" ]]; then
            _STATE="$return_state"
            return
        elif [[ "$_MENU_CHOICE" -ge 1 ]] && [[ "$_MENU_CHOICE" -le ${#_CATEGORY_NAMES[@]} ]]; then
            local idx=$((_MENU_CHOICE - 1))
            local category="${_CATEGORY_NAMES[$idx]}"
            local keys_str="${CONFIG_CATEGORIES[$category]:-}"
            # shellcheck disable=SC2206
            local keys=($keys_str)

            local editing=true
            while [[ "$editing" == "true" ]]; do
                _tui_bunny "${_CATEGORY_LABELS[$idx]}" "pick a setting to change"
                local i=1
                for key in "${keys[@]}"; do
                    local var="CFG_${key}"
                    local val="${!var:-${CONFIG_DEFAULTS[$key]:-}}"
                    local type="${CONFIG_TYPES[$key]:-string}"
                    local type_label
                    case "$type" in
                        bool) type_label="bool" ;;
                        int)  type_label="int" ;;
                        enum:*) type_label="${type#enum:}" ;;
                        *)    type_label="text" ;;
                    esac
                    echo -e " ${_TUI_CYAN}${i})${_TUI_RESET} ${key} = ${_TUI_BOLD}${val}${_TUI_RESET}  (${type_label})"
                    i=$((i + 1))
                done
                echo -e " ${_TUI_CYAN}0)${_TUI_RESET} Back"
                echo ""
                read -rp " > " _MENU_CHOICE </dev/tty 2>/dev/null || read -rp " > " _MENU_CHOICE
                _MENU_CHOICE="${_MENU_CHOICE:-0}"

                if [[ "$_MENU_CHOICE" == "0" ]]; then
                    editing=false
                elif [[ "$_MENU_CHOICE" -ge 1 ]] && [[ "$_MENU_CHOICE" -le ${#keys[@]} ]]; then
                    local edit_idx=$((_MENU_CHOICE - 1))
                    _edit_config_key "${keys[$edit_idx]}"
                fi
            done

            # Save if config file exists
            if [[ -f "${_PREFIX}/.config/nudge/nudge.conf" ]] || [[ -f "${_PREFIX}/.config/nudge.conf" ]]; then
                _action_write_config 2>/dev/null || true
            fi
        else
            _STATE="$return_state"
            return
        fi
    done
}

_screen_update() {
    _tui_bunny "checking for updates..." ""

    local latest=""
    local _orig_check="${SELF_UPDATE_CHECK:-true}"
    SELF_UPDATE_CHECK="true"
    NUDGE_VERSION="$VERSION"

    local state_file="${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/selfupdate_last_check"
    rm -f "$state_file" 2>/dev/null || true

    latest=$(selfupdate_check 2>/dev/null) || true
    SELF_UPDATE_CHECK="$_orig_check"

    if [[ -z "$latest" ]]; then
        _tui_bunny "you're up to date!" "running nudge v${VERSION}"
        _tui_info "auto-update: $([ "${CFG_SELF_UPDATE_CHECK:-true}" == "true" ] && echo "on" || echo "off")"
        _tui_info "channel: ${CFG_SELF_UPDATE_CHANNEL:-stable}"
        _tui_info "source: github.com/${SELFUPDATE_REPO}"
        echo ""
        _tui_menu "Toggle auto-update" "Switch channel (stable/beta)" "Back"
        case "${_MENU_CHOICE}" in
            1)
                if [[ "${CFG_SELF_UPDATE_CHECK:-true}" == "true" ]]; then
                    CFG_SELF_UPDATE_CHECK=false
                    _tui_info "Auto-update: OFF"
                else
                    CFG_SELF_UPDATE_CHECK=true
                    _tui_info "Auto-update: ON"
                fi
                _action_write_config 2>/dev/null || true
                _tui_wait
                ;;
            2)
                if [[ "${CFG_SELF_UPDATE_CHANNEL:-stable}" == "stable" ]]; then
                    CFG_SELF_UPDATE_CHANNEL="beta"
                    _tui_info "Channel: beta"
                else
                    CFG_SELF_UPDATE_CHANNEL="stable"
                    _tui_info "Channel: stable"
                fi
                _action_write_config 2>/dev/null || true
                _tui_wait
                ;;
        esac
    else
        _tui_bunny "nudge v${latest} is available!" "you're on v${VERSION}"
        _tui_menu "Update now" "Skip" "Back"
        case "${_MENU_CHOICE}" in
            1)
                _tui_bunny "updating to v${latest}..." ""
                if _action_update; then
                    _tui_info "Updated to v${latest}!"
                    _tui_info "Restart setup.sh to use the new version."
                else
                    _tui_error "Update failed."
                fi
                _tui_wait
                ;;
        esac
    fi
    _STATE="MAIN_MENU"
}

_screen_status() {
    _tui_bunny "system status" ""

    local installed_ver=""
    if [[ -f "${_PREFIX}/.config/nudge.version" ]]; then
        installed_ver=$(cat "${_PREFIX}/.config/nudge.version" 2>/dev/null || true)
    fi

    if [[ -n "$installed_ver" ]]; then
        _tui_info "Installed: nudge v${installed_ver}"
    else
        _tui_warn "nudge is not installed"
    fi

    _tui_info "Setup version: $VERSION"

    if [[ -f "${_PREFIX}/.config/autostart/nudge.desktop" ]]; then
        _tui_info "Autostart: XDG desktop entry"
    elif systemctl --user is-enabled nudge.timer &>/dev/null 2>&1; then
        _tui_info "Autostart: systemd timer (enabled)"
    else
        _tui_warn "Autostart: not configured"
    fi

    if [[ -f "${_PREFIX}/.local/bin/nudge.sh" ]]; then _tui_info "nudge.sh: present"; else _tui_warn "nudge.sh: missing"; fi
    if [[ -d "${_PREFIX}/.local/lib/nudge" ]]; then _tui_info "lib modules: present"; else _tui_warn "lib modules: missing"; fi
    if [[ -f "${_PREFIX}/.config/nudge/nudge.conf" ]]; then _tui_info "Config: present"; else _tui_warn "Config: missing"; fi
    if [[ -f "${_PREFIX}/.local/share/bash-completion/completions/nudge" ]]; then _tui_info "Bash completion: present"; else _tui_warn "Bash completion: missing"; fi
    if [[ -f "${_PREFIX}/.local/share/man/man1/nudge.1" ]]; then _tui_info "Man page: present"; else _tui_warn "Man page: missing"; fi

    if _load_existing_config 2>/dev/null; then
        _tui_header "Config highlights:"
        _tui_setting "ENABLED" "${CFG_ENABLED}"
        _tui_setting "SCHEDULE_MODE" "${CFG_SCHEDULE_MODE}"
        _tui_setting "DELAY" "${CFG_DELAY}s"
        _tui_setting "AUTO_UPDATE" "${CFG_SELF_UPDATE_CHECK}"
        _tui_setting "CHANNEL" "${CFG_SELF_UPDATE_CHANNEL}"
    fi

    _tui_wait
    _STATE="MAIN_MENU"
}

# ========================================================
# CLI dispatch — handle non-interactive flags
# ========================================================

_cli_dispatch() {
    _detect_all
    _init_config_defaults

    case "$_MODE" in
        install)
            if [[ "$_UPGRADE" == "true" ]]; then
                _load_existing_config || true
            fi
            if [[ "$_USE_DEFAULTS" != "true" ]] && [[ "$_UNATTENDED" != "true" ]]; then
                return 1
            fi
            local _cli_reinstall=false
            local existing_ver=""
            [[ -f "${_PREFIX}/.config/nudge.version" ]] && existing_ver=$(cat "${_PREFIX}/.config/nudge.version" 2>/dev/null || true)
            if [[ -z "$existing_ver" ]] && [[ -f "${_PREFIX}/.config/nudge/nudge.conf" ]]; then
                _cli_reinstall=true
                _load_existing_config || true
            fi
            echo ""
            if [[ "$_cli_reinstall" == "true" ]] && [[ "${CFG_BUNNY_PERSONALITY:-disney}" != "classic" ]]; then
                output_banner "YOU CAME BACK!! i knew you would!! i missed you so much!!" "" "(^'.'^)"
            else
                output_banner "installing nudge v${VERSION}..." ""
            fi
            echo ""
            _action_create_dirs
            _action_backup_config
            _action_write_config
            _action_install_scripts
            _action_install_autostart
            _action_install_completion
            _action_install_man
            _action_stamp_version
            if [[ "$_UNATTENDED" != "true" ]]; then
                _action_verify
            fi
            echo ""
            output_banner "all done! nudge is installed." "run nudge.sh --dry-run to test."
            echo ""
            exit "$_EXIT_OK"
            ;;
        uninstall)
            _load_existing_config 2>/dev/null || true
            local personality="${CFG_BUNNY_PERSONALITY:-disney}"

            echo ""
            if [[ "$personality" == "classic" ]]; then
                output_banner "Removing nudge..." ""
            else
                output_banner "you... you're removing me?" "" "(='.'=)"
                echo ""
                output_banner "i tried my best... i really did" "" "(:'.'=)"
            fi
            echo ""

            _action_uninstall

            echo ""
            if [[ "$personality" == "classic" ]]; then
                output_banner "nudge has been removed." ""
            else
                _bunny_farewell "(T.'T)" "*waves tiny paw*"
                echo ""
                echo "  nudge has been removed. Your system will no longer check for updates at login."
            fi

            if [[ "$_KEEP_CONFIG" == "true" ]] && [[ -d "${_PREFIX}/.config/nudge" ]]; then
                if [[ "$personality" != "classic" ]]; then
                    echo ""
                    output_banner "you kept my config... does that mean you might come back?" "" "(:'.'=)"
                else
                    echo ""
                    echo "  Config preserved at: ~/.config/nudge/"
                fi
            fi
            echo ""

            if _is_nudge_source_dir "$SCRIPT_DIR" && [[ -t 0 ]]; then
                echo "  The source directory still exists:"
                echo "    ${SCRIPT_DIR}/"
                echo ""
                local confirmed
                confirmed=$(_tui_confirm "Delete source directory ${SCRIPT_DIR}/?" "false")
                if [[ "$confirmed" == "true" ]]; then
                    confirmed=$(_tui_confirm "This will permanently delete ${SCRIPT_DIR}. Are you sure?" "false")
                    if [[ "$confirmed" == "true" ]]; then
                        rm -rf "$SCRIPT_DIR"
                        echo "  Deleted: ${SCRIPT_DIR}/"
                        exit "$_EXIT_OK"
                    fi
                fi
                echo "  Source directory kept."
            elif _is_nudge_source_dir "$SCRIPT_DIR"; then
                echo "  Note: source directory remains at ${SCRIPT_DIR}/"
            fi
            exit "$_EXIT_OK"
            ;;
        update)
            NUDGE_VERSION="$VERSION"
            if [[ "$_UPDATE_CHECK_ONLY" == "true" ]]; then
                SELF_UPDATE_CHECK="true"
                local state_file="${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/selfupdate_last_check"
                rm -f "$state_file" 2>/dev/null || true
                local latest
                latest=$(selfupdate_check 2>/dev/null) || true
                if [[ -n "$latest" ]]; then
                    echo "nudge v${latest} available (current: v${VERSION})"
                else
                    echo "nudge v${VERSION} is up to date"
                fi
                exit "$_EXIT_OK"
            fi
            _action_update
            exit "$_EXIT_OK"
            ;;
        config-only)
            _load_existing_config || true
            return 1
            ;;
    esac

    return 1
}

# ========================================================
# Main entry point
# ========================================================

main() {
    if [[ -n "$_MODE" ]]; then
        if _cli_dispatch; then
            exit "$_EXIT_OK"
        fi
    fi

    _STATE="MAIN_MENU"

    if [[ "$_MODE" == "config-only" ]]; then
        _detect_all
        _init_config_defaults
        _STATE="CONFIGURE"
    fi

    while [[ "$_STATE" != "EXIT" ]]; do
        case "$_STATE" in
            MAIN_MENU)       _screen_main_menu ;;
            INSTALL_DETECT)  _screen_install_detect ;;
            INSTALL_EXEC)    _screen_install_exec ;;
            INSTALL_DONE)    _screen_install_done ;;
            UNINSTALL)       _screen_uninstall ;;
            UNINSTALL_EXEC)  _screen_uninstall_exec ;;
            CONFIGURE)       _screen_configure ;;
            UPDATE_CHECK)    _screen_update ;;
            STATUS)          _screen_status ;;
            *)               _STATE="EXIT" ;;
        esac
    done

    echo ""
    output_banner "bye! stay fresh." ""
    echo ""
    exit "$_EXIT_OK"
}

main
