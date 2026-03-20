#!/usr/bin/env bats
# Tests for bunny personality engine

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)

    # Minimal stubs for dependencies
    export NUDGE_STATE_DIR="$TMPDIR_TEST/state"
    export XDG_DATA_HOME="$TMPDIR_TEST/data"
    mkdir -p "$NUDGE_STATE_DIR"
    mkdir -p "$XDG_DATA_HOME/nudge"

    # Source output.sh for log stubs (needed by config.sh)
    source "$PROJECT_DIR/lib/output.sh"
    # Source config.sh for CONFIG_DEFAULTS/CONFIG_TYPES
    source "$PROJECT_DIR/lib/config.sh"
    # Source bunny modules (must come after NUDGE_STATE_DIR is set)
    source "$PROJECT_DIR/lib/bunny-poses.sh"
    source "$PROJECT_DIR/lib/bunny-dialogue.sh"
    source "$PROJECT_DIR/lib/bunny.sh"
    # Override streak file and state paths to use our test state dir
    BUNNY_STREAK_FILE="$NUDGE_STATE_DIR/decline_streak"
    _BUNNY_INSTALL_DATE_FILE="$NUDGE_STATE_DIR/bunny_install_date"
    _BUNNY_LAST_SEEN_FILE="$NUDGE_STATE_DIR/bunny_last_seen"
}

teardown() {
    [[ -n "${TMPDIR_TEST:-}" ]] && rm -rf "$TMPDIR_TEST" || true
}

# --- Streak tests ---

@test "bunny_get_streak returns 0 when no file exists" {
    rm -f "$BUNNY_STREAK_FILE"
    run bunny_get_streak
    [[ "$status" -eq 0 ]]
    [[ "$output" == "0" ]]
}

@test "bunny_increment_streak creates file with value 1" {
    rm -f "$BUNNY_STREAK_FILE"
    bunny_increment_streak
    local val
    val=$(cat "$BUNNY_STREAK_FILE")
    [[ "$val" == "1" ]]
}

@test "bunny_increment_streak increments existing value" {
    echo "3" > "$BUNNY_STREAK_FILE"
    bunny_increment_streak
    local val
    val=$(cat "$BUNNY_STREAK_FILE")
    [[ "$val" == "4" ]]
}

@test "bunny_reset_streak resets to 0" {
    echo "5" > "$BUNNY_STREAK_FILE"
    bunny_reset_streak
    run bunny_get_streak
    [[ "$output" == "0" ]]
}

@test "bunny_get_streak returns 0 for non-numeric content" {
    echo "garbage" > "$BUNNY_STREAK_FILE"
    run bunny_get_streak
    [[ "$output" == "0" ]]
}

@test "streak file uses atomic write (temp file pattern)" {
    bunny_increment_streak
    [[ -f "$BUNNY_STREAK_FILE" ]]
    # No stale temp files left behind
    local temps
    temps=$(find "$(dirname "$BUNNY_STREAK_FILE")" -name 'decline_streak.*' 2>/dev/null | wc -l)
    [[ "$temps" -eq 0 ]]
}

# --- Face tests (disney mode) ---

@test "bunny_face returns normal face for prompt streak 0" {
    BUNNY_PERSONALITY="disney"
    run bunny_face "prompt" 0
    [[ "$output" == "(='.'=)" ]]
}

@test "bunny_face returns normal face for prompt streak 1-2" {
    BUNNY_PERSONALITY="disney"
    run bunny_face "prompt" 1
    [[ "$output" == "(='.'=)" ]]
    run bunny_face "prompt" 2
    [[ "$output" == "(='.'=)" ]]
}

@test "bunny_face returns sweat face for prompt streak 3" {
    BUNNY_PERSONALITY="disney"
    run bunny_face "prompt" 3
    [[ "$output" == "(;'.'=)" ]]
}

@test "bunny_face returns teary face for prompt streak 4" {
    BUNNY_PERSONALITY="disney"
    run bunny_face "prompt" 4
    [[ "$output" == "(:'.'=)" ]]
}

@test "bunny_face returns crying face for prompt streak 5+" {
    BUNNY_PERSONALITY="disney"
    run bunny_face "prompt" 5
    [[ "$output" == "(T.'T)" ]]
    run bunny_face "prompt" 10
    [[ "$output" == "(T.'T)" ]]
}

