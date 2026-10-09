#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/config.sh
# Configuration loading, validation, and migration

set -euo pipefail

# --- Config paths ---
NUDGE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nudge"
NUDGE_CONFIG_FILE="${NUDGE_CONFIG_DIR}/nudge.conf"
NUDGE_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nudge"
NUDGE_STATE_DIR="$NUDGE_DATA_DIR"

# Legacy config path (v1.x)
NUDGE_LEGACY_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nudge.conf"

# --- The config format this version writes ---
readonly NUDGE_CONF_VERSION="2.1.0"

# --- Default values for all 32 config keys ---
declare -gA CONFIG_DEFAULTS=(
    # v1.x keys
    [ENABLED]="true"
    [DELAY]="45"
    [CHECK_SECURITY]="true"
    [AUTO_DISMISS]="0"
    [UPDATE_COMMAND]="sudo apt update && sudo apt full-upgrade"
    [NETWORK_HOST]="archive.ubuntu.com"
    [NETWORK_TIMEOUT]="5"
    [NETWORK_RETRIES]="2"
    [NOTIFICATION_BACKEND]="auto"
    [LOG_FILE]=""
    # v2.0 keys
    [CONF_VERSION]="2.1.0"
    [SCHEDULE_MODE]="login"
    [SCHEDULE_INTERVAL_HOURS]="24"
    [HISTORY_ENABLED]="true"
    [HISTORY_MAX_LINES]="500"
    [FLATPAK_ENABLED]="auto"
    [SNAP_ENABLED]="auto"
    [PREVIEW_UPDATES]="true"
    [SECURITY_PRIORITY]="true"
    [REBOOT_CHECK]="true"
    [SNAPSHOT_ENABLED]="false"
    [SNAPSHOT_TOOL]="auto"
    [SELF_UPDATE_CHECK]="true"
    [SELF_UPDATE_CHANNEL]="stable"
    [OFFLINE_MODE]="skip"
    [DEFERRAL_OPTIONS]="1h,4h,1d"
    [PKGMGR_OVERRIDE]=""
    [DUNST_APPNAME]="nudge"
    [JSON_OUTPUT]="false"
    [LOG_LEVEL]="info"
    [BUNNY_PERSONALITY]="disney"
    [TERMINAL_EMULATOR]="auto"
    [CRITICAL_PACKAGES_EXTRA]=""
    # v2.1 keys
    [SELECT_UPDATES]="true"
)

# --- Type declarations ---
declare -gA CONFIG_TYPES=(
    [ENABLED]="bool"
    [DELAY]="int"
    [CHECK_SECURITY]="bool"
    [AUTO_DISMISS]="int"
    [UPDATE_COMMAND]="string"
    [NETWORK_HOST]="string"
    [NETWORK_TIMEOUT]="int"
    [NETWORK_RETRIES]="int"
    [NOTIFICATION_BACKEND]="enum:auto,kdialog,zenity,notify-send,dunstify,gdbus,none"
    [LOG_FILE]="string"
    [CONF_VERSION]="string"
    [SCHEDULE_MODE]="enum:login,daily,weekly"
    [SCHEDULE_INTERVAL_HOURS]="int"
    [HISTORY_ENABLED]="bool"
    [HISTORY_MAX_LINES]="int"
    [FLATPAK_ENABLED]="enum:true,false,auto"
    [SNAP_ENABLED]="enum:true,false,auto"
    [PREVIEW_UPDATES]="bool"
    [SECURITY_PRIORITY]="bool"
    [REBOOT_CHECK]="bool"
    [SNAPSHOT_ENABLED]="bool"
    [SNAPSHOT_TOOL]="enum:auto,timeshift,snapper,btrfs"
    [SELF_UPDATE_CHECK]="bool"
    [SELF_UPDATE_CHANNEL]="enum:stable,beta"
    [OFFLINE_MODE]="enum:skip,notify,queue"
    [DEFERRAL_OPTIONS]="string"
    [PKGMGR_OVERRIDE]="string"
    [DUNST_APPNAME]="string"
    [JSON_OUTPUT]="bool"
    [LOG_LEVEL]="enum:debug,info,warn,error"
    [BUNNY_PERSONALITY]="enum:classic,disney"
    [TERMINAL_EMULATOR]="string"
    [CRITICAL_PACKAGES_EXTRA]="string"
    [SELECT_UPDATES]="bool"
)

