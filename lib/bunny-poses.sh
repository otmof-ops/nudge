#!/usr/bin/env bash
# nudge — lib/bunny-poses.sh
# Bunny ASCII art poses — 10 movement variants, all 3-line format
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

# --- Pose dispatcher ---
# Usage: bunny_pose <pose> <face> [message]
# Returns 3-line ASCII art string via stdout
bunny_pose() {
    local pose="${1:-sitting}" face="${2:-$BUNNY_FACE_NORMAL}" msg="${3:-}"
    "_bunny_pose_${pose}" "$face" "$msg" 2>/dev/null || _bunny_pose_sitting "$face" "$msg"
}

# --- Sitting (default) ---
# Standard bunny: ears, face+msg, feet
_bunny_pose_sitting() {
    local face="$1" msg="${2:-}"
    if [[ -n "$msg" ]]; then
        printf ' (\\__/)\n %s  %s\n (")_(")' "$face" "$msg"
    else
        printf ' (\\__/)\n %s\n (")_(")' "$face"
    fi
}

# --- Peeking (selfupdate, prompt streak 2-3) ---
# Bunny peeking from side
_bunny_pose_peeking() {
    local face="$1" msg="${2:-}"
    if [[ -n "$msg" ]]; then
        printf ' (\\__/)\n %s |  %s\n (")_(") |' "$face" "$msg"
    else
        printf ' (\\__/)\n %s |\n (")_(") |' "$face"
    fi
}

# --- Tapping (reboot, prompt streak 4-5) ---
# Bunny tapping with arm
_bunny_pose_tapping() {
    local face="$1" msg="${2:-}"
    if [[ -n "$msg" ]]; then
        printf ' (\\__/)\n %s  %s\n (\")_(\")o' "$face" "$msg"
    else
        printf ' (\\__/)\n %s\n (\")_(\")o' "$face"
    fi
}

# --- Jumping (accepted, security) ---
# Bunny with arms up
_bunny_pose_jumping() {
    local face="$1" msg="${2:-}"
    if [[ -n "$msg" ]]; then
        printf ' \\(\\__/)/\n  %s  %s\n /(")_(")\\' "$face" "$msg"
    else
        printf ' \\(\\__/)/\n  %s\n /(")_(")\\' "$face"
    fi
}

# --- Hiding (security warnings, streak 6) ---
# Bunny covering face with paws
_bunny_pose_hiding() {
    local face="$1" msg="${2:-}"
    if [[ -n "$msg" ]]; then
        printf ' (\\__/)\n (\")%s(\")  %s\n  (")_(")' "$face" "$msg"
    else
        printf ' (\\__/)\n (\")%s(\")\n  (")_(")' "$face"
    fi
}

# --- Sleeping (zero updates) ---
# Overrides face to closed eyes
_bunny_pose_sleeping() {
    local _face="$1" msg="${2:-}"
    # Always override face for sleeping
    local sleep_face="(-'.'-)  zzz"
    if [[ -n "$msg" ]]; then
        printf ' (\\__/)\n %s  %s\n (")_(")' "$sleep_face" "$msg"
    else
        printf ' (\\__/)\n %s\n (")_(")' "$sleep_face"
    fi
}

# --- Handing (snapshot) ---
# Bunny holding a star
_bunny_pose_handing() {
    local face="$1" msg="${2:-}"
    if [[ -n "$msg" ]]; then
        printf ' (\\__/)\n %s  %s\n (")_(")>' "$face" "$msg"
    else
        printf ' (\\__/)\n %s\n (")_(")>' "$face"
    fi
}

# --- Waving (declined streak 0-1, returning) ---
# Bunny waving
_bunny_pose_waving() {
    local face="$1" msg="${2:-}"
    if [[ -n "$msg" ]]; then
        printf ' (\\__/)/\n %s  %s\n (")_(")' "$face" "$msg"
    else
        printf ' (\\__/)/\n %s\n (")_(")' "$face"
    fi
}

# --- Hugging (network down) ---
# Arms together
_bunny_pose_hugging() {
    local face="$1" msg="${2:-}"
    if [[ -n "$msg" ]]; then
        printf ' (\\__/)\n(%s)  %s\n (\")(\")' "$face" "$msg"
    else
        printf ' (\\__/)\n(%s)\n (\")(\")' "$face"
    fi
}

# --- Looking up (big_update, first_run) ---
# Wide eyes override
_bunny_pose_looking_up() {
    local _face="$1" msg="${2:-}"
    local wide_face="$BUNNY_FACE_WIDE"
    if [[ -n "$msg" ]]; then
        printf ' (\\__/)\n %s  %s\n (")_(")' "$wide_face" "$msg"
    else
        printf ' (\\__/)\n %s\n (")_(")' "$wide_face"
    fi
}

# --- Farewell (uninstall final) ---
# Bunny waving goodbye with tiny paw
_bunny_pose_farewell() {
    local face="$1" msg="${2:-}"
    if [[ -n "$msg" ]]; then
        printf ' (\\__/)\n %s  %s\n (")_(")ノ' "$face" "$msg"
    else
        printf ' (\\__/)\n %s\n (")_(")ノ' "$face"
    fi
}
