#!/usr/bin/env bats
# Tests for lib/safety.sh — reboot detection and snapshots

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)

    # Stubs
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }
    json_set() { :; }
    notify_reboot() { return 1; }

    NUDGE_STATE_DIR="$TMPDIR_TEST"
    REBOOT_CHECK=true
    SNAPSHOT_ENABLED=false

    source "$PROJECT_DIR/lib/safety.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "safety_reboot_check returns 1 when REBOOT_CHECK=false" {
    REBOOT_CHECK=false
    ! safety_reboot_check
}

@test "safety_check_pending_reboot returns 1 when no file" {
    ! safety_check_pending_reboot
}

@test "safety_check_pending_reboot returns 0 when file exists" {
    echo "$(date)" > "$TMPDIR_TEST/reboot_pending"
    safety_check_pending_reboot
}

@test "safety_handle_reboot creates pending file when reboot needed" {
    # Override reboot check to return true
    safety_reboot_check() { return 0; }

    safety_handle_reboot
    [[ -f "$TMPDIR_TEST/reboot_pending" ]]
}

@test "safety_snapshot returns 0 when disabled" {
    SNAPSHOT_ENABLED=false
    safety_snapshot
}

@test "safety_snapshot fails when enabled but no tool available" {
    SNAPSHOT_ENABLED=true
    SNAPSHOT_TOOL="auto"

    # Override commands to not be found
    command() { return 1; }

    ! safety_snapshot
}
