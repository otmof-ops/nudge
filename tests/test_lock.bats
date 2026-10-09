#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause

bats_require_minimum_version 1.5.0
# Tests for lib/lock.sh — flock-based locking

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)

    # Stub logging
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }

    # Override lock file location
    export XDG_RUNTIME_DIR="$TMPDIR_TEST"
    source "$PROJECT_DIR/lib/lock.sh"
}

teardown() {
    lock_release 2>/dev/null || true
    rm -rf "$TMPDIR_TEST"
}

@test "lock_acquire succeeds on first call" {
    lock_acquire
}

@test "lock file is created" {
    lock_acquire
    [[ -f "$LOCK_FILE" ]]
}

@test "lock_release closes the descriptor and leaves the file in place" {
    lock_acquire
    lock_release
    [[ -z "$LOCK_FD" ]]
    [[ -f "$LOCK_FILE" ]]
    # and the lock can be taken again
    lock_acquire
}

@test "lock falls back to the state directory without XDG_RUNTIME_DIR" {
    unset XDG_RUNTIME_DIR
    NUDGE_STATE_DIR="$TMPDIR_TEST/state"
    lock_acquire
    [[ "$LOCK_FILE" == "$TMPDIR_TEST/state/nudge-${UID}.lock" ]]
    [[ -f "$LOCK_FILE" ]]
}

@test "lock refuses a symlinked lock path" {
    ln -s /dev/null "$TMPDIR_TEST/nudge-${UID}.lock"
    run ! lock_acquire
}

@test "second lock_acquire fails when lock is held" {
    # Acquire lock in a subshell that holds it
    (
        source "$PROJECT_DIR/lib/lock.sh"
        lock_acquire
        sleep 5
    ) &
    local bg_pid=$!
    sleep 0.5  # Let subshell acquire lock

    # Try to acquire — should fail
    run ! lock_acquire

    kill "$bg_pid" 2>/dev/null || true
    wait "$bg_pid" 2>/dev/null || true
}
