#!/usr/bin/env bash
# nudge — lib/network.sh
# Multi-method network connectivity probe
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

# --- Single probe attempt (three methods) ---
network_probe_once() {
    local host="${NETWORK_HOST:-archive.ubuntu.com}"
    local timeout="${NETWORK_TIMEOUT:-5}"

    # Method 1: curl (HTTP HEAD)
    if command -v curl &>/dev/null; then
        if curl --head --silent --max-time "$timeout" --output /dev/null "https://$host" 2>/dev/null; then
            log_debug "Network probe passed (curl → $host)"
            return 0
        fi
    fi

    # Method 2: wget (spider)
    if command -v wget &>/dev/null; then
        if wget --spider --timeout="$timeout" --quiet "https://$host" 2>/dev/null; then
            log_debug "Network probe passed (wget → $host)"
            return 0
        fi
    fi

    # Method 3: ping (ICMP)
    if command -v ping &>/dev/null; then
        if ping -c 1 -W "$timeout" "$host" &>/dev/null; then
            log_debug "Network probe passed (ping → $host)"
            return 0
        fi
    fi

    return 1
}

# --- Network check with retries ---
network_check() {
    local retries="${NETWORK_RETRIES:-2}"
    local attempt=0

    while ! network_probe_once; do
        attempt=$((attempt + 1))
        if [[ "$attempt" -gt "$retries" ]]; then
            log_warn "Network check failed after $retries retries"
            return 1
        fi
        log_info "Network check failed. Retry $attempt/$retries in 15s."
        if [[ "${DRY_RUN:-false}" != "true" ]] && [[ "${CHECK_ONLY:-false}" != "true" ]]; then
            sleep 15
        fi
    done

    log_info "Network check passed"
    return 0
}

# --- Handle offline mode ---
network_handle_offline() {
    local mode="${OFFLINE_MODE:-skip}"

    case "$mode" in
        skip)
            log_info "Offline mode: skip — exiting silently"
            return "$EXIT_NETWORK_FAIL"
            ;;
        notify)
            log_info "Offline mode: notify — showing notification"
            local _net_msg="Network unavailable, skipping update check"
            local _net_personality_msg
            _net_personality_msg=$(bunny_message "network" 2>/dev/null) || true
            [[ -n "$_net_personality_msg" ]] && _net_msg="$_net_personality_msg"
            if command -v notify-send &>/dev/null; then
                notify-send -i network-offline "nudge" \
                    "$_net_msg" 2>/dev/null || true
            fi
            return "$EXIT_NETWORK_FAIL"
            ;;
        queue)
            log_info "Offline mode: queue — flagging for next run"
            mkdir -p "$NUDGE_STATE_DIR" 2>/dev/null || true
            { date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'; } \
                > "$NUDGE_STATE_DIR/pending_check"
            return "$EXIT_NETWORK_FAIL"
            ;;
        *)
            return "$EXIT_NETWORK_FAIL"
            ;;
    esac
}
