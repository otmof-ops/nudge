#!/usr/bin/env bash
# nudge — lib/config.sh
# Configuration loading, validation, and migration
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

# --- Config paths ---
NUDGE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nudge"
NUDGE_CONFIG_FILE="${NUDGE_CONFIG_DIR}/nudge.conf"
NUDGE_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nudge"
NUDGE_STATE_DIR="$NUDGE_DATA_DIR"

# Legacy config path (v1.x)
NUDGE_LEGACY_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nudge.conf"

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
    [CONF_VERSION]="2.0.0"
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
    [EXIT_ON_HELD]="true"
    [JSON_OUTPUT]="false"
    [LOG_LEVEL]="info"
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
    [EXIT_ON_HELD]="bool"
    [JSON_OUTPUT]="bool"
    [LOG_LEVEL]="enum:debug,info,warn,error"
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
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
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

# --- Load config with safe line-by-line parser ---
config_load() {
    local config_file="${1:-$NUDGE_CONFIG_FILE}"

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

    # Line-by-line parser — no source
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue

        # Parse KEY=VALUE or KEY="VALUE"
        if [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Strip surrounding quotes
            if [[ "$value" =~ ^\"(.*)\"$ ]]; then
                value="${BASH_REMATCH[1]}"
            elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            # Check if this is a known key
            if [[ -n "${CONFIG_DEFAULTS[$key]+x}" ]]; then
                if config_validate_value "$key" "$value"; then
                    printf -v "$key" '%s' "$value"
                else
                    printf -v "$key" '%s' "${CONFIG_DEFAULTS[$key]}"
                fi
            else
                log_warn "Config line $line_num: unknown key '$key' (ignored)"
            fi
        else
            log_warn "Config line $line_num: unparseable line (ignored)"
        fi
    done < "$config_file"

    return 0
}

# --- Validate entire config ---
config_validate() {
    local errors=0

    for key in "${!CONFIG_TYPES[@]}"; do
        local value
        value="$(eval "echo \"\${$key:-}\"")"
        if ! config_validate_value "$key" "$value" 2>/dev/null; then
            errors=$((errors + 1))
        fi
    done

    if [[ "$errors" -gt 0 ]]; then
        log_error "Config validation found $errors error(s)"
        return 1
    fi
    return 0
}

# --- Print resolved config ---
config_print() {
    for key in $(echo "${!CONFIG_DEFAULTS[@]}" | tr ' ' '\n' | sort); do
        local value
        value="$(eval "echo \"\${$key:-${CONFIG_DEFAULTS[$key]}}\"")"
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

        if [[ -z "$current_version" ]] || [[ "$current_version" != "2.0.0" ]]; then
            log_info "Config needs migration (version: ${current_version:-unknown})"
            local backup
            backup="${NUDGE_CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
            cp "$NUDGE_CONFIG_FILE" "$backup"
            config_load "$NUDGE_CONFIG_FILE"
            CONF_VERSION="2.0.0"
            config_write "$NUDGE_CONFIG_FILE"
            return 0
        fi
    fi

    log_info "Config is up to date"
    return 0
}

# --- Write config file ---
config_write() {
    local dest="${1:-$NUDGE_CONFIG_FILE}"
    mkdir -p "$(dirname "$dest")"

    cat > "$dest" << 'HEADER'
# nudge — configuration
# A gentle nudge to keep your system fresh.
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.
HEADER

    cat >> "$dest" << CONF

# Config format version (do not edit)
CONF_VERSION="${CONF_VERSION:-2.0.0}"

# --- Core Settings ---

# Enable or disable nudge (true/false)
ENABLED=${ENABLED:-true}

# Delay in seconds after login before checking for updates
DELAY=${DELAY:-45}

# Highlight security updates separately (true/false)
CHECK_SECURITY=${CHECK_SECURITY:-true}

# Auto-dismiss dialog after N seconds (0 = never dismiss)
AUTO_DISMISS=${AUTO_DISMISS:-0}

# Command to run for system update
UPDATE_COMMAND="${UPDATE_COMMAND:-sudo apt update && sudo apt full-upgrade}"

# --- Network Settings ---

# Host for network connectivity check
NETWORK_HOST="${NETWORK_HOST:-archive.ubuntu.com}"

# Network check timeout in seconds
NETWORK_TIMEOUT=${NETWORK_TIMEOUT:-5}

# Number of network check retries before giving up
NETWORK_RETRIES=${NETWORK_RETRIES:-2}

# Behavior when network unavailable: skip, notify, queue
OFFLINE_MODE="${OFFLINE_MODE:-skip}"

# --- Notification Settings ---

# Notification backend: auto, kdialog, zenity, notify-send, dunstify, gdbus, none
NOTIFICATION_BACKEND="${NOTIFICATION_BACKEND:-auto}"

# App name for dunst notifications
DUNST_APPNAME="${DUNST_APPNAME:-nudge}"

# Show package list before prompting (true/false)
PREVIEW_UPDATES=${PREVIEW_UPDATES:-true}

# Show critical/security packages first (true/false)
SECURITY_PRIORITY=${SECURITY_PRIORITY:-true}

# --- Schedule Settings ---

# Check frequency: login, daily, weekly
SCHEDULE_MODE="${SCHEDULE_MODE:-login}"

# Hours between checks (for daily/weekly modes)
SCHEDULE_INTERVAL_HOURS=${SCHEDULE_INTERVAL_HOURS:-24}

# Choices for "Remind me later" (comma-separated durations)
DEFERRAL_OPTIONS="${DEFERRAL_OPTIONS:-1h,4h,1d}"

# --- Package Manager Settings ---

# Force specific package manager (empty = auto-detect)
PKGMGR_OVERRIDE="${PKGMGR_OVERRIDE:-}"

# Check flatpak updates: true, false, auto
FLATPAK_ENABLED="${FLATPAK_ENABLED:-auto}"

# Check snap updates: true, false, auto
SNAP_ENABLED="${SNAP_ENABLED:-auto}"

# Skip held/pinned packages silently (true/false)
EXIT_ON_HELD=${EXIT_ON_HELD:-true}

# --- History & Logging ---

# Write history records (true/false)
HISTORY_ENABLED=${HISTORY_ENABLED:-true}

# Rotate history at this many lines
HISTORY_MAX_LINES=${HISTORY_MAX_LINES:-500}

# Log file path (empty = no logging)
LOG_FILE="${LOG_FILE:-}"

# Log verbosity: debug, info, warn, error
LOG_LEVEL="${LOG_LEVEL:-info}"

# Default to JSON output (true/false)
JSON_OUTPUT=${JSON_OUTPUT:-false}

# --- Safety Settings ---

# Detect if reboot needed post-upgrade (true/false)
REBOOT_CHECK=${REBOOT_CHECK:-true}

# Take filesystem snapshot before upgrade (true/false)
SNAPSHOT_ENABLED=${SNAPSHOT_ENABLED:-false}

# Snapshot backend: auto, timeshift, snapper, btrfs
SNAPSHOT_TOOL="${SNAPSHOT_TOOL:-auto}"

# --- Self-Update Settings ---

# Check GitHub for newer nudge version (true/false)
SELF_UPDATE_CHECK=${SELF_UPDATE_CHECK:-true}

# Release channel: stable, beta
SELF_UPDATE_CHANNEL="${SELF_UPDATE_CHANNEL:-stable}"
CONF
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