@test "bunny_face returns happy face for accepted" {
    BUNNY_PERSONALITY="disney"
    run bunny_face "accepted" 0
    [[ "$output" == "(^'.'^)" ]]
}

@test "bunny_face returns worried face for reboot" {
    BUNNY_PERSONALITY="disney"
    run bunny_face "reboot" 0
    [[ "$output" == "(o'.'o)" ]]
}

@test "bunny_face returns normal face for zero updates" {
    BUNNY_PERSONALITY="disney"
    run bunny_face "zero" 0
    [[ "$output" == "(='.'=)" ]]
}

# --- Face tests (classic mode) ---

@test "bunny_face always returns normal face in classic mode" {
    BUNNY_PERSONALITY="classic"
    run bunny_face "prompt" 5
    [[ "$output" == "(='.'=)" ]]
    run bunny_face "accepted" 0
    [[ "$output" == "(='.'=)" ]]
    run bunny_face "reboot" 0
    [[ "$output" == "(='.'=)" ]]
}

# --- Message tests (disney mode) ---

@test "bunny_message returns disney prompt message (from array)" {
    BUNNY_PERSONALITY="disney"
    run bunny_message "prompt"
    [[ -n "$output" ]]
}

@test "bunny_message returns disney accepted message (from array)" {
    BUNNY_PERSONALITY="disney"
    run bunny_message "accepted"
    [[ -n "$output" ]]
}

@test "bunny_message returns disney security message (from array)" {
    BUNNY_PERSONALITY="disney"
    run bunny_message "security"
    [[ -n "$output" ]]
}

@test "bunny_message returns disney zero message (from array)" {
    BUNNY_PERSONALITY="disney"
    run bunny_message "zero"
    [[ -n "$output" ]]
}

@test "bunny_message returns disney reboot message (from array)" {
    BUNNY_PERSONALITY="disney"
    run bunny_message "reboot"
    [[ -n "$output" ]]
}

@test "bunny_message returns disney snapshot message (from array)" {
    BUNNY_PERSONALITY="disney"
    run bunny_message "snapshot"
    [[ -n "$output" ]]
}

@test "bunny_message returns disney selfupdate message (from array)" {
    BUNNY_PERSONALITY="disney"
    run bunny_message "selfupdate"
    [[ -n "$output" ]]
}

@test "bunny_message returns disney network message (from array)" {
    BUNNY_PERSONALITY="disney"
    run bunny_message "network"
    [[ -n "$output" ]]
}

@test "bunny_message declined streak 0 returns non-empty" {
    BUNNY_PERSONALITY="disney"
    echo "0" > "$BUNNY_STREAK_FILE"
    run bunny_message "declined"
    [[ -n "$output" ]]
}

@test "bunny_message declined streak 1 returns non-empty" {
    BUNNY_PERSONALITY="disney"
    echo "1" > "$BUNNY_STREAK_FILE"
    run bunny_message "declined"
    [[ -n "$output" ]]
}

@test "bunny_message declined streak 2 returns non-empty" {
    BUNNY_PERSONALITY="disney"
    echo "2" > "$BUNNY_STREAK_FILE"
    run bunny_message "declined"
    [[ -n "$output" ]]
}

@test "bunny_message declined streak 3 returns non-empty" {
    BUNNY_PERSONALITY="disney"
    echo "3" > "$BUNNY_STREAK_FILE"
    run bunny_message "declined"
    [[ -n "$output" ]]
}

@test "bunny_message declined streak 4 returns non-empty" {
    BUNNY_PERSONALITY="disney"
    echo "4" > "$BUNNY_STREAK_FILE"
    run bunny_message "declined"
    [[ -n "$output" ]]
}

# --- Message tests (classic mode) ---

@test "bunny_message returns classic messages" {
    BUNNY_PERSONALITY="classic"
    run bunny_message "prompt"
    [[ "$output" == "Updates available" ]]
    run bunny_message "accepted"
    [[ "$output" == "Updates applied successfully" ]]
    run bunny_message "reboot"
    [[ "$output" == "A system reboot is required" ]]
}

# --- Dialog tests ---

