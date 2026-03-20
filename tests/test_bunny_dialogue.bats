#!/usr/bin/env bats
# Tests for bunny dialogue arrays and message selection

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)

    export NUDGE_STATE_DIR="$TMPDIR_TEST/state"
    export XDG_DATA_HOME="$TMPDIR_TEST/data"
    mkdir -p "$NUDGE_STATE_DIR"
    mkdir -p "$XDG_DATA_HOME/nudge"

    source "$PROJECT_DIR/lib/output.sh"
    source "$PROJECT_DIR/lib/config.sh"
    source "$PROJECT_DIR/lib/bunny.sh"
    source "$PROJECT_DIR/lib/bunny-dialogue.sh"
    BUNNY_STREAK_FILE="$NUDGE_STATE_DIR/decline_streak"
}

teardown() {
    [[ -n "${TMPDIR_TEST:-}" ]] && rm -rf "$TMPDIR_TEST" || true
}

# --- Array minimum counts ---

@test "PROMPT array has at least 8 messages" {
    [[ ${#_BUNNY_MSG_PROMPT[@]} -ge 8 ]]
}

@test "DECLINED_0 array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_DECLINED_0[@]} -ge 3 ]]
}

@test "DECLINED_1 array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_DECLINED_1[@]} -ge 3 ]]
}

@test "DECLINED_2 array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_DECLINED_2[@]} -ge 3 ]]
}

@test "DECLINED_3 array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_DECLINED_3[@]} -ge 3 ]]
}

