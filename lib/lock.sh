#!/usr/bin/env bash
# nudge — lib/lock.sh
# flock-based instance locking
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    _NUDGE_RUNTIME_DIR=$(mktemp -d "/tmp/nudge-${UID}-XXXXXX")
else
    _NUDGE_RUNTIME_DIR="$XDG_RUNTIME_DIR"
fi
LOCK_FILE="${_NUDGE_RUNTIME_DIR}/nudge-${UID}.lock"
LOCK_FD=""

# --- Acquire lock ---
lock_acquire() {
    exec {LOCK_FD}>"$LOCK_FILE"
    if ! flock -n "$LOCK_FD"; then
        log_warn "Another nudge instance is running"
        return 1
    fi
    log_debug "Lock acquired: $LOCK_FILE (fd=$LOCK_FD)"
    return 0
}

# --- Release lock (called automatically on exit) ---
lock_release() {
    if [[ -n "$LOCK_FD" ]]; then
        exec {LOCK_FD}>&- 2>/dev/null || true
        LOCK_FD=""
    fi
    rm -f "$LOCK_FILE" 2>/dev/null || true
    # Clean up temp runtime directory if we created one
    if [[ "${_NUDGE_RUNTIME_DIR:-}" == /tmp/nudge-* ]]; then
        rmdir "$_NUDGE_RUNTIME_DIR" 2>/dev/null || true
    fi
    log_debug "Lock released"
}