@test "bunny_dialog produces output with face and message" {
    BUNNY_PERSONALITY="disney"
    echo "0" > "$BUNNY_STREAK_FILE"
    run bunny_dialog "prompt"
    [[ "$output" == *'(\__/)'* ]]
    [[ "$output" == *"(='.'=)"* ]]
    [[ "$output" == *'(")_(")'* ]]
    # Message is now randomly selected from array
    [[ -n "$output" ]]
}

@test "bunny_dialog classic mode produces output" {
    BUNNY_PERSONALITY="classic"
    run bunny_dialog "accepted"
    [[ "$output" == *'(\__/)'* ]]
    [[ "$output" == *"(='.'=)"* ]]
    [[ "$output" == *"Updates applied successfully"* ]]
}

@test "all contexts produce non-empty messages in disney mode" {
    BUNNY_PERSONALITY="disney"
    echo "0" > "$BUNNY_STREAK_FILE"
    local contexts=(prompt declined accepted security zero reboot snapshot selfupdate network)
    for ctx in "${contexts[@]}"; do
        run bunny_message "$ctx"
        [[ -n "$output" ]]
    done
}

@test "all contexts produce non-empty messages in classic mode" {
    BUNNY_PERSONALITY="classic"
    local contexts=(prompt declined accepted security zero reboot snapshot selfupdate network)
    for ctx in "${contexts[@]}"; do
        run bunny_message "$ctx"
        [[ -n "$output" ]]
    done
}

# --- bunny_render tests ---

