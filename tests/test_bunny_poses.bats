#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
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

# --- Every pose is three lines with ears on top and feet at the bottom ---

@test "every pose renders three lines with ears and feet" {
    local poses=(sitting peeking tapping jumping hiding sleeping handing waving hugging looking_up farewell)
    local pose
    for pose in "${poses[@]}"; do
        run bunny_pose "$pose" "$BUNNY_FACE_NORMAL"
        [[ "$status" -eq 0 ]]
        [[ "${#lines[@]}" -eq 3 ]]
        [[ "${lines[0]}" == *'(\__/)'* ]]
        [[ "${lines[2]}" == *'(")_(")'* ]]
    done
}

@test "the art is plain ASCII, safe for dialogs and terminals" {
    local poses=(sitting peeking tapping jumping hiding sleeping handing waving hugging looking_up farewell)
    local pose
    for pose in "${poses[@]}"; do
        run bunny_pose "$pose" "$BUNNY_FACE_HAPPY" "hi"
        [[ "$output" =~ ^[[:print:][:space:]]+$ ]]
        [[ ! "$output" =~ [^[:ascii:]] ]]
    done
}

# --- Faces land inside the head ---

@test "bunny_head wraps a face in the cheeks" {
    [[ "$(bunny_head "$BUNNY_FACE_NORMAL")" == "(='.'=)" ]]
    [[ "$(bunny_head "$BUNNY_FACE_HAPPY")" == "(=^.^=)" ]]
}

@test "sitting pose includes the face" {
    run bunny_pose "sitting" "$BUNNY_FACE_NORMAL"
    [[ "$output" == *"(='.'=)"* ]]
}

@test "jumping pose raises both paws and includes the face" {
    run bunny_pose "jumping" "$BUNNY_FACE_HAPPY"
    [[ "${lines[0]}" == *'\(\__/)/'* ]]
    [[ "$output" == *"(=^.^=)"* ]]
}

@test "hiding pose covers the face with paws" {
    run bunny_pose "hiding" "$BUNNY_FACE_CRYING"
    [[ "$output" == *'(")T.T(")'* ]]
}

@test "waving pose includes face string" {
    run bunny_pose "waving" "$BUNNY_FACE_WORRIED"
    [[ "${lines[0]}" == *'(\__/)/'* ]]
    [[ "$output" == *"(=o.o=)"* ]]
}

@test "hugging pose wraps the arms around the head" {
    run bunny_pose "hugging" "$BUNNY_FACE_TEARY"
    [[ "$output" == *"((=;.;=))"* ]]
}

# --- Message placement ---

@test "sitting pose with message places message on face line" {
    run bunny_pose "sitting" "$BUNNY_FACE_NORMAL" "hello world"
    [[ "${lines[1]}" == *"(='.'=)  hello world" ]]
}

@test "waving pose with message places message on face line" {
    run bunny_pose "waving" "$BUNNY_FACE_NORMAL" "hi there"
    [[ "${lines[1]}" == *"(='.'=)  hi there" ]]
}

@test "peeking pose with message includes message" {
    run bunny_pose "peeking" "$BUNNY_FACE_NORMAL" "psst"
    [[ "${lines[0]}" == *'|(\__/)'* ]]
    [[ "$output" == *"psst"* ]]
}

# --- Fallback ---

@test "unknown pose falls back to sitting" {
    run bunny_pose "nonexistent_pose" "$BUNNY_FACE_NORMAL"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$(bunny_pose sitting "$BUNNY_FACE_NORMAL")" ]]
}

# --- Overrides ---

@test "sleeping pose overrides face to closed eyes with zzz" {
    run bunny_pose "sleeping" "$BUNNY_FACE_HAPPY"
    [[ "$output" == *"(=-.-=) zzz"* ]]
    [[ "$output" != *"^.^"* ]]
}

@test "looking_up pose uses wide eyes" {
    run bunny_pose "looking_up" "$BUNNY_FACE_NORMAL"
    [[ "$output" == *"(=O.O=)"* ]]
}

# --- Pose details ---

@test "tapping pose has a tapping paw" {
    run bunny_pose "tapping" "$BUNNY_FACE_WORRIED"
    [[ "${lines[1]}" == *"(=o.o=)_/"* ]]
}

@test "handing pose holds out a star" {
    run bunny_pose "handing" "$BUNNY_FACE_NORMAL"
    [[ "${lines[1]}" == *"(='.'=)-*"* ]]
}

@test "farewell pose waves a paw at the feet" {
    run bunny_pose "farewell" "$BUNNY_FACE_CRYING" "*waves tiny paw*"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"waves tiny paw"* ]]
    [[ "${lines[2]}" == *'(")_(")/'* ]]
}

@test "sitting pose without message shows face only on middle line" {
    run bunny_pose "sitting" "$BUNNY_FACE_NORMAL" ""
    [[ "${lines[1]}" == " (='.'=)" ]]
}

# --- Faces are the eyes.nose.eyes only ---

@test "face constants are three-character faces" {
    local f
    for f in "$BUNNY_FACE_NORMAL" "$BUNNY_FACE_HAPPY" "$BUNNY_FACE_WORRIED" "$BUNNY_FACE_WIDE" \
             "$BUNNY_FACE_SWEAT" "$BUNNY_FACE_TEARY" "$BUNNY_FACE_CRYING" "$BUNNY_FACE_SLEEPING"; do
        [[ "${#f}" -eq 3 ]]
        [[ "${f:1:1}" == "." ]]
    done
}
