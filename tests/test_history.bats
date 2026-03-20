#!/usr/bin/env bats
# Tests for lib/history.sh — JSONL history log and viewer

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
    DETECTED_PKGMGR="apt"
    PKG_UPDATES_TOTAL=5
    PKG_UPDATES_SECURITY=2
    PKG_UPDATES_CRITICAL=1
    PKG_UPDATES_FLATPAK=0
    PKG_UPDATES_SNAP=0
    HISTORY_ENABLED=true
    HISTORY_MAX_LINES=500
    declare -A _JSON_DATA=()

    source "$PROJECT_DIR/lib/output.sh"
    source "$PROJECT_DIR/lib/history.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "history_write creates JSONL file" {
    history_write "APPLIED" "test" "2"
    [[ -f "$HISTORY_FILE" ]]
}

@test "history_write appends valid JSONL" {
    history_write "APPLIED" "" "2"
    history_write "DECLINED" "" "1"

    local count
    count=$(wc -l < "$HISTORY_FILE")
    [[ "$count" -eq 2 ]]

    # Each line should contain JSON
    head -1 "$HISTORY_FILE" | grep -q '"outcome":"APPLIED"'
    tail -1 "$HISTORY_FILE" | grep -q '"outcome":"DECLINED"'
}

@test "history_write respects HISTORY_ENABLED=false" {
    HISTORY_ENABLED=false
    history_write "APPLIED" "" "2"
    [[ ! -f "$HISTORY_FILE" ]]
}

@test "history_rotate trims old entries" {
    HISTORY_MAX_LINES=5

    for i in $(seq 1 10); do
        history_write "APPLIED" "run $i" "2"
    done

    local count
    count=$(wc -l < "$HISTORY_FILE")
    [[ "$count" -le 5 ]]
}

@test "history_show table format works" {
    history_write "APPLIED" "" "2"
    history_write "DECLINED" "" "1"

    local output
    output=$(history_show 10 "table")

    echo "$output" | grep -q "TIMESTAMP"
    echo "$output" | grep -q "APPLIED"
    echo "$output" | grep -q "DECLINED"
}

@test "history_show json format dumps JSONL" {
    history_write "APPLIED" "" "2"

    local output
    output=$(history_show 10 "json")

    echo "$output" | grep -q '"outcome":"APPLIED"'
}

@test "history_show with no file prints message" {
    HISTORY_FILE="$TMPDIR_TEST/nonexistent.jsonl"
    local output
    output=$(history_show)
    echo "$output" | grep -q "No history found"
}

@test "history record contains all required fields" {
    _NUDGE_TRIGGER="login"
    history_write "APPLIED" "test detail" "2"

    local record
    record=$(cat "$HISTORY_FILE")

    echo "$record" | grep -q '"timestamp":'
    echo "$record" | grep -q '"nudge_version":"2.0.0"'
    echo "$record" | grep -q '"trigger":"login"'
    echo "$record" | grep -q '"pkg_manager":"apt"'
    echo "$record" | grep -q '"outcome":"APPLIED"'
    echo "$record" | grep -q '"updates_total":5'
    echo "$record" | grep -q '"exit_code":2'
}

@test "history_show --since filters records by date" {
    # Write records with known timestamps
    _NUDGE_TRIGGER="manual"
    declare -A _JSON_DATA=()

    history_write "APPLIED" "old run" "2"

    # Get current date as the since filter
    local today
    today=$(date +%Y-%m-%d)

    local output
    output=$(history_show 100 "json" "$today")

    # Should contain our record from today
    echo "$output" | grep -q '"outcome":"APPLIED"'
}
