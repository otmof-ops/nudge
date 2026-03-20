#!/usr/bin/env bash
# nudge — lib/history.sh
# JSONL history log and viewer
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

HISTORY_FILE="${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/history.jsonl"

# --- POSIX-compatible JSON field extraction (no grep -P / PCRE) ---
_json_extract_string() {
    local json="$1" key="$2"
    local val
    val=$(echo "$json" | grep -o "\"${key}\":\"[^\"]*\"" | head -1 | cut -d'"' -f4)
    echo "$val"
}

_json_extract_number() {
    local json="$1" key="$2"
    local val
    val=$(echo "$json" | grep -o "\"${key}\":[0-9]*" | head -1 | cut -d: -f2)
    echo "${val:-0}"
}

# --- Write a history record ---
history_write() {
    [[ "${HISTORY_ENABLED:-true}" != "true" ]] && return 0

    local outcome="${1:-UNKNOWN}"
    local detail="${2:-}"
    local exit_code="${3:-0}"

    mkdir -p "$(dirname "$HISTORY_FILE")" 2>/dev/null || true

    local ts
    ts="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"

    local trigger="manual"
    if [[ -n "${_NUDGE_TRIGGER:-}" ]]; then
        trigger="$_NUDGE_TRIGGER"
    fi

    local packages_json="${_JSON_DATA[packages]:-[]}"

    # Build JSONL record (escape string values)
    local _esc_ts _esc_outcome _esc_detail _esc_trigger _esc_pkg _esc_ver
    _esc_ts=$(json_escape "$ts")
    _esc_outcome=$(json_escape "$outcome")
    _esc_detail=$(json_escape "$detail")
    _esc_trigger=$(json_escape "$trigger")
    _esc_pkg=$(json_escape "${DETECTED_PKGMGR:-unknown}")
    _esc_ver=$(json_escape "${NUDGE_VERSION:-2.0.0}")

    local record
    record=$(cat <<ENDJSON
{"timestamp":"$_esc_ts","nudge_version":"$_esc_ver","trigger":"$_esc_trigger","pkg_manager":"$_esc_pkg","outcome":"$_esc_outcome","detail":"$_esc_detail","updates_total":${PKG_UPDATES_TOTAL:-0},"updates_security":${PKG_UPDATES_SECURITY:-0},"updates_critical":${PKG_UPDATES_CRITICAL:-0},"updates_flatpak":${PKG_UPDATES_FLATPAK:-0},"updates_snap":${PKG_UPDATES_SNAP:-0},"packages":$packages_json,"reboot_required":${_JSON_DATA[reboot_required]:-false},"snapshot_id":${_JSON_DATA[snapshot_id]:-null},"deferred":${_JSON_DATA[deferred]:-false},"duration_seconds":${_JSON_DATA[duration_seconds]:-0},"exit_code":$exit_code}
ENDJSON
)
    # Atomic append: write to temp file then append (prevents partial JSONL on SIGKILL)
    local _hist_tmp
    _hist_tmp=$(mktemp "${HISTORY_FILE}.XXXXXX" 2>/dev/null) || true
    if [[ -n "$_hist_tmp" ]]; then
        echo "$record" > "$_hist_tmp"
        cat "$_hist_tmp" >> "$HISTORY_FILE" 2>/dev/null || true
        rm -f "$_hist_tmp" 2>/dev/null || true
    else
        echo "$record" >> "$HISTORY_FILE" 2>/dev/null || true
    fi

    # Rotate if needed
    history_rotate
}

# --- Rotate history ---
history_rotate() {
    local max="${HISTORY_MAX_LINES:-500}"
    [[ ! -f "$HISTORY_FILE" ]] && return 0

    local count
    count=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)

    if [[ "$count" -gt "$max" ]]; then
        local trim=$((count - max))
        local tmp
        tmp=$(mktemp "${HISTORY_FILE}.XXXXXX")
        tail -n "$max" "$HISTORY_FILE" > "$tmp" 2>/dev/null
        mv "$tmp" "$HISTORY_FILE" 2>/dev/null || true
        log_debug "History rotated: removed $trim oldest entries"
    fi
}

# --- Display history (formatted table) ---
history_show() {
    local count="${1:-20}"
    local format="${2:-table}"
    local since="${3:-}"

    if [[ ! -f "$HISTORY_FILE" ]]; then
        echo "No history found."
        return 0
    fi

    if [[ "$format" == "json" ]]; then
        if [[ -n "$since" ]]; then
            _history_filter_since "$since"
        else
            tail -n "$count" "$HISTORY_FILE"
        fi
        return 0
    fi

    # Table format
    printf "%-20s  %-8s  %-6s  %-12s  %-5s  %-5s  %s\n" \
        "TIMESTAMP" "PKGMGR" "TOTAL" "OUTCOME" "SEC" "CRIT" "EXIT"
    printf "%s\n" "$(printf '%.0s─' {1..80})"

    local lines
    if [[ -n "$since" ]]; then
        lines=$(_history_filter_since "$since")
    else
        lines=$(tail -n "$count" "$HISTORY_FILE")
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Parse JSON manually (no jq dependency)
        local ts pkg outcome total sec crit ec
        # Extract JSON fields using POSIX-compatible patterns (no grep -P)
        ts=$(_json_extract_string "$line" "timestamp")
        ts="${ts:0:19}"
        pkg=$(_json_extract_string "$line" "pkg_manager")
        outcome=$(_json_extract_string "$line" "outcome")
        total=$(_json_extract_number "$line" "updates_total")
        sec=$(_json_extract_number "$line" "updates_security")
        crit=$(_json_extract_number "$line" "updates_critical")
        ec=$(_json_extract_number "$line" "exit_code")

        printf "%-20s  %-8s  %-6s  %-12s  %-5s  %-5s  %s\n" \
            "${ts:-?}" "${pkg:-?}" "${total:-0}" "${outcome:-?}" "${sec:-0}" "${crit:-0}" "${ec:-0}"
    done <<< "$lines"
}

# --- Filter history by date ---
_history_filter_since() {
    local since="$1"
    if ! date -d "$since" +%s &>/dev/null; then
        echo "Error: Invalid date '$since'" >&2
        return 1
    fi
    local since_epoch
    since_epoch=$(date -d "$since" +%s 2>/dev/null || echo 0)

    while IFS= read -r line; do
        local ts
        ts=$(_json_extract_string "$line" "timestamp")
        local ts_epoch
        ts_epoch=$(date -d "$ts" +%s 2>/dev/null || echo 0)
        if [[ "$ts_epoch" -ge "$since_epoch" ]]; then
            echo "$line"
        fi
    done < "$HISTORY_FILE"
}
