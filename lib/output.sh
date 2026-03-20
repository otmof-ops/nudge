#!/usr/bin/env bash
# nudge — lib/output.sh
# Exit codes, logging, and JSON output
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

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

# --- Mascot banner ---
output_banner() {
    local msg_line1="${1:-}"
    local msg_line2="${2:-}"
    local face="${3:-( -.-)}"
    if [[ -n "$msg_line1" ]] && [[ -n "$msg_line2" ]]; then
        printf ' (\\(\\\n'
        printf ' %s  %s\n' "$face" "$msg_line1"
        printf ' o_(")(")  %s\n' "$msg_line2"
    elif [[ -n "$msg_line1" ]]; then
        printf ' (\\(\\\n'
        printf ' %s  %s\n' "$face" "$msg_line1"
        printf ' o_(")(") \n'
    else
        printf ' (\\(\\\n'
        printf ' %s\n' "$face"
        printf ' o_(")(") \n'
    fi
}

# --- Pre-formatted content renderer ---
# Usage: output_render <content>
# Prints pre-formatted multi-line string (e.g., bunny pose output)
output_render() {
    local content="${1:-}"
    [[ -z "$content" ]] && return 0
    printf '%s\n' "$content"
}

# --- JSON string escaper (RFC 8259 compliant) ---
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    # Handle remaining control characters U+0001–U+001F via per-character sed substitution
    # shellcheck disable=SC1003
    s=$(printf '%s' "$s" | sed \
        -e 's/\x01/\\u0001/g' -e 's/\x02/\\u0002/g' -e 's/\x03/\\u0003/g' \
        -e 's/\x04/\\u0004/g' -e 's/\x05/\\u0005/g' -e 's/\x06/\\u0006/g' \
        -e 's/\x07/\\u0007/g' -e 's/\x08/\\u0008/g' -e 's/\x0b/\\u000b/g' \
        -e 's/\x0c/\\u000c/g' -e 's/\x0e/\\u000e/g' -e 's/\x0f/\\u000f/g' \
        -e 's/\x10/\\u0010/g' -e 's/\x11/\\u0011/g' -e 's/\x12/\\u0012/g' \
        -e 's/\x13/\\u0013/g' -e 's/\x14/\\u0014/g' -e 's/\x15/\\u0015/g' \
        -e 's/\x16/\\u0016/g' -e 's/\x17/\\u0017/g' -e 's/\x18/\\u0018/g' \
        -e 's/\x19/\\u0019/g' -e 's/\x1a/\\u001a/g' -e 's/\x1b/\\u001b/g' \
        -e 's/\x1c/\\u001c/g' -e 's/\x1d/\\u001d/g' -e 's/\x1e/\\u001e/g' \
        -e 's/\x1f/\\u001f/g' 2>/dev/null) || true
    printf '%s' "$s"
}

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
    local _esc_ver _esc_ts _esc_reason _esc_pkg
    _esc_ver=$(json_escape "${NUDGE_VERSION:-2.0.0}")
    _esc_ts=$(json_escape "$ts")
    _esc_reason=$(json_escape "$reason")
    _esc_pkg="${_JSON_DATA[pkg_manager]:-}"

    cat <<ENDJSON
{
  "nudge_version": "$_esc_ver",
  "timestamp": "$_esc_ts",
  "exit_code": $exit_code,
  "exit_reason": "$_esc_reason",
  "pkg_manager": $(if [[ -n "$_esc_pkg" ]]; then printf '"%s"' "$(json_escape "$_esc_pkg")"; else printf 'null'; fi),
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