# --- Validate a single key/value pair ---
config_validate_value() {
    local key="$1" value="$2"
    local type="${CONFIG_TYPES[$key]:-string}"

    case "$type" in
        bool)
            if [[ "$value" != "true" && "$value" != "false" ]]; then
                log_warn "Config: $key='$value' is not a valid bool, using default '${CONFIG_DEFAULTS[$key]}'"
                return 1
            fi
            ;;
        int)
            if ! [[ "$value" =~ ^(0|[1-9][0-9]{0,8})$ ]]; then
                log_warn "Config: $key='$value' is not a valid integer, using default '${CONFIG_DEFAULTS[$key]}'"
                return 1
            fi
            ;;
        enum:*)
            local valid="${type#enum:}"
            local found=false
            IFS=',' read -ra opts <<< "$valid"
            for opt in "${opts[@]}"; do
                if [[ "$value" == "$opt" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" != "true" ]]; then
                log_warn "Config: $key='$value' is not valid (expected: $valid), using default '${CONFIG_DEFAULTS[$key]}'"
                return 1
            fi
            ;;
        string)
            # All strings are valid
            ;;
    esac
    return 0
}

# --- Problems found while loading (key=value lines that were rejected) ---
_CONFIG_PROBLEMS=()

# --- The config file must belong to the user and be writable by nobody else ---
_config_file_trusted() {
    local f="$1" owner mode
    [[ -f "$f" && ! -L "$f" ]] || return 1
    owner=$(stat -c %u "$f" 2>/dev/null) || return 1
    mode=$(stat -c %a "$f" 2>/dev/null) || return 1
    [[ "$owner" == "$UID" ]] || return 1
    # world-writable: refuse (group write is normal under a private user group)
    [[ "${mode: -1}" =~ [2367] ]] && return 1
    return 0
}

