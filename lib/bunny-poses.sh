#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/bunny-poses.sh
# shellcheck disable=SC2034  # constants used by the sourcing scripts
# The Nudge Bunny: faces and poses. Every pose is three lines of plain ASCII
# so it survives dialogs, terminals and the README alike. The face sits in the
# head, the message rides the face line, and bunny_render appends the detail
# to the feet line.
#
#      (\__/)
#      (='.'=)  message
#      (")_(")  detail

set -euo pipefail

# --- Faces: the eyes.nose.eyes inside the head ---
# Guarded so the file can be sourced after bunny.sh pulled it in already.
if [[ -z "${BUNNY_FACE_NORMAL:-}" ]]; then
    readonly BUNNY_FACE_NORMAL="'.'"
    readonly BUNNY_FACE_HAPPY="^.^"
    readonly BUNNY_FACE_WORRIED="o.o"
    readonly BUNNY_FACE_WIDE="O.O"
    readonly BUNNY_FACE_SWEAT="-.-"
    readonly BUNNY_FACE_TEARY=";.;"
    readonly BUNNY_FACE_CRYING="T.T"
    readonly BUNNY_FACE_SLEEPING="-.-"
    # --- Shared art pieces ---
    readonly BUNNY_EARS=' (\__/)'
    readonly BUNNY_FEET=' (")_(")'
fi

# --- Head: wrap a face in the bunny's cheeks ---
# Usage: bunny_head <face>   ->  (='.'=)
bunny_head() {
    printf '(=%s=)' "${1:-$BUNNY_FACE_NORMAL}"
}

# --- Three-line layout helper ---
# Usage: _bunny_lines <ears> <head-line> <feet> [message]
# Prints the pose without a trailing newline (callers add detail or newline).
_bunny_lines() {
    local l1="$1" l2="$2" l3="$3" msg="${4:-}"
    if [[ -n "$msg" ]]; then
        printf '%s\n%s  %s\n%s' "$l1" "$l2" "$msg" "$l3"
    else
        printf '%s\n%s\n%s' "$l1" "$l2" "$l3"
    fi
}

# --- Pose dispatcher ---
# Usage: bunny_pose <pose> <face> [message]
bunny_pose() {
    local pose="${1:-sitting}" face="${2:-$BUNNY_FACE_NORMAL}" msg="${3:-}"
    "_bunny_pose_${pose}" "$face" "$msg" 2>/dev/null || _bunny_pose_sitting "$face" "$msg"
}

# --- Sitting (default) ---
_bunny_pose_sitting() {
    local face="$1" msg="${2:-}"
    _bunny_lines "$BUNNY_EARS" " $(bunny_head "$face")" "$BUNNY_FEET" "$msg"
}

# --- Peeking from behind an edge (selfupdate, prompt streak 2-3) ---
_bunny_pose_peeking() {
    local face="$1" msg="${2:-}"
    _bunny_lines ' |(\__/)' " |$(bunny_head "$face")" ' |(")_(")' "$msg"
}

# --- Tapping a paw (reboot, prompt streak 4-5) ---
_bunny_pose_tapping() {
    local face="$1" msg="${2:-}"
    _bunny_lines "$BUNNY_EARS" " $(bunny_head "$face")_/" "$BUNNY_FEET" "$msg"
}

# --- Jumping with both paws up (accepted, security) ---
_bunny_pose_jumping() {
    local face="$1" msg="${2:-}"
    _bunny_lines ' \(\__/)/' "  $(bunny_head "$face")" '  (")_(")' "$msg"
}

# --- Hiding behind the paws (streak 6+) ---
_bunny_pose_hiding() {
    local face="$1" msg="${2:-}"
    _bunny_lines "$BUNNY_EARS" ' (")'"$face"'(")' "$BUNNY_FEET" "$msg"
}

# --- Sleeping (zero updates); always closed eyes ---
_bunny_pose_sleeping() {
    local _face="$1" msg="${2:-}"
    _bunny_lines "$BUNNY_EARS" " $(bunny_head "$BUNNY_FACE_SLEEPING") zzz" "$BUNNY_FEET" "$msg"
}

# --- Handing over a star (snapshot) ---
_bunny_pose_handing() {
    local face="$1" msg="${2:-}"
    _bunny_lines "$BUNNY_EARS" " $(bunny_head "$face")-*" "$BUNNY_FEET" "$msg"
}

# --- Waving a paw by the ear (declined streak 0-1, returning) ---
_bunny_pose_waving() {
    local face="$1" msg="${2:-}"
    _bunny_lines ' (\__/)/' " $(bunny_head "$face")" "$BUNNY_FEET" "$msg"
}

# --- Hugging itself (network down) ---
_bunny_pose_hugging() {
    local face="$1" msg="${2:-}"
    _bunny_lines "$BUNNY_EARS" "($(bunny_head "$face"))" "$BUNNY_FEET" "$msg"
}

# --- Looking up, wide eyes (big_update, first_run) ---
_bunny_pose_looking_up() {
    local _face="$1" msg="${2:-}"
    _bunny_lines "$BUNNY_EARS" " $(bunny_head "$BUNNY_FACE_WIDE")" "$BUNNY_FEET" "$msg"
}

# --- Farewell, a tiny paw wave at the feet (uninstall) ---
_bunny_pose_farewell() {
    local face="$1" msg="${2:-}"
    _bunny_lines "$BUNNY_EARS" " $(bunny_head "$face")" ' (")_(")/' "$msg"
}
