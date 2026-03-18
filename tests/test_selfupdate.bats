#!/usr/bin/env bats
# Tests for lib/selfupdate.sh — version comparison and self-update

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)

    # Stubs
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }

    NUDGE_STATE_DIR="$TMPDIR_TEST"
    NUDGE_VERSION="2.0.0"
    SELF_UPDATE_CHECK=true

    source "$PROJECT_DIR/lib/selfupdate.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "version_gt: 2.1.0 > 2.0.0" {
    version_gt "2.1.0" "2.0.0"
}

@test "version_gt: 2.0.1 > 2.0.0" {
    version_gt "2.0.1" "2.0.0"
}

@test "version_gt: 3.0.0 > 2.9.9" {
    version_gt "3.0.0" "2.9.9"
}

@test "version_gt: 2.0.0 not > 2.0.0 (equal)" {
    ! version_gt "2.0.0" "2.0.0"
}

@test "version_gt: 1.9.9 not > 2.0.0" {
    ! version_gt "1.9.9" "2.0.0"
}

@test "version_gt handles v prefix" {
    version_gt "v2.1.0" "v2.0.0"
}

@test "selfupdate_check_due returns 0 when no state file" {
    SELFUPDATE_STATE_FILE="$TMPDIR_TEST/nonexistent"
    selfupdate_check_due
}

@test "selfupdate_check_due returns 1 when checked recently" {
    SELFUPDATE_STATE_FILE="$TMPDIR_TEST/selfupdate_check"
    date -Iseconds > "$SELFUPDATE_STATE_FILE"
    ! selfupdate_check_due
}

@test "selfupdate_check_due returns 1 when disabled" {
    SELF_UPDATE_CHECK=false
    ! selfupdate_check_due
}

@test "selfupdate_mark_checked creates state file" {
    SELFUPDATE_STATE_FILE="$TMPDIR_TEST/selfupdate_check"
    selfupdate_mark_checked
    [[ -f "$SELFUPDATE_STATE_FILE" ]]
}