@test "bunny_render produces output for prompt context" {
    BUNNY_PERSONALITY="disney"
    echo "0" > "$BUNNY_STREAK_FILE"
    echo "2026-01-01T00:00:00+00:00" > "$_BUNNY_INSTALL_DATE_FILE"
    echo "$(date -Iseconds)" > "$_BUNNY_LAST_SEEN_FILE"
    run bunny_render "prompt" "nudge: 5 updates"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "bunny_render produces output for accepted context" {
    BUNNY_PERSONALITY="disney"
    echo "0" > "$BUNNY_STREAK_FILE"
    echo "2026-01-01T00:00:00+00:00" > "$_BUNNY_INSTALL_DATE_FILE"
    run bunny_render "accepted"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "bunny_render produces output for security context" {
    BUNNY_PERSONALITY="disney"
    run bunny_render "security"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "bunny_render produces output for zero context" {
    BUNNY_PERSONALITY="disney"
    run bunny_render "zero"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "bunny_render produces output for reboot context" {
    BUNNY_PERSONALITY="disney"
    run bunny_render "reboot"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "bunny_render produces output for network context" {
    BUNNY_PERSONALITY="disney"
    run bunny_render "network"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "bunny_render classic mode matches legacy format" {
    BUNNY_PERSONALITY="classic"
    run bunny_render "prompt"
    [[ "$output" == *'(\__/)'* ]]
    [[ "$output" == *"(='.'=)"* ]]
    [[ "$output" == *"Updates available"* ]]
    [[ "$output" == *'(")_(")'* ]]
}

@test "bunny_render classic mode with detail" {
    BUNNY_PERSONALITY="classic"
    run bunny_render "prompt" "nudge: 5 updates"
    [[ "$output" == *"nudge: 5 updates"* ]]
}

# --- Season detection tests ---

@test "_bunny_detect_season returns a valid season string" {
    echo "2026-01-01T00:00:00+00:00" > "$_BUNNY_INSTALL_DATE_FILE"
    run _bunny_detect_season
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^(christmas|halloween|summer|winter|birthday|none)$ ]]
}

# --- Season decoration tests ---

@test "_bunny_season_decorate passes through for none season" {
    run _bunny_season_decorate "line1
line2
line3" "none"
    [[ "$output" == *"line1"* ]]
    [[ "$output" == *"line3"* ]]
}

@test "_bunny_season_decorate adds emoji for christmas" {
    run _bunny_season_decorate "line1
line2
line3" "christmas"
    [[ "$output" == *"line1"* ]]
}

# --- Special context detection tests ---

@test "_bunny_detect_special_context returns first_run when no install file" {
    rm -f "$_BUNNY_INSTALL_DATE_FILE"
    run _bunny_detect_special_context "prompt" "0"
    [[ "$output" == "first_run" ]]
}

@test "_bunny_detect_special_context returns big_update for 50+ packages" {
    echo "2026-01-01T00:00:00+00:00" > "$_BUNNY_INSTALL_DATE_FILE"
    echo "$(date -Iseconds)" > "$_BUNNY_LAST_SEEN_FILE"
    run _bunny_detect_special_context "prompt" "50"
    [[ "$output" == "big_update" ]]
}

@test "_bunny_detect_special_context passes through non-prompt context" {
    run _bunny_detect_special_context "accepted" "100"
    [[ "$output" == "accepted" ]]
}

@test "_bunny_detect_special_context returns returning after 7+ days" {
    echo "2026-01-01T00:00:00+00:00" > "$_BUNNY_INSTALL_DATE_FILE"
    local old_date
    old_date=$(date -d "8 days ago" -Iseconds 2>/dev/null) || old_date=""
    if [[ -n "$old_date" ]]; then
        echo "$old_date" > "$_BUNNY_LAST_SEEN_FILE"
        run _bunny_detect_special_context "prompt" "5"
        [[ "$output" == "returning" ]]
    else
        skip "date -d not available"
    fi
}

# --- bunny_init tests ---

@test "bunny_init creates install_date file" {
    rm -f "$_BUNNY_INSTALL_DATE_FILE"
    bunny_init
    [[ -f "$_BUNNY_INSTALL_DATE_FILE" ]]
}

@test "bunny_init creates last_seen file" {
    rm -f "$_BUNNY_LAST_SEEN_FILE"
    bunny_init
    [[ -f "$_BUNNY_LAST_SEEN_FILE" ]]
}

@test "bunny_init does not overwrite existing install_date" {
    echo "2025-01-01T00:00:00+00:00" > "$_BUNNY_INSTALL_DATE_FILE"
    bunny_init
    local val
    val=$(cat "$_BUNNY_INSTALL_DATE_FILE")
    [[ "$val" == "2025-01-01T00:00:00+00:00" ]]
}

# --- Pose selection tests ---

@test "_bunny_select_pose returns sitting for prompt streak 0" {
    run _bunny_select_pose "prompt" 0
    [[ "$output" == "sitting" ]]
}

@test "_bunny_select_pose returns peeking for prompt streak 2" {
    run _bunny_select_pose "prompt" 2
    [[ "$output" == "peeking" ]]
}

@test "_bunny_select_pose returns tapping for prompt streak 4" {
    run _bunny_select_pose "prompt" 4
    [[ "$output" == "tapping" ]]
}

@test "_bunny_select_pose returns hiding for prompt streak 6+" {
    run _bunny_select_pose "prompt" 6
    [[ "$output" == "hiding" ]]
}

@test "_bunny_select_pose returns jumping for accepted" {
    run _bunny_select_pose "accepted" 0
    [[ "$output" == "jumping" ]]
}

@test "_bunny_select_pose returns sleeping for zero" {
    run _bunny_select_pose "zero" 0
    [[ "$output" == "sleeping" ]]
}

@test "_bunny_select_pose returns looking_up for first_run" {
    run _bunny_select_pose "first_run" 0
    [[ "$output" == "looking_up" ]]
}

@test "_bunny_select_pose returns waving for returning" {
    run _bunny_select_pose "returning" 0
    [[ "$output" == "waving" ]]
}

@test "_bunny_select_pose returns hugging for network" {
    run _bunny_select_pose "network" 0
    [[ "$output" == "hugging" ]]
}

@test "_bunny_select_pose returns handing for snapshot" {
    run _bunny_select_pose "snapshot" 0
    [[ "$output" == "handing" ]]
}

# --- Declined streak 7+ silent treatment via bunny_render ---

@test "bunny_message declined streak 7 returns empty (silent treatment)" {
    BUNNY_PERSONALITY="disney"
    echo "7" > "$BUNNY_STREAK_FILE"
    run bunny_message "declined"
    [[ -z "$output" ]]
}

# --- bunny_dialog backward compatibility ---

@test "_bunny_detect_time_context returns valid context" {
    run _bunny_detect_time_context
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^(late_night|early_morning|weekend|none)$ ]]
}

@test "bunny_dialog still works as deprecated wrapper" {
    BUNNY_PERSONALITY="disney"
    echo "0" > "$BUNNY_STREAK_FILE"
    run bunny_dialog "prompt"
    [[ "$output" == *'(\__/)'* ]]
    [[ "$output" == *'(")_(")'* ]]
}
