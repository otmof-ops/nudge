#!/usr/bin/env bash
# nudge — lib/schedule.sh
# Scheduling, interval guards, and deferral
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

SCHEDULE_LAST_CHECK_FILE="${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/last_check"
SCHEDULE_DEFERRED_FILE="${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/deferred_until"

# --- Check if a check is due ---
schedule_due() {
    local mode="${SCHEDULE_MODE:-login}"
    local interval_hours="${SCHEDULE_INTERVAL_HOURS:-24}"

    # Check deferral first
    if [[ -f "$SCHEDULE_DEFERRED_FILE" ]]; then
        local deferred_until
        deferred_until=$(cat "$SCHEDULE_DEFERRED_FILE" 2>/dev/null || true)
        if [[ -n "$deferred_until" ]]; then
            local deferred_epoch now_epoch
            deferred_epoch=$(date -d "$deferred_until" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            if [[ "$now_epoch" -lt "$deferred_epoch" ]]; then
                log_info "Check deferred until $deferred_until"
                return 1
            else
                # Deferral expired, clean up
                rm -f "$SCHEDULE_DEFERRED_FILE" 2>/dev/null || true
                log_info "Deferral expired, proceeding"
            fi
        fi
    fi

    # Check pending queue (from offline mode)
    if [[ -f "${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/pending_check" ]]; then
        rm -f "${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/pending_check" 2>/dev/null || true
        log_info "Pending check from offline queue — forcing check"
        return 0
    fi

    # Login mode: always due
    if [[ "$mode" == "login" ]]; then
        return 0
    fi

    # Daily/weekly: check interval
    if [[ ! -f "$SCHEDULE_LAST_CHECK_FILE" ]]; then
        log_debug "No last_check file — check is due"
        return 0
    fi

    local last_check
    last_check=$(cat "$SCHEDULE_LAST_CHECK_FILE" 2>/dev/null || true)
    if [[ -z "$last_check" ]]; then
        return 0
    fi

    local last_epoch now_epoch elapsed_hours
    last_epoch=$(date -d "$last_check" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    elapsed_hours=$(( (now_epoch - last_epoch) / 3600 ))

    local required_hours="$interval_hours"
    if [[ "$mode" == "weekly" ]]; then
        required_hours=$((interval_hours * 7))
    fi

    if [[ "$elapsed_hours" -ge "$required_hours" ]]; then
        log_debug "Check is due ($elapsed_hours hours since last check)"
        return 0
    else
        log_info "Check not due ($elapsed_hours/$required_hours hours elapsed)"
        return 1
    fi
}

# --- Atomic write helper (write-then-rename) ---
_atomic_write() {
    local file="$1" value="$2"
    local tmp
    tmp=$(mktemp "${file}.XXXXXX") && echo "$value" > "$tmp" && mv "$tmp" "$file"
}

# --- Mark check as completed ---
schedule_mark_done() {
    mkdir -p "$(dirname "$SCHEDULE_LAST_CHECK_FILE")" 2>/dev/null || true
    local ts
    ts=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
    _atomic_write "$SCHEDULE_LAST_CHECK_FILE" "$ts"
    log_debug "Marked last check time"
}

# --- Parse duration string (1h, 4h, 1d, 3d, 1w) ---
parse_duration() {
    local input="$1"
    local number="${input%[hdw]}"
    local unit="${input: -1}"

    if ! [[ "$number" =~ ^[0-9]+$ ]]; then
        log_error "Invalid duration: $input"
        return 1
    fi

    local seconds=0
    case "$unit" in
        h) seconds=$((number * 3600)) ;;
        d) seconds=$((number * 86400)) ;;
        w) seconds=$((number * 604800)) ;;
        *)
            log_error "Invalid duration unit: $unit (expected h/d/w)"
            return 1
            ;;
    esac

    echo "$seconds"
}

# --- Write deferral ---
schedule_defer() {
    local duration="$1"
    local seconds
    seconds=$(parse_duration "$duration") || return 1

    local until_epoch until_iso
    until_epoch=$(( $(date +%s) + seconds ))
    until_iso=$(date -d "@$until_epoch" -Iseconds 2>/dev/null || \
        date -r "$until_epoch" -Iseconds 2>/dev/null || \
        date '+%Y-%m-%dT%H:%M:%S')

    mkdir -p "$(dirname "$SCHEDULE_DEFERRED_FILE")" 2>/dev/null || true
    _atomic_write "$SCHEDULE_DEFERRED_FILE" "$until_iso"
    log_info "Deferred until: $until_iso ($duration)"
    return 0
}

# --- Show deferral options dialog ---
schedule_prompt_defer() {
    local options="${DEFERRAL_OPTIONS:-1h,4h,1d}"
    IFS=',' read -ra opts <<< "$options"

    local choice=""

    case "${NOTIFY_BACKEND:-}" in
        kdialog)
            local items=()
            for opt in "${opts[@]}"; do
                items+=("$opt" "$opt")
            done
            choice=$(kdialog --title "Remind Me Later" \
                --combobox "Remind me in:" "${items[@]}" 2>/dev/null) || true
            ;;
        zenity)
            local col_items=()
            for opt in "${opts[@]}"; do
                col_items+=("$opt")
            done
            choice=$(printf '%s\n' "${col_items[@]}" | \
                zenity --list --title="Remind Me Later" \
                --column="Duration" --text="Remind me in:" 2>/dev/null) || true
            ;;
        *)
            # Default to first option
            choice="${opts[0]}"
            ;;
    esac

    if [[ -n "$choice" ]]; then
        schedule_defer "$choice"
        return 0
    fi
    return 1
}
