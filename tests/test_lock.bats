#!/usr/bin/env bats
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

@test "lock_release removes lock file" {
    lock_acquire
    lock_release
    [[ ! -f "$LOCK_FILE" ]]
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
    ! lock_acquire

    kill "$bg_pid" 2>/dev/null || true
    wait "$bg_pid" 2>/dev/null || true
}