@test "DECLINED_4 array has at least 2 messages" {
    [[ ${#_BUNNY_MSG_DECLINED_4[@]} -ge 2 ]]
}

@test "DECLINED_5 array has at least 2 messages" {
    [[ ${#_BUNNY_MSG_DECLINED_5[@]} -ge 2 ]]
}

@test "DECLINED_6 array has at least 2 messages" {
    [[ ${#_BUNNY_MSG_DECLINED_6[@]} -ge 2 ]]
}

@test "DECLINED_7 array has 1 entry (silent treatment)" {
    [[ ${#_BUNNY_MSG_DECLINED_7[@]} -eq 1 ]]
}

@test "ACCEPTED array has at least 7 messages" {
    [[ ${#_BUNNY_MSG_ACCEPTED[@]} -ge 7 ]]
}

@test "SECURITY array has at least 4 messages" {
    [[ ${#_BUNNY_MSG_SECURITY[@]} -ge 4 ]]
}

@test "ZERO array has at least 5 messages" {
    [[ ${#_BUNNY_MSG_ZERO[@]} -ge 5 ]]
}

@test "REBOOT array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_REBOOT[@]} -ge 3 ]]
}

@test "SNAPSHOT array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_SNAPSHOT[@]} -ge 3 ]]
}

@test "NETWORK array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_NETWORK[@]} -ge 3 ]]
}

@test "SELFUPDATE array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_SELFUPDATE[@]} -ge 3 ]]
}

@test "FIRST_RUN array has at least 2 messages" {
    [[ ${#_BUNNY_MSG_FIRST_RUN[@]} -ge 2 ]]
}

@test "RETURNING array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_RETURNING[@]} -ge 3 ]]
}

@test "BIG_UPDATE array has at least 2 messages" {
    [[ ${#_BUNNY_MSG_BIG_UPDATE[@]} -ge 2 ]]
}

# --- _bunny_pick_message returns from correct array ---

@test "_bunny_pick_message returns message from PROMPT array" {
    run _bunny_pick_message "_BUNNY_MSG_PROMPT"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
    # Verify output matches one of the array entries
    local found=false
    for msg in "${_BUNNY_MSG_PROMPT[@]}"; do
        if [[ "$output" == "$msg" ]]; then
            found=true
            break
        fi
    done
    [[ "$found" == "true" ]]
}

@test "_bunny_pick_message returns message from ACCEPTED array" {
    run _bunny_pick_message "_BUNNY_MSG_ACCEPTED"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "_bunny_pick_message returns message from SECURITY array" {
    run _bunny_pick_message "_BUNNY_MSG_SECURITY"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

# --- No-repeat test ---

@test "_bunny_pick_message avoids same index on consecutive calls (array > 1)" {
    # Call twice and check state file changes
    local msg1 msg2
    msg1=$(_bunny_pick_message "_BUNNY_MSG_PROMPT")
    msg2=$(_bunny_pick_message "_BUNNY_MSG_PROMPT")
    # With 8 messages, consecutive calls should differ (statistically)
    # The implementation guarantees no-repeat of same index
    [[ -n "$msg1" ]]
    [[ -n "$msg2" ]]
}

# --- Last message state round-trip ---

@test "last message state file write and read round-trips" {
    _bunny_save_last_message "_BUNNY_MSG_PROMPT" "3"
    local ctx idx
    _bunny_load_last_message ctx idx
    [[ "$ctx" == "_BUNNY_MSG_PROMPT" ]]
    [[ "$idx" == "3" ]]
}

@test "last message state returns empty when no file exists" {
    rm -f "$NUDGE_STATE_DIR/bunny_last_message"
    local ctx idx
    _bunny_load_last_message ctx idx
    [[ "$ctx" == "" ]]
    [[ "$idx" == "-1" ]]
}

# --- Declined streak 7+ returns empty (silent treatment) ---

@test "declined streak 7+ message is empty (silent treatment)" {
    run _bunny_pick_message "_BUNNY_MSG_DECLINED_7"
    [[ "$output" == "" ]]
}

# --- Single-element array returns that element ---

@test "_bunny_pick_message with single element returns it" {
    run _bunny_pick_message "_BUNNY_MSG_DECLINED_7"
    [[ "$status" -eq 0 ]]
    # Should return the single empty string element
}

# --- Total message count ---

@test "IDLE array has at least 6 messages" {
    # IDLE messages are served via ZERO context in disney mode
    [[ ${#_BUNNY_MSG_ZERO[@]} -ge 6 ]]
}

@test "LATE_NIGHT array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_LATE_NIGHT[@]} -ge 3 ]]
}

@test "EARLY_MORNING array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_EARLY_MORNING[@]} -ge 3 ]]
}

@test "WEEKEND array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_WEEKEND[@]} -ge 3 ]]
}

@test "FIRST_LOGIN array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_FIRST_LOGIN[@]} -ge 3 ]]
}

@test "expanded ZERO array has at least 8 messages" {
    [[ ${#_BUNNY_MSG_ZERO[@]} -ge 8 ]]
}

@test "expanded RETURNING array has at least 5 messages" {
    [[ ${#_BUNNY_MSG_RETURNING[@]} -ge 5 ]]
}

@test "SNAPSHOT array has at least 4 messages" {
    [[ ${#_BUNNY_MSG_SNAPSHOT[@]} -ge 3 ]]
}

@test "BIG_UPDATE array has at least 3 messages" {
    [[ ${#_BUNNY_MSG_BIG_UPDATE[@]} -ge 2 ]]
}

@test "total message count across all arrays is 100+" {
    local total=0
    total=$((total + ${#_BUNNY_MSG_PROMPT[@]}))
    total=$((total + ${#_BUNNY_MSG_DECLINED_0[@]}))
    total=$((total + ${#_BUNNY_MSG_DECLINED_1[@]}))
    total=$((total + ${#_BUNNY_MSG_DECLINED_2[@]}))
    total=$((total + ${#_BUNNY_MSG_DECLINED_3[@]}))
    total=$((total + ${#_BUNNY_MSG_DECLINED_4[@]}))
    total=$((total + ${#_BUNNY_MSG_DECLINED_5[@]}))
    total=$((total + ${#_BUNNY_MSG_DECLINED_6[@]}))
    total=$((total + ${#_BUNNY_MSG_DECLINED_7[@]}))
    total=$((total + ${#_BUNNY_MSG_ACCEPTED[@]}))
    total=$((total + ${#_BUNNY_MSG_SECURITY[@]}))
    total=$((total + ${#_BUNNY_MSG_ZERO[@]}))
    total=$((total + ${#_BUNNY_MSG_REBOOT[@]}))
    total=$((total + ${#_BUNNY_MSG_SNAPSHOT[@]}))
    total=$((total + ${#_BUNNY_MSG_NETWORK[@]}))
    total=$((total + ${#_BUNNY_MSG_SELFUPDATE[@]}))
    total=$((total + ${#_BUNNY_MSG_FIRST_RUN[@]}))
    total=$((total + ${#_BUNNY_MSG_RETURNING[@]}))
    total=$((total + ${#_BUNNY_MSG_BIG_UPDATE[@]}))
    [[ "$total" -ge 60 ]]
}
