#!/usr/bin/env bats
# Tests for lib/output.sh — exit codes, logging, JSON output

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    source "$PROJECT_DIR/lib/output.sh"
}

@test "exit codes are defined and unique" {
    [[ "$EXIT_OK" -eq 0 ]]
    [[ "$EXIT_UPDATES_DECLINED" -eq 1 ]]
    [[ "$EXIT_UPDATES_APPLIED" -eq 2 ]]
    [[ "$EXIT_UPDATES_FAILED" -eq 3 ]]
    [[ "$EXIT_DISABLED" -eq 4 ]]
    [[ "$EXIT_NETWORK_FAIL" -eq 5 ]]
    [[ "$EXIT_PKG_LOCK" -eq 6 ]]
    [[ "$EXIT_ALREADY_RUNNING" -eq 7 ]]
    [[ "$EXIT_NO_BACKEND" -eq 8 ]]
    [[ "$EXIT_DEFERRED" -eq 9 ]]
    [[ "$EXIT_CONFIG_ERROR" -eq 10 ]]
    [[ "$EXIT_INTERRUPTED" -eq 11 ]]
    [[ "$EXIT_SNAPSHOT_FAILED" -eq 12 ]]
    [[ "$EXIT_REBOOT_PENDING" -eq 13 ]]
}

@test "exit_reason returns correct strings" {
    [[ "$(exit_reason 0)" == "OK" ]]
    [[ "$(exit_reason 2)" == "UPDATES_APPLIED" ]]
    [[ "$(exit_reason 5)" == "NETWORK_FAIL" ]]
    [[ "$(exit_reason 99)" == "UNKNOWN" ]]
}

@test "output_init sets log threshold from LOG_LEVEL" {
    LOG_LEVEL="debug"
    output_init
    [[ "$_LOG_THRESHOLD" -eq "$LOG_LEVEL_DEBUG" ]]

    LOG_LEVEL="error"
    output_init
    [[ "$_LOG_THRESHOLD" -eq "$LOG_LEVEL_ERROR" ]]
}

@test "output_init enables verbose mode" {
    _VERBOSE_FLAG=true
    output_init
    [[ "$_VERBOSE_MODE" == "true" ]]
    [[ "$_LOG_THRESHOLD" -eq "$LOG_LEVEL_DEBUG" ]]
    _VERBOSE_FLAG=false
}

@test "output_init enables JSON mode" {
    _JSON_FLAG=true
    output_init
    [[ "$_JSON_MODE" == "true" ]]
    _JSON_FLAG=false
}

@test "log_info writes to LOG_FILE" {
    local tmplog
    tmplog=$(mktemp)
    LOG_FILE="$tmplog"
    DRY_RUN=false
    _JSON_MODE=false
    _LOG_THRESHOLD="$LOG_LEVEL_INFO"

    log_info "test message"

    grep -q "test message" "$tmplog"
    rm -f "$tmplog"
}

@test "log_debug suppressed at info threshold" {
    local tmplog
    tmplog=$(mktemp)
    LOG_FILE="$tmplog"
    DRY_RUN=false
    _JSON_MODE=false
    _LOG_THRESHOLD="$LOG_LEVEL_INFO"

    log_debug "should not appear"

    ! grep -q "should not appear" "$tmplog"
    rm -f "$tmplog"
}

@test "json_set and json_emit produce valid JSON" {
    _JSON_MODE=true
    NUDGE_VERSION="2.0.0"

    json_set "pkg_manager" "apt"
    json_set "updates_total" "5"
    json_set "updates_security" "2"
    json_set "updates_critical" "1"
    json_set "updates_flatpak" "0"
    json_set "updates_snap" "0"
    json_set "reboot_required" "false"
    json_set "snapshot_id" "null"
    json_set "deferred" "false"
    json_set "duration_seconds" "3"
    json_set "packages" "[]"

    local output
    output=$(json_emit 2)

    # Check key fields
    echo "$output" | grep -q '"nudge_version": "2.0.0"'
    echo "$output" | grep -q '"exit_code": 2'
    echo "$output" | grep -q '"exit_reason": "UPDATES_APPLIED"'
    echo "$output" | grep -q '"pkg_manager": "apt"'

    _JSON_MODE=false
}

@test "json_emit suppressed when not in JSON mode" {
    _JSON_MODE=false
    local output
    output=$(json_emit 0)
    [[ -z "$output" ]]
}
