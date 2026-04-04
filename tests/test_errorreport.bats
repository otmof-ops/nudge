#!/usr/bin/env bats
# Tests for lib/errorreport.sh

setup() {
    TMPDIR_TEST=$(mktemp -d)
    export NUDGE_STATE_DIR="$TMPDIR_TEST/state"
    export CRASH_REPORT_DIR="$NUDGE_STATE_DIR/crash-reports"
    export NUDGE_VERSION="2.0.0"
    export _NUDGE_TRIGGER="manual"
    export HISTORY_FILE="$NUDGE_STATE_DIR/history.jsonl"
    export LOG_FILE=""
    export DETECTED_PKGMGR="apt"
    export NOTIFY_BACKEND="zenity"

    # Source dependencies
    source "$BATS_TEST_DIRNAME/../lib/output.sh"
    source "$BATS_TEST_DIRNAME/../lib/errorreport.sh"

    mkdir -p "$NUDGE_STATE_DIR"

    # Set config vars the report collects
    ENABLED=true
    DELAY=45
    CHECK_SECURITY=true
    AUTO_DISMISS=0
    NETWORK_HOST="archive.ubuntu.com"
    NETWORK_TIMEOUT=5
    NETWORK_RETRIES=2
    OFFLINE_MODE="skip"
    NOTIFICATION_BACKEND="auto"
    SCHEDULE_MODE="login"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "_is_error_exit returns 1 for EXIT_OK (0)" {
    ! _is_error_exit 0
}

@test "_is_error_exit returns 1 for EXIT_UPDATES_DECLINED (1)" {
    ! _is_error_exit 1
}

@test "_is_error_exit returns 1 for EXIT_UPDATES_APPLIED (2)" {
    ! _is_error_exit 2
}

@test "_is_error_exit returns 1 for EXIT_DISABLED (4)" {
    ! _is_error_exit 4
}

@test "_is_error_exit returns 1 for EXIT_DEFERRED (9)" {
    ! _is_error_exit 9
}

@test "_is_error_exit returns 0 for EXIT_UPDATES_FAILED (3)" {
    _is_error_exit 3
}

@test "_is_error_exit returns 0 for EXIT_NETWORK_FAIL (5)" {
    _is_error_exit 5
}

@test "_is_error_exit returns 0 for EXIT_PKG_LOCK (6)" {
    _is_error_exit 6
}

@test "_is_error_exit returns 0 for EXIT_NO_BACKEND (8)" {
    _is_error_exit 8
}

@test "_is_error_exit returns 0 for EXIT_CONFIG_ERROR (10)" {
    _is_error_exit 10
}

@test "_is_error_exit returns 0 for EXIT_INTERRUPTED (11)" {
    _is_error_exit 11
}

@test "_is_error_exit returns 0 for EXIT_SNAPSHOT_FAILED (12)" {
    _is_error_exit 12
}

@test "errorreport_write creates crash report for error exit" {
    local result
    result=$(errorreport_write 5 "test network fail")
    [[ -f "$result" ]]
    grep -q "exit_code: 5" "$result"
    grep -q "exit_reason: NETWORK_FAIL" "$result"
    grep -q "context: test network fail" "$result"
}

@test "errorreport_write skips normal exits" {
    local result
    result=$(errorreport_write 0 "")
    [[ -z "$result" ]]
    [[ ! -d "$CRASH_REPORT_DIR" ]] || [[ $(find "$CRASH_REPORT_DIR" -name "crash-*.txt" 2>/dev/null | wc -l) -eq 0 ]]
}

@test "errorreport_write includes system info" {
    local result
    result=$(errorreport_write 10 "config error")
    grep -q "kernel:" "$result"
    grep -q "bash:" "$result"
    grep -q "pkg_manager: apt" "$result"
    grep -q "notify_backend: zenity" "$result"
}

@test "errorreport_write includes sanitized config" {
    local result
    result=$(errorreport_write 3 "upgrade failed")
    grep -q "ENABLED=true" "$result"
    grep -q "DELAY=45" "$result"
    grep -q "UPDATE_COMMAND=\[redacted\]" "$result"
    grep -q "LOG_FILE=\[redacted\]" "$result"
}

@test "errorreport_write includes nudge version" {
    local result
    result=$(errorreport_write 8 "no backend")
    grep -q "nudge_version: 2.0.0" "$result"
}

@test "errorreport_list shows reports" {
    errorreport_write 5 "fail 1" >/dev/null
    errorreport_write 3 "fail 2" >/dev/null
    local output
    output=$(errorreport_list)
    [[ "$output" == *"NETWORK_FAIL"* ]]
    [[ "$output" == *"UPDATES_FAILED"* ]]
}

@test "errorreport_list json format" {
    errorreport_write 6 "pkg lock" >/dev/null
    local output
    output=$(errorreport_list 10 "json")
    [[ "$output" == "["* ]]
    [[ "$output" == *"PKG_LOCK"* ]]
}

@test "errorreport_show displays latest report" {
    errorreport_write 11 "interrupted" >/dev/null
    local output
    output=$(errorreport_show)
    [[ "$output" == *"exit_code: 11"* ]]
    [[ "$output" == *"INTERRUPTED"* ]]
}

@test "errorreport_show returns 1 when no reports" {
    ! errorreport_show
}

@test "errorreport_clear removes all reports" {
    errorreport_write 5 "fail" >/dev/null
    errorreport_write 3 "fail" >/dev/null
    local output
    output=$(errorreport_clear)
    [[ "$output" == *"Cleared 2"* ]]
    [[ $(find "$CRASH_REPORT_DIR" -name "crash-*.txt" 2>/dev/null | wc -l) -eq 0 ]]
}

@test "crash report rotation keeps max reports" {
    CRASH_REPORT_MAX=3
    for i in {1..5}; do
        errorreport_write 5 "fail $i" >/dev/null
        sleep 1  # distinct timestamps
    done
    local count
    count=$(find "$CRASH_REPORT_DIR" -name "crash-*.txt" -type f | wc -l)
    [[ "$count" -le 4 ]]  # may be 3 or 4 depending on timing
}

@test "_build_issue_body produces markdown" {
    local report
    report=$(errorreport_write 10 "config error")
    local body
    body=$(_build_issue_body "$report")
    [[ "$body" == *"## Automated Crash Report"* ]]
    [[ "$body" == *"Exit Code"* ]]
    [[ "$body" == *"System Information"* ]]
    [[ "$body" == *"Sanitized Config"* ]]
}

@test "errorreport_file_issue requires gh CLI" {
    errorreport_write 5 "fail" >/dev/null
    # Remove gh from PATH entirely
    local mock_bin
    mock_bin=$(mktemp -d)
    local old_path="$PATH"
    PATH="$mock_bin:/usr/bin:/bin"
    # Ensure no gh exists
    rm -f "$mock_bin/gh" 2>/dev/null || true
    if command -v gh &>/dev/null; then
        # gh is in /usr/bin or /bin — skip this test
        PATH="$old_path"
        skip "gh is installed in system path"
    fi
    local output
    output=$(errorreport_file_issue 2>&1) || true
    PATH="$old_path"
    rm -rf "$mock_bin"
    [[ "$output" == *"GitHub CLI"* ]] || [[ "$output" == *"gh"* ]]
}
