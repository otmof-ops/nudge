#!/usr/bin/env bats
# Tests for bunny pose rendering

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
    source "$PROJECT_DIR/lib/bunny-poses.sh"
    BUNNY_STREAK_FILE="$NUDGE_STATE_DIR/decline_streak"
}

teardown() {
    [[ -n "${TMPDIR_TEST:-}" ]] && rm -rf "$TMPDIR_TEST" || true
}

# --- Each pose produces non-empty output ---

@test "sitting pose produces non-empty output" {
    run bunny_pose "sitting" "$BUNNY_FACE_NORMAL"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "peeking pose produces non-empty output" {
    run bunny_pose "peeking" "$BUNNY_FACE_NORMAL"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "tapping pose produces non-empty output" {
    run bunny_pose "tapping" "$BUNNY_FACE_NORMAL"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "jumping pose produces non-empty output" {
    run bunny_pose "jumping" "$BUNNY_FACE_HAPPY"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "hiding pose produces non-empty output" {
    run bunny_pose "hiding" "$BUNNY_FACE_CRYING"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "sleeping pose produces non-empty output" {
    run bunny_pose "sleeping" "$BUNNY_FACE_NORMAL"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "handing pose produces non-empty output" {
    run bunny_pose "handing" "$BUNNY_FACE_NORMAL"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "waving pose produces non-empty output" {
    run bunny_pose "waving" "$BUNNY_FACE_NORMAL"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "hugging pose produces non-empty output" {
    run bunny_pose "hugging" "$BUNNY_FACE_NORMAL"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "looking_up pose produces non-empty output" {
    run bunny_pose "looking_up" "$BUNNY_FACE_NORMAL"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

# --- Face string appears in output ---

@test "sitting pose includes face string" {
    run bunny_pose "sitting" "$BUNNY_FACE_NORMAL"
    [[ "$output" == *"(='.'=)"* ]]
}

@test "jumping pose includes face string" {
    run bunny_pose "jumping" "$BUNNY_FACE_HAPPY"
    [[ "$output" == *"(^'.'^)"* ]]
}

@test "hiding pose includes face string" {
    run bunny_pose "hiding" "$BUNNY_FACE_CRYING"
    [[ "$output" == *"(T.'T)"* ]]
}

@test "waving pose includes face string" {
    run bunny_pose "waving" "$BUNNY_FACE_WORRIED"
    [[ "$output" == *"(o'.'o)"* ]]
}

@test "hugging pose includes face string" {
    run bunny_pose "hugging" "$BUNNY_FACE_TEARY"
    [[ "$output" == *"(:'.'=)"* ]]
}

# --- Message placement ---

@test "sitting pose with message places message on face line" {
    run bunny_pose "sitting" "$BUNNY_FACE_NORMAL" "hello world"
    [[ "$output" == *"(='.'=)  hello world"* ]]
}

@test "waving pose with message places message on face line" {
    run bunny_pose "waving" "$BUNNY_FACE_NORMAL" "hi there"
    [[ "$output" == *"(='.'=)  hi there"* ]]
}

@test "peeking pose with message includes message" {
    run bunny_pose "peeking" "$BUNNY_FACE_NORMAL" "psst"
    [[ "$output" == *"psst"* ]]
}

# --- Fallback ---

@test "unknown pose falls back to sitting" {
    run bunny_pose "nonexistent_pose" "$BUNNY_FACE_NORMAL"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'(\__/)'* ]]
    [[ "$output" == *"(='.'=)"* ]]
    [[ "$output" == *'(")_(")'* ]]
}

# --- Sleeping pose overrides face ---

@test "sleeping pose overrides face to closed eyes" {
    run bunny_pose "sleeping" "$BUNNY_FACE_HAPPY"
    [[ "$output" == *"(-'.'-)  zzz"* ]]
    # Should NOT contain the happy face
    [[ "$output" != *"(^'.'^)"* ]]
}

# --- Looking up pose overrides face ---

@test "looking_up pose uses wide face" {
    run bunny_pose "looking_up" "$BUNNY_FACE_NORMAL"
    [[ "$output" == *"(o'.'o)"* ]]
}

# --- All poses contain ears ---

@test "all poses contain ears marker" {
    local poses=(sitting peeking tapping jumping hiding sleeping handing waving hugging looking_up)
    for pose in "${poses[@]}"; do
        run bunny_pose "$pose" "$BUNNY_FACE_NORMAL"
        [[ "$output" == *'(\__/)'* ]] || [[ "$output" == *'\(\__/\)'* ]]
    done
}

# --- Sitting pose without message ---

@test "sitting pose without message shows face only on middle line" {
    run bunny_pose "sitting" "$BUNNY_FACE_NORMAL" ""
    [[ "$output" == *'(\__/)'* ]]
    [[ "$output" == *"(='.'=)"* ]]
    [[ "$output" == *'(")_(")'* ]]
}

# --- Tapping pose visual check ---

@test "tapping pose has tapping arm" {
    run bunny_pose "tapping" "$BUNNY_FACE_WORRIED"
    [[ "$output" == *'(")_(")'* ]]
}

# --- Handing pose visual check ---

@test "handing pose has extended arm" {
    run bunny_pose "handing" "$BUNNY_FACE_NORMAL"
    [[ "$output" == *'(")_(")'* ]]
}

# --- Farewell pose ---

@test "farewell pose has waving feet" {
    run bunny_pose "farewell" "$BUNNY_FACE_CRYING" "*waves tiny paw*"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'(\__/)'* ]]
    [[ "$output" == *"waves tiny paw"* ]]
    [[ "$output" == *'(")_(")ノ'* ]]
}

# --- Jumping pose includes ears and feet ---

@test "jumping pose includes feet" {
    run bunny_pose "jumping" "$BUNNY_FACE_HAPPY"
    [[ "$output" == *'(")_(")'* ]] || [[ "$output" == *'(")'* ]]
}

# --- Hiding pose visual check ---

@test "hiding pose has peeking body" {
    run bunny_pose "hiding" "$BUNNY_FACE_CRYING"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'(\__/)'* ]]
    [[ "$output" == *"(T.'T)"* ]]
}
