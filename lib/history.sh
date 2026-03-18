#!/usr/bin/env bash
# nudge — lib/history.sh
# JSONL history log and viewer
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

HISTORY_FILE="${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/history.jsonl"

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

    # Build JSONL record
    local record
    record=$(cat <<ENDJSON
{"timestamp":"$ts","nudge_version":"${NUDGE_VERSION:-2.0.0}","trigger":"$trigger","pkg_manager":"${DETECTED_PKGMGR:-unknown}","outcome":"$outcome","detail":"$detail","updates_total":${PKG_UPDATES_TOTAL:-0},"updates_security":${PKG_UPDATES_SECURITY:-0},"updates_critical":${PKG_UPDATES_CRITICAL:-0},"updates_flatpak":${PKG_UPDATES_FLATPAK:-0},"updates_snap":${PKG_UPDATES_SNAP:-0},"packages":$packages_json,"reboot_required":${_JSON_DATA[reboot_required]:-false},"snapshot_id":${_JSON_DATA[snapshot_id]:-null},"deferred":${_JSON_DATA[deferred]:-false},"duration_seconds":${_JSON_DATA[duration_seconds]:-0},"exit_code":$exit_code}
ENDJSON
)
    echo "$record" >> "$HISTORY_FILE" 2>/dev/null || true

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
        local tmp="${HISTORY_FILE}.tmp"
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
        ts=$(echo "$line" | grep -oP '"timestamp":"[^"]*"' | cut -d'"' -f4 | cut -c1-19)
        pkg=$(echo "$line" | grep -oP '"pkg_manager":"[^"]*"' | cut -d'"' -f4)
        outcome=$(echo "$line" | grep -oP '"outcome":"[^"]*"' | cut -d'"' -f4)
        total=$(echo "$line" | grep -oP '"updates_total":[0-9]*' | cut -d: -f2)
        sec=$(echo "$line" | grep -oP '"updates_security":[0-9]*' | cut -d: -f2)
        crit=$(echo "$line" | grep -oP '"updates_critical":[0-9]*' | cut -d: -f2)
        ec=$(echo "$line" | grep -oP '"exit_code":[0-9]*' | cut -d: -f2)

        printf "%-20s  %-8s  %-6s  %-12s  %-5s  %-5s  %s\n" \
            "${ts:-?}" "${pkg:-?}" "${total:-0}" "${outcome:-?}" "${sec:-0}" "${crit:-0}" "${ec:-0}"
    done <<< "$lines"
}

# --- Filter history by date ---
_history_filter_since() {
    local since="$1"
    local since_epoch
    since_epoch=$(date -d "$since" +%s 2>/dev/null || echo 0)

    while IFS= read -r line; do
        local ts
        ts=$(echo "$line" | grep -oP '"timestamp":"[^"]*"' | cut -d'"' -f4)
        local ts_epoch
        ts_epoch=$(date -d "$ts" +%s 2>/dev/null || echo 0)
        if [[ "$ts_epoch" -ge "$since_epoch" ]]; then
            echo "$line"
        fi
    done < "$HISTORY_FILE"
}
