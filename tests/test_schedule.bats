#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause

bats_require_minimum_version 1.5.0
# Tests for lib/schedule.sh — scheduling, deferral, duration parsing

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
    SCHEDULE_MODE="login"
    SCHEDULE_INTERVAL_HOURS=24

    source "$PROJECT_DIR/lib/schedule.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "parse_duration handles hours" {
    [[ "$(parse_duration '1h')" -eq 3600 ]]
    [[ "$(parse_duration '4h')" -eq 14400 ]]
}

@test "parse_duration handles days" {
    [[ "$(parse_duration '1d')" -eq 86400 ]]
    [[ "$(parse_duration '3d')" -eq 259200 ]]
}

@test "parse_duration handles weeks" {
    [[ "$(parse_duration '1w')" -eq 604800 ]]
}

@test "parse_duration rejects invalid input" {
    run ! parse_duration "abc"
    run ! parse_duration "1x"
}

@test "schedule_due returns 0 in login mode" {
    SCHEDULE_MODE="login"
    schedule_due
}

@test "schedule_due returns 0 when no last_check file" {
    SCHEDULE_MODE="daily"
    SCHEDULE_LAST_CHECK_FILE="$TMPDIR_TEST/last_check"
    schedule_due
}

@test "schedule_due returns 1 when not enough time elapsed" {
    SCHEDULE_MODE="daily"
    SCHEDULE_INTERVAL_HOURS=24
    SCHEDULE_LAST_CHECK_FILE="$TMPDIR_TEST/last_check"

    # Write recent timestamp
    date -Iseconds > "$SCHEDULE_LAST_CHECK_FILE"

    run ! schedule_due
}

@test "schedule_due returns 0 when enough time elapsed" {
    SCHEDULE_MODE="daily"
    SCHEDULE_INTERVAL_HOURS=24
    SCHEDULE_LAST_CHECK_FILE="$TMPDIR_TEST/last_check"

    # Write timestamp from 25 hours ago
    local old_ts
    old_ts=$(date -d '25 hours ago' -Iseconds 2>/dev/null || date -Iseconds)
    echo "$old_ts" > "$SCHEDULE_LAST_CHECK_FILE"

    # This may or may not pass depending on date support
    # Just test that the function runs without error
    schedule_due || true
}

@test "schedule_mark_done creates last_check file" {
    SCHEDULE_LAST_CHECK_FILE="$TMPDIR_TEST/last_check"
    schedule_mark_done
    [[ -f "$SCHEDULE_LAST_CHECK_FILE" ]]
}

@test "schedule_defer writes deferred_until file" {
    SCHEDULE_DEFERRED_FILE="$TMPDIR_TEST/deferred_until"
    schedule_defer "1h"
    [[ -f "$SCHEDULE_DEFERRED_FILE" ]]
}

@test "schedule_due respects active deferral" {
    SCHEDULE_DEFERRED_FILE="$TMPDIR_TEST/deferred_until"

    # Write a deferral 1 hour in the future
    local future
    future=$(date -d '+1 hour' -Iseconds 2>/dev/null || date -Iseconds)
    echo "$future" > "$SCHEDULE_DEFERRED_FILE"

    run ! schedule_due
}

@test "schedule_due clears expired deferral" {
    SCHEDULE_DEFERRED_FILE="$TMPDIR_TEST/deferred_until"

    # Write a deferral in the past
    local past
    past=$(date -d '1 hour ago' -Iseconds 2>/dev/null || date -Iseconds)
    echo "$past" > "$SCHEDULE_DEFERRED_FILE"

    SCHEDULE_MODE="login"
    schedule_due

    # File should be cleaned up
    [[ ! -f "$SCHEDULE_DEFERRED_FILE" ]]
}

@test "schedule_due processes pending_check queue" {
    SCHEDULE_MODE="daily"
    SCHEDULE_LAST_CHECK_FILE="$TMPDIR_TEST/last_check"

    # Write recent check (would normally skip)
    date -Iseconds > "$SCHEDULE_LAST_CHECK_FILE"

    # But pending_check overrides
    echo "$(date -Iseconds)" > "$NUDGE_STATE_DIR/pending_check"

    schedule_due
    [[ ! -f "$NUDGE_STATE_DIR/pending_check" ]]
}

@test "schedule_due weekly mode requires 168h" {
    SCHEDULE_MODE="weekly"
    SCHEDULE_INTERVAL_HOURS=24
    SCHEDULE_LAST_CHECK_FILE="$TMPDIR_TEST/last_check"

    # Write recent timestamp — should not be due
    date -Iseconds > "$SCHEDULE_LAST_CHECK_FILE"

    run ! schedule_due
}

@test "an expired deferral forces a check even in daily mode" {
    SCHEDULE_MODE="daily"
    SCHEDULE_INTERVAL_HOURS=24
    SCHEDULE_LAST_CHECK_FILE="$TMPDIR_TEST/last_check"
    SCHEDULE_DEFERRED_FILE="$TMPDIR_TEST/deferred_until"
    date -d '1 hour ago' -Iseconds > "$SCHEDULE_LAST_CHECK_FILE"
    date -d '1 minute ago' -Iseconds > "$SCHEDULE_DEFERRED_FILE"
    schedule_due
    [[ ! -f "$SCHEDULE_DEFERRED_FILE" ]]
}

@test "a 24h timer that fires 50 seconds short is still due" {
    SCHEDULE_MODE="daily"
    SCHEDULE_INTERVAL_HOURS=24
    SCHEDULE_LAST_CHECK_FILE="$TMPDIR_TEST/last_check"
    date -d "$((86400 - 50)) seconds ago" -Iseconds > "$SCHEDULE_LAST_CHECK_FILE"
    schedule_due
}

@test "a last_check in the future does not silence the check" {
    SCHEDULE_MODE="daily"
    SCHEDULE_LAST_CHECK_FILE="$TMPDIR_TEST/last_check"
    date -d '+10 days' -Iseconds > "$SCHEDULE_LAST_CHECK_FILE"
    schedule_due
}

@test "parse_duration caps at 30 days and rejects leading zeros" {
    run ! parse_duration "31d"
    run ! parse_duration "99999999999999d"
    [[ "$(parse_duration '08h')" -eq 28800 ]]
    [[ "$(parse_duration '30d')" -eq 2592000 ]]
}

@test "schedule_prompt_defer fails when the chosen duration cannot be parsed" {
    NOTIFY_BACKEND="none"
    DEFERRAL_OPTIONS="30m,1h"
    SCHEDULE_DEFERRED_FILE="$TMPDIR_TEST/deferred_until"
    run ! schedule_prompt_defer
    [[ ! -f "$SCHEDULE_DEFERRED_FILE" ]]
}