# --- Load config with safe line-by-line parser ---
config_load() {
    local config_file="${1:-$NUDGE_CONFIG_FILE}"
    _CONFIG_PROBLEMS=()

    # Set all defaults first
    for key in "${!CONFIG_DEFAULTS[@]}"; do
        printf -v "$key" '%s' "${CONFIG_DEFAULTS[$key]}"
    done

    # If no config file exists, check legacy path
    if [[ ! -f "$config_file" ]]; then
        if [[ -f "$NUDGE_LEGACY_CONFIG" ]]; then
            log_info "Found legacy config at $NUDGE_LEGACY_CONFIG"
            config_file="$NUDGE_LEGACY_CONFIG"
        else
            log_info "No config file found, using defaults"
            return 0
        fi
    fi

    if ! _config_file_trusted "$config_file"; then
        log_error "Config file $config_file is not a regular file owned by you with no group/world write — ignoring it"
        _CONFIG_PROBLEMS+=("config file not trusted: $config_file")
        return 0
    fi

    # Line-by-line parser — no source
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        line="${line%$'\r'}"
        [[ "$line_num" -eq 1 ]] && line="${line#$'\xEF\xBB\xBF'}"

        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue

        # Parse KEY=VALUE, KEY = VALUE, export KEY=VALUE, KEY="VALUE"
        if [[ "$line" =~ ^(export[[:space:]]+)?([A-Z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[2]}"
            local value="${BASH_REMATCH[3]}"

            # Strip surrounding quotes; an unquoted value ends at an inline comment
            if [[ "$value" =~ ^\"(.*)\"[[:space:]]*(#.*)?$ ]]; then
                value="${BASH_REMATCH[1]}"
            elif [[ "$value" =~ ^\'(.*)\'[[:space:]]*(#.*)?$ ]]; then
                value="${BASH_REMATCH[1]}"
            else
                value="${value%%[[:space:]]#*}"
                value="${value%"${value##*[![:space:]]}"}"
            fi

            # Check if this is a known key
            if [[ -n "${CONFIG_DEFAULTS[$key]+x}" ]]; then
                if config_validate_value "$key" "$value"; then
                    printf -v "$key" '%s' "$value"
                else
                    printf -v "$key" '%s' "${CONFIG_DEFAULTS[$key]}"
                    _CONFIG_PROBLEMS+=("line $line_num: $key='$value' rejected, default used")
                fi
            else
                log_warn "Config line $line_num: unknown key '$key' (ignored)"
                _CONFIG_PROBLEMS+=("line $line_num: unknown key $key")
            fi
        else
            log_warn "Config line $line_num: unparseable line (ignored)"
            _CONFIG_PROBLEMS+=("line $line_num: unparseable line")
        fi
    done < "$config_file"

    # Validate NETWORK_HOST — reject suspicious characters
    if [[ -n "${NETWORK_HOST:-}" ]] && [[ ! "$NETWORK_HOST" =~ ^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$ ]]; then
        log_warn "NETWORK_HOST contains invalid characters — resetting to default"
        NETWORK_HOST="${CONFIG_DEFAULTS[NETWORK_HOST]}"
        _CONFIG_PROBLEMS+=("NETWORK_HOST rejected")
    fi

    # Validate TERMINAL_EMULATOR — a bare program name, never a path or a shell word
    if [[ -n "${TERMINAL_EMULATOR:-}" ]] && [[ ! "$TERMINAL_EMULATOR" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_warn "TERMINAL_EMULATOR must be a program name — resetting to auto"
        TERMINAL_EMULATOR="${CONFIG_DEFAULTS[TERMINAL_EMULATOR]}"
    fi

    # Validate CRITICAL_PACKAGES_EXTRA — pipe-separated package names only (it lands in a regex)
    if [[ -n "${CRITICAL_PACKAGES_EXTRA:-}" ]] && [[ ! "$CRITICAL_PACKAGES_EXTRA" =~ ^[a-zA-Z0-9.+_-]+(\|[a-zA-Z0-9.+_-]+)*$ ]]; then
        log_warn "CRITICAL_PACKAGES_EXTRA must be package names separated by | — ignoring it"
        CRITICAL_PACKAGES_EXTRA=""
    fi

    # Validate DEFERRAL_OPTIONS — durations like 1h,4h,1d,1w (spaces after commas are fine)
    DEFERRAL_OPTIONS="${DEFERRAL_OPTIONS//[[:space:]]/}"
    if [[ -n "${DEFERRAL_OPTIONS:-}" ]] && [[ ! "$DEFERRAL_OPTIONS" =~ ^[0-9]+[hdw](,[0-9]+[hdw])*$ ]]; then
        log_warn "DEFERRAL_OPTIONS must be durations like 1h,4h,1d — resetting to default"
        DEFERRAL_OPTIONS="${CONFIG_DEFAULTS[DEFERRAL_OPTIONS]}"
    fi

    # Validate LOG_FILE — a regular file (or absent) under a directory we can name
    if [[ -n "${LOG_FILE:-}" ]]; then
        if [[ "$LOG_FILE" != /* ]]; then
            log_warn "LOG_FILE must be an absolute path — logging disabled"
            LOG_FILE=""
        elif [[ -e "$LOG_FILE" ]] && [[ ! -f "$LOG_FILE" || -L "$LOG_FILE" ]]; then
            log_warn "LOG_FILE is not a regular file — logging disabled"
            LOG_FILE=""
        fi
    fi

    # Validate UPDATE_COMMAND against the grammar (no shell syntax, known tools only)
    if [[ -n "${UPDATE_COMMAND:-}" ]] && ! config_parse_update_command "$UPDATE_COMMAND" >/dev/null; then
        log_error "UPDATE_COMMAND rejected: ${_UPDATE_COMMAND_ERROR:-not a plain package-manager command}. Reset to default."
        UPDATE_COMMAND="${CONFIG_DEFAULTS[UPDATE_COMMAND]}"
        _CONFIG_PROBLEMS+=("UPDATE_COMMAND rejected: ${_UPDATE_COMMAND_ERROR:-invalid}")
    fi

    return 0
}

# --- Validate entire config ---
# Reports what config_load had to reject (it already fell back to defaults).
config_validate() {
    local errors=0 problem

    for problem in "${_CONFIG_PROBLEMS[@]}"; do
        echo "Config: $problem" >&2
        errors=$((errors + 1))
    done

    for key in "${!CONFIG_TYPES[@]}"; do
        local value="${!key:-}"
        if ! config_validate_value "$key" "$value" 2>/dev/null; then
            echo "Config: $key='$value' is not valid" >&2
            errors=$((errors + 1))
        fi
    done

    if [[ "$errors" -gt 0 ]]; then
        log_error "Config validation found $errors error(s)"
        return 1
    fi
    return 0
}

# --- The update command grammar ---
# One or more commands joined by " && ". Each is an optional "sudo", then a
# known package tool, then plain arguments. No shell syntax at all, and no
# option that points a tool at attacker-chosen code, config or roots.
# Usage: config_parse_update_command <string>  -> one command per line, argv
# words separated by single spaces; 1 and _UPDATE_COMMAND_ERROR on rejection.
_UPDATE_COMMAND_ERROR=""
readonly _UPDATE_TOOLS=" apt apt-get aptitude nala dnf yum pacman zypper flatpak snap "
config_parse_update_command() {
    local cmd="$1" rest part tok i
    _UPDATE_COMMAND_ERROR=""
    if [[ -z "$cmd" ]]; then _UPDATE_COMMAND_ERROR="empty"; return 1; fi
    rest="$cmd"
    while :; do
        if [[ "$rest" == *" && "* ]]; then
            part="${rest%% && *}"
            rest="${rest#* && }"
        else
            part="$rest"
            rest=""
        fi
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        if [[ -z "$part" ]]; then _UPDATE_COMMAND_ERROR="empty command"; return 1; fi
        if [[ "$part" =~ [^A-Za-z0-9=._:+,\ -] ]]; then
            _UPDATE_COMMAND_ERROR="only letters, digits, space and = . _ : + , - are allowed"
            return 1
        fi
        local -a words=()
        read -ra words <<< "$part"
        i=0
        if [[ "${words[0]}" == "sudo" ]]; then
            i=1
        fi
        tok="${words[$i]:-}"
        if [[ " $_UPDATE_TOOLS " != *" $tok "* ]]; then
            _UPDATE_COMMAND_ERROR="'$tok' is not a known package tool"
            return 1
        fi
        for tok in "${words[@]:$((i + 1))}"; do
            if [[ ! "$tok" =~ ^-{0,2}[A-Za-z0-9][A-Za-z0-9=._:+,-]*$ ]]; then
                _UPDATE_COMMAND_ERROR="bad argument '$tok'"
                return 1
            fi
            case "$tok" in
                -o|-o=*|-o[A-Za-z]*|--option|--option=*|-c|-c=*|-c[A-Za-z]*|--config-file*|--config*|-C|-C=*|-C[A-Za-z]*|\
                --root*|--installroot*|--setopt*|--hookdir*|--dbpath*|--sysroot*|--cachedir*|--cache-dir*|--logfile*|\
                --plugins-root*|--pluginpath*|--pluginconfpath*|--releasever*|--user-data-dir*|--installation=*|--system|--user)
                    _UPDATE_COMMAND_ERROR="option '$tok' is not allowed"
                    return 1
                    ;;
            esac
            if [[ "$tok" == *::* ]]; then
                _UPDATE_COMMAND_ERROR="apt configuration options are not allowed"
                return 1
            fi
        done
        printf '%s\n' "${words[*]}"
        [[ -z "$rest" ]] && break
    done
    return 0
}

# --- Print resolved config ---
config_print() {
    for key in $(echo "${!CONFIG_DEFAULTS[@]}" | tr ' ' '\n' | sort); do
        local value="${!key:-${CONFIG_DEFAULTS[$key]}}"
        printf "%-28s = %s\n" "$key" "$value"
    done
}

# --- Migrate config from v1.1.0 to v2.0.0 ---
migrate_110_to_200() {
    local src="$1"
    local dest="$NUDGE_CONFIG_FILE"

    log_info "Migrating config from v1.1.0 to v2.0.0"

    # Create new config directory
    mkdir -p "$NUDGE_CONFIG_DIR"

    # Backup original
    local backup
    backup="${src}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$src" "$backup"
    log_info "Config backed up to: $backup"

    # Load old config values
    config_load "$src"

    # Write new config
    config_write "$dest"

    log_info "Config migrated to: $dest"
}

# --- Run config migration ---
config_migrate() {
    # Check if legacy config exists and new config doesn't
    if [[ -f "$NUDGE_LEGACY_CONFIG" ]] && [[ ! -f "$NUDGE_CONFIG_FILE" ]]; then
        migrate_110_to_200 "$NUDGE_LEGACY_CONFIG"
        return 0
    fi

    # Check CONF_VERSION in current config
    if [[ -f "$NUDGE_CONFIG_FILE" ]]; then
        local current_version=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^CONF_VERSION=(.*)$ ]]; then
                current_version="${BASH_REMATCH[1]}"
                current_version="${current_version//\"/}"
                break
            fi
        done < "$NUDGE_CONFIG_FILE"

        if [[ -z "$current_version" ]] || [[ "$current_version" != "$NUDGE_CONF_VERSION" ]]; then
            log_info "Config needs migration (version: ${current_version:-unknown})"
            local backup
            backup="${NUDGE_CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
            cp "$NUDGE_CONFIG_FILE" "$backup"
            config_load "$NUDGE_CONFIG_FILE"
            config_write "$NUDGE_CONFIG_FILE"
            return 0
        fi
    fi

    log_info "Config is up to date"
    return 0
}

# --- Write config file (atomically, readable by the owner only) ---
config_write() {
    local final="${1:-$NUDGE_CONFIG_FILE}"
    mkdir -p "$(dirname "$final")" || {
        log_error "Cannot create config directory: $(dirname "$final")"
        return 1
    }
    if [[ -L "$final" ]]; then
        log_error "Refusing to write through a symlink: $final"
        return 1
    fi
    local dest
    dest=$(umask 077 && mktemp "${final}.XXXXXX") || {
        log_error "Cannot create a temporary file beside $final"
        return 1
    }

    cat > "$dest" << 'HEADER'
# nudge — configuration
# A gentle nudge to keep your system fresh.
# Edit by hand or through: setup.sh (Configure settings)
HEADER

    # Write config values using printf to prevent heredoc variable expansion issues
    # (values containing $, backticks, or backslashes are written literally)
    {
    printf '\n# Config format version (do not edit)\n'
    printf 'CONF_VERSION="%s"\n' "$NUDGE_CONF_VERSION"

    printf '\n# --- Core Settings ---\n'
    printf '\n# Enable or disable nudge (true/false)\n'
    printf 'ENABLED=%s\n' "${ENABLED:-true}"
    printf '\n# Delay in seconds after login before checking for updates\n'
    printf 'DELAY=%s\n' "${DELAY:-45}"
    printf '\n# Highlight security updates separately (true/false)\n'
    printf 'CHECK_SECURITY=%s\n' "${CHECK_SECURITY:-true}"
    printf '\n# Auto-dismiss dialog after N seconds (0 = never dismiss)\n'
    printf 'AUTO_DISMISS=%s\n' "${AUTO_DISMISS:-0}"
    printf '\n# Command to run for system update\n'
    printf 'UPDATE_COMMAND="%s"\n' "${UPDATE_COMMAND:-sudo apt update && sudo apt full-upgrade}"
    printf '\n# Show the selection menu (lists, subcategories, single packages) after Update Now (true/false)\n'
    printf 'SELECT_UPDATES=%s\n' "${SELECT_UPDATES:-true}"

    printf '\n# --- Network Settings ---\n'
    printf '\n# Host for network connectivity check\n'
    printf 'NETWORK_HOST="%s"\n' "${NETWORK_HOST:-archive.ubuntu.com}"
    printf '\n# Network check timeout in seconds\n'
    printf 'NETWORK_TIMEOUT=%s\n' "${NETWORK_TIMEOUT:-5}"
    printf '\n# Number of network check retries before giving up\n'
    printf 'NETWORK_RETRIES=%s\n' "${NETWORK_RETRIES:-2}"
    printf '\n# Behavior when network unavailable: skip, notify, queue\n'
    printf 'OFFLINE_MODE="%s"\n' "${OFFLINE_MODE:-skip}"

    printf '\n# --- Notification Settings ---\n'
    printf '\n# Notification backend: auto, kdialog, zenity, notify-send, dunstify, gdbus, none\n'
    printf 'NOTIFICATION_BACKEND="%s"\n' "${NOTIFICATION_BACKEND:-auto}"
    printf '\n# App name for dunst notifications\n'
    printf 'DUNST_APPNAME="%s"\n' "${DUNST_APPNAME:-nudge}"
    printf '\n# Show package list before prompting (true/false)\n'
    printf 'PREVIEW_UPDATES=%s\n' "${PREVIEW_UPDATES:-true}"
    printf '\n# Show critical/security packages first (true/false)\n'
    printf 'SECURITY_PRIORITY=%s\n' "${SECURITY_PRIORITY:-true}"

    printf '\n# --- Schedule Settings ---\n'
    printf '\n# Check frequency: login, daily, weekly\n'
    printf 'SCHEDULE_MODE="%s"\n' "${SCHEDULE_MODE:-login}"
    printf '\n# Hours between checks (for daily/weekly modes)\n'
    printf 'SCHEDULE_INTERVAL_HOURS=%s\n' "${SCHEDULE_INTERVAL_HOURS:-24}"
    printf '\n# Choices for "Remind me later" (comma-separated durations)\n'
    printf 'DEFERRAL_OPTIONS="%s"\n' "${DEFERRAL_OPTIONS:-1h,4h,1d}"

    printf '\n# --- Package Manager Settings ---\n'
    printf '\n# Force specific package manager (empty = auto-detect)\n'
    printf 'PKGMGR_OVERRIDE="%s"\n' "${PKGMGR_OVERRIDE:-}"
    printf '\n# Check flatpak updates: true, false, auto\n'
    printf 'FLATPAK_ENABLED="%s"\n' "${FLATPAK_ENABLED:-auto}"
    printf '\n# Check snap updates: true, false, auto\n'
    printf 'SNAP_ENABLED="%s"\n' "${SNAP_ENABLED:-auto}"

    printf '\n# --- History & Logging ---\n'
    printf '\n# Write history records (true/false)\n'
    printf 'HISTORY_ENABLED=%s\n' "${HISTORY_ENABLED:-true}"
    printf '\n# Rotate history at this many lines\n'
    printf 'HISTORY_MAX_LINES=%s\n' "${HISTORY_MAX_LINES:-500}"
    printf '\n# Log file path (empty = no logging)\n'
    printf 'LOG_FILE="%s"\n' "${LOG_FILE:-}"
    printf '\n# Log verbosity: debug, info, warn, error\n'
    printf 'LOG_LEVEL="%s"\n' "${LOG_LEVEL:-info}"
    printf '\n# Default to JSON output (true/false)\n'
    printf 'JSON_OUTPUT=%s\n' "${JSON_OUTPUT:-false}"

    printf '\n# --- Safety Settings ---\n'
    printf '\n# Detect if reboot needed post-upgrade (true/false)\n'
    printf 'REBOOT_CHECK=%s\n' "${REBOOT_CHECK:-true}"
    printf '\n# Take filesystem snapshot before upgrade (true/false)\n'
    printf 'SNAPSHOT_ENABLED=%s\n' "${SNAPSHOT_ENABLED:-false}"
    printf '\n# Snapshot backend: auto, timeshift, snapper, btrfs\n'
    printf 'SNAPSHOT_TOOL="%s"\n' "${SNAPSHOT_TOOL:-auto}"

    printf '\n# --- Self-Update Settings ---\n'
    printf '\n# Check GitHub for newer nudge version (true/false)\n'
    printf 'SELF_UPDATE_CHECK=%s\n' "${SELF_UPDATE_CHECK:-true}"
    printf '\n# Release channel: stable, beta\n'
    printf 'SELF_UPDATE_CHANNEL="%s"\n' "${SELF_UPDATE_CHANNEL:-stable}"

    printf '\n# --- Terminal Settings ---\n'
    printf '\n# Terminal emulator for upgrade commands (auto = detect)\n'
    printf 'TERMINAL_EMULATOR="%s"\n' "${TERMINAL_EMULATOR:-auto}"

    printf '\n# --- Security Classification ---\n'
    printf '\n# Extra package names to classify as CRITICAL (pipe-separated)\n'
    printf 'CRITICAL_PACKAGES_EXTRA="%s"\n' "${CRITICAL_PACKAGES_EXTRA:-}"

    printf '\n# --- Personality Settings ---\n'
    printf '\n# Bunny personality voice: classic (neutral), disney (bubbly baby-talk)\n'
    printf 'BUNNY_PERSONALITY="%s"\n' "${BUNNY_PERSONALITY:-disney}"
    } >> "$dest"
    if [[ -e "$final" ]]; then
        chmod --reference="$final" "$dest" 2>/dev/null || true
    fi
    mv -f "$dest" "$final" || {
        rm -f "$dest"
        log_error "Cannot write $final"
        return 1
    }
}

# --- Ensure data directories exist ---
config_ensure_dirs() {
    mkdir -p "$NUDGE_CONFIG_DIR" 2>/dev/null || true
    mkdir -p "$NUDGE_DATA_DIR" 2>/dev/null || true
    mkdir -p "$NUDGE_STATE_DIR" 2>/dev/null || true
    if [[ -n "${LOG_FILE:-}" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    fi
}
