#!/usr/bin/env bash
# nudge — lib/lock.sh
# flock-based instance locking
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/nudge-${UID}.lock"
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
    log_debug "Lock released"
}
