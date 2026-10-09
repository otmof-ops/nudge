#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/lock.sh
# flock-based instance locking

set -euo pipefail

LOCK_FILE=""
LOCK_FD=""

# --- Where the lock lives ---
# XDG_RUNTIME_DIR when the session has one; otherwise the user's own state
# directory. The path is deterministic so two instances always meet on the
# same file (a per-run mktemp directory would never contend).
_lock_dir() {
    local dir="${XDG_RUNTIME_DIR:-}"
    if [[ -n "$dir" && -d "$dir" && -w "$dir" ]]; then
        printf '%s' "$dir"
        return 0
    fi
    dir="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}"
    mkdir -p "$dir" 2>/dev/null || return 1
    printf '%s' "$dir"
}

# --- Acquire lock ---
lock_acquire() {
    local dir
    dir=$(_lock_dir) || {
        log_error "Failed to find a directory for the lock file"
        return 1
    }
    LOCK_FILE="${dir}/nudge-${UID}.lock"
    if [[ -L "$LOCK_FILE" ]]; then
        log_error "Lock path is a symlink, refusing: $LOCK_FILE"
        return 1
    fi
    # Open for append so an existing file is never truncated under a holder.
    if ! exec {LOCK_FD}>>"$LOCK_FILE"; then
        log_error "Cannot open lock file: $LOCK_FILE"
        LOCK_FD=""
        return 1
    fi
    if ! flock -n "$LOCK_FD"; then
        log_warn "Another nudge instance is running"
        exec {LOCK_FD}>&- 2>/dev/null || true
        LOCK_FD=""
        return 1
    fi
    log_debug "Lock acquired: $LOCK_FILE (fd=$LOCK_FD)"
    return 0
}

# --- Release lock (called automatically on exit) ---
# The file stays: unlinking a lock file races with the next instance, which may
# have opened the old inode. flock is released when the descriptor closes.
lock_release() {
    if [[ -n "$LOCK_FD" ]]; then
        exec {LOCK_FD}>&- 2>/dev/null || true
        LOCK_FD=""
        log_debug "Lock released"
    fi
}
