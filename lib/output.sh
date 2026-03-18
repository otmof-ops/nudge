#!/usr/bin/env bash
# nudge — lib/output.sh
# Exit codes, logging, and JSON output
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

# --- Named exit codes ---
# shellcheck disable=SC2034  # Variables are used by sourcing scripts
readonly EXIT_OK=0
readonly EXIT_UPDATES_DECLINED=1
readonly EXIT_UPDATES_APPLIED=2
readonly EXIT_UPDATES_FAILED=3
readonly EXIT_DISABLED=4
readonly EXIT_NETWORK_FAIL=5
readonly EXIT_PKG_LOCK=6
readonly EXIT_ALREADY_RUNNING=7
readonly EXIT_NO_BACKEND=8
readonly EXIT_DEFERRED=9
readonly EXIT_CONFIG_ERROR=10
readonly EXIT_INTERRUPTED=11
readonly EXIT_SNAPSHOT_FAILED=12
readonly EXIT_REBOOT_PENDING=13

# Map exit codes to reason strings
declare -gA EXIT_REASONS=(
    [0]="OK"
    [1]="UPDATES_DECLINED"
    [2]="UPDATES_APPLIED"
    [3]="UPDATES_FAILED"
    [4]="DISABLED"
    [5]="NETWORK_FAIL"
    [6]="PKG_LOCK"
    [7]="ALREADY_RUNNING"
    [8]="NO_BACKEND"
    [9]="DEFERRED"
    [10]="CONFIG_ERROR"
    [11]="INTERRUPTED"
    [12]="SNAPSHOT_FAILED"
    [13]="REBOOT_PENDING"
)

# --- Log level constants ---
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Resolved numeric log level (set by output_init)
_LOG_THRESHOLD="$LOG_LEVEL_INFO"

# JSON output mode
_JSON_MODE=false
_VERBOSE_MODE=false

# JSON accumulator
declare -gA _JSON_DATA=()

# --- Initialize output subsystem ---
output_init() {
    local level="${LOG_LEVEL:-info}"
    case "${level,,}" in
        debug) _LOG_THRESHOLD="$LOG_LEVEL_DEBUG" ;;
        info)  _LOG_THRESHOLD="$LOG_LEVEL_INFO" ;;
        warn)  _LOG_THRESHOLD="$LOG_LEVEL_WARN" ;;
        error) _LOG_THRESHOLD="$LOG_LEVEL_ERROR" ;;
        *)     _LOG_THRESHOLD="$LOG_LEVEL_INFO" ;;
    esac

    if [[ "${JSON_OUTPUT:-false}" == "true" ]] || [[ "${_JSON_FLAG:-false}" == "true" ]]; then
        _JSON_MODE=true
    fi

    if [[ "${_VERBOSE_FLAG:-false}" == "true" ]]; then
        _VERBOSE_MODE=true
        _LOG_THRESHOLD="$LOG_LEVEL_DEBUG"
    fi
}

# --- Core logging ---
_log() {
    local level_num="$1" level_name="$2"
    shift 2
    local msg="$*"

    [[ "$level_num" -lt "$_LOG_THRESHOLD" ]] && return 0

    # In JSON mode, suppress human output
    if [[ "$_JSON_MODE" == "true" ]]; then
        return 0
    fi

    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local line="[$ts] [$level_name] $msg"

    # Write to log file if configured
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "$line" >> "$LOG_FILE" 2>/dev/null || true
    fi

    # Write to stdout if verbose, dry-run, or check-only
    if [[ "$_VERBOSE_MODE" == "true" ]] || \
       [[ "${DRY_RUN:-false}" == "true" ]] || \
       [[ "${CHECK_ONLY:-false}" == "true" ]]; then
        echo "$line" >&2
    fi
}

log_debug() { _log "$LOG_LEVEL_DEBUG" "DEBUG" "$@"; }
log_info()  { _log "$LOG_LEVEL_INFO"  "INFO"  "$@"; }
log_warn()  { _log "$LOG_LEVEL_WARN"  "WARN"  "$@"; }
log_error() { _log "$LOG_LEVEL_ERROR" "ERROR" "$@"; }

# Backward-compatible log() alias
log() { log_info "$@"; }

# --- JSON output ---
json_set() {
    local key="$1" value="$2"
    _JSON_DATA["$key"]="$value"
}

json_emit() {
    local exit_code="${1:-0}"
    [[ "$_JSON_MODE" != "true" ]] && return 0

    local reason="${EXIT_REASONS[$exit_code]:-UNKNOWN}"
    local ts
    ts="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"

    # Build JSON manually (no jq dependency)
    cat <<ENDJSON
{
  "nudge_version": "${NUDGE_VERSION:-2.0.0}",
  "timestamp": "$ts",
  "exit_code": $exit_code,
  "exit_reason": "$reason",
  "pkg_manager": "${_JSON_DATA[pkg_manager]:-null}",
  "updates": {
    "total": ${_JSON_DATA[updates_total]:-0},
    "security": ${_JSON_DATA[updates_security]:-0},
    "critical": ${_JSON_DATA[updates_critical]:-0},
    "flatpak": ${_JSON_DATA[updates_flatpak]:-0},
    "snap": ${_JSON_DATA[updates_snap]:-0}
  },
  "packages": ${_JSON_DATA[packages]:-[]},
  "reboot_required": ${_JSON_DATA[reboot_required]:-false},
  "snapshot_id": ${_JSON_DATA[snapshot_id]:-null},
  "deferred": ${_JSON_DATA[deferred]:-false},
  "duration_seconds": ${_JSON_DATA[duration_seconds]:-0}
}
ENDJSON
}

# --- Exit reason lookup ---
exit_reason() {
    echo "${EXIT_REASONS[${1:-0}]:-UNKNOWN}"
}
