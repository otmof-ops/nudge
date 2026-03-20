#!/usr/bin/env bash
# nudge — lib/bunny.sh
# Bunny personality engine — orchestrator, render engine, season detection, state tracking
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

BUNNY_STREAK_FILE="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}/decline_streak"

# --- Face constants ---
readonly BUNNY_FACE_NORMAL="(='.'=)"
readonly BUNNY_FACE_HAPPY="(^'.'^)"
readonly BUNNY_FACE_WORRIED="(o'.'o)"
readonly BUNNY_FACE_SWEAT="(;'.'=)"
readonly BUNNY_FACE_TEARY="(:'.'=)"
readonly BUNNY_FACE_CRYING="(T.'T)"
# shellcheck disable=SC2034  # Face constants are used by bunny-poses.sh and sourcing scripts
readonly BUNNY_FACE_SLEEPING="(-'.'-)'"
# shellcheck disable=SC2034
readonly BUNNY_FACE_WIDE="(o'.'o)"

# --- State file paths ---
_BUNNY_INSTALL_DATE_FILE="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}/bunny_install_date"
_BUNNY_LAST_SEEN_FILE="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}/bunny_last_seen"

# --- Streak file I/O ---

bunny_get_streak() {
    if [[ -f "$BUNNY_STREAK_FILE" ]]; then
        local val
        val=$(cat "$BUNNY_STREAK_FILE" 2>/dev/null) || val=0
        if [[ "$val" =~ ^[0-9]+$ ]]; then
            echo "$val"
        else
            echo 0
        fi
    else
        echo 0
    fi
}

bunny_increment_streak() {
    local current
    current=$(bunny_get_streak)
    _bunny_atomic_write "$BUNNY_STREAK_FILE" "$((current + 1))"
}

bunny_reset_streak() {
    _bunny_atomic_write "$BUNNY_STREAK_FILE" "0"
}

# Self-contained atomic write (no cross-module dependency)
_bunny_atomic_write() {
    local file="$1" value="$2"
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    local tmp
    tmp=$(mktemp "${file}.XXXXXX") && echo "$value" > "$tmp" && mv "$tmp" "$file"
}

# --- Initialization ---
# Usage: bunny_init
# Writes install date if missing, updates last_seen. Call once from nudge.sh.
bunny_init() {
    local state_dir="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}"
    mkdir -p "$state_dir" 2>/dev/null || true

    # Update state file paths with resolved state dir
    _BUNNY_INSTALL_DATE_FILE="${state_dir}/bunny_install_date"
    _BUNNY_LAST_SEEN_FILE="${state_dir}/bunny_last_seen"

    # Write install date if first run
    if [[ ! -f "$_BUNNY_INSTALL_DATE_FILE" ]]; then
        _bunny_atomic_write "$_BUNNY_INSTALL_DATE_FILE" "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
    fi

    # Always update last seen
    _bunny_atomic_write "$_BUNNY_LAST_SEEN_FILE" "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
}

# --- Face selection ---
# Usage: bunny_face <context> [streak]
bunny_face() {
    local context="$1"
    local streak="${2:-0}"
    local personality="${BUNNY_PERSONALITY:-disney}"

    if [[ "$personality" == "classic" ]]; then
        echo "$BUNNY_FACE_NORMAL"
        return
    fi

    case "$context" in
        prompt)
            if [[ "$streak" -ge 5 ]]; then
                echo "$BUNNY_FACE_CRYING"
            elif [[ "$streak" -ge 4 ]]; then
                echo "$BUNNY_FACE_TEARY"
            elif [[ "$streak" -ge 3 ]]; then
                echo "$BUNNY_FACE_SWEAT"
            else
                echo "$BUNNY_FACE_NORMAL"
            fi
            ;;
        declined)
            if [[ "$streak" -ge 4 ]]; then
                echo "$BUNNY_FACE_CRYING"
            elif [[ "$streak" -ge 3 ]]; then
                echo "$BUNNY_FACE_TEARY"
            elif [[ "$streak" -ge 2 ]]; then
                echo "$BUNNY_FACE_SWEAT"
            else
                echo "$BUNNY_FACE_NORMAL"
            fi
            ;;
        accepted|security)
            echo "$BUNNY_FACE_HAPPY"
            ;;
        zero)
            echo "$BUNNY_FACE_NORMAL"
            ;;
        reboot)
            echo "$BUNNY_FACE_WORRIED"
            ;;
        snapshot)
            echo "$BUNNY_FACE_NORMAL"
            ;;
        selfupdate)
            echo "$BUNNY_FACE_NORMAL"
            ;;
        network)
            echo "$BUNNY_FACE_NORMAL"
            ;;
        *)
            echo "$BUNNY_FACE_NORMAL"
            ;;
    esac
}

# --- Message selection ---
# Usage: bunny_message <context> [extra_data]
bunny_message() {
    local context="$1"
    local extra="${2:-}"
    local personality="${BUNNY_PERSONALITY:-disney}"

    if [[ "$personality" == "classic" ]]; then
        _bunny_message_classic "$context" "$extra"
        return
    fi

    _bunny_message_disney "$context" "$extra"
}

_bunny_message_disney() {
    local context="$1"
    local extra="${2:-}"
    local streak
    streak=$(bunny_get_streak)

    case "$context" in
        prompt)
            local time_ctx
            time_ctx=$(_bunny_detect_time_context)
            # 30% chance for time-aware flavor
            if [[ "$time_ctx" != "none" ]] && [[ $(( RANDOM % 3 )) -eq 0 ]]; then
                case "$time_ctx" in
                    late_night)     _bunny_pick_message "_BUNNY_MSG_LATE_NIGHT" ;;
                    early_morning)  _bunny_pick_message "_BUNNY_MSG_EARLY_MORNING" ;;
                    weekend)        _bunny_pick_message "_BUNNY_MSG_WEEKEND" ;;
                esac
            else
                _bunny_pick_message "_BUNNY_MSG_PROMPT"
            fi
            ;;
        declined)
            local arr_name="_BUNNY_MSG_DECLINED_${streak}"
            # Cap at 7 for streak 7+
            if [[ "$streak" -ge 7 ]]; then
                arr_name="_BUNNY_MSG_DECLINED_7"
            fi
            # Check if array exists, fallback to highest available
            local -n _test_arr="$arr_name" 2>/dev/null || true
            if [[ ${#_test_arr[@]} -gt 0 ]]; then
                _bunny_pick_message "$arr_name"
            else
                _bunny_pick_message "_BUNNY_MSG_DECLINED_7"
            fi
            ;;
        accepted)
            _bunny_pick_message "_BUNNY_MSG_ACCEPTED"
            ;;
        security)
            _bunny_pick_message "_BUNNY_MSG_SECURITY"
            ;;
        zero)
            local time_ctx
            time_ctx=$(_bunny_detect_time_context)
            # 50% chance to use time-aware message when applicable
            if [[ "$time_ctx" != "none" ]] && [[ $(( RANDOM % 2 )) -eq 0 ]]; then
                case "$time_ctx" in
                    late_night)     _bunny_pick_message "_BUNNY_MSG_LATE_NIGHT" ;;
                    early_morning)  _bunny_pick_message "_BUNNY_MSG_EARLY_MORNING" ;;
                    weekend)        _bunny_pick_message "_BUNNY_MSG_WEEKEND" ;;
                esac
            else
                _bunny_pick_message "_BUNNY_MSG_ZERO"
            fi
            ;;
        reboot)
            _bunny_pick_message "_BUNNY_MSG_REBOOT"
            ;;
        snapshot)
            _bunny_pick_message "_BUNNY_MSG_SNAPSHOT"
            ;;
        selfupdate)
            _bunny_pick_message "_BUNNY_MSG_SELFUPDATE"
            ;;
        network)
            _bunny_pick_message "_BUNNY_MSG_NETWORK"
            ;;
        first_run)
            _bunny_pick_message "_BUNNY_MSG_FIRST_RUN"
            ;;
        returning)
            _bunny_pick_message "_BUNNY_MSG_RETURNING"
            ;;
        big_update)
            _bunny_pick_message "_BUNNY_MSG_BIG_UPDATE"
            ;;
        *)
            echo ""
            ;;
    esac
}

_bunny_message_classic() {
    local context="$1"
    local extra="${2:-}"

    case "$context" in
        prompt|first_run|returning|big_update)
            echo "Updates available"
            ;;
        declined)
            echo "Update declined"
            ;;
        accepted)
            echo "Updates applied successfully"
            ;;
        security)
            echo "Security updates applied"
            ;;
        zero)
            echo "System is up to date"
            ;;
        reboot)
            echo "A system reboot is required"
            ;;
        snapshot)
            echo "Pre-upgrade snapshot created"
            ;;
        selfupdate)
            echo "A newer version of nudge is available"
            ;;
        network)
            echo "Network unavailable, skipping update check"
            ;;
        *)
            echo ""
            ;;
    esac
}

# --- Season detection ---
# Usage: _bunny_detect_season
# Returns: christmas|halloween|summer|winter|birthday|none
_bunny_detect_season() {
    local month day
    month=$(date '+%-m')
    day=$(date '+%-d')

    # Check birthday (install anniversary) first — overrides season
    if [[ -f "$_BUNNY_INSTALL_DATE_FILE" ]]; then
        local install_date
        install_date=$(cat "$_BUNNY_INSTALL_DATE_FILE" 2>/dev/null) || install_date=""
        if [[ -n "$install_date" ]]; then
            local install_month install_day
            install_month=$(date -d "$install_date" '+%-m' 2>/dev/null) || install_month=""
            install_day=$(date -d "$install_date" '+%-d' 2>/dev/null) || install_day=""
            if [[ "$install_month" == "$month" && "$install_day" == "$day" ]]; then
                echo "birthday"
                return
            fi
        fi
    fi

    case "$month" in
        1|2)   echo "winter" ;;
        6|7|8) echo "summer" ;;
        10)    echo "halloween" ;;
        12)    echo "christmas" ;;
        *)     echo "none" ;;
    esac
}

# --- Season decoration ---
# Usage: _bunny_season_decorate <pose_string> <season>
# Prepends/appends emoji to first/last line
_bunny_season_decorate() {
    local pose_string="$1" season="$2"

    [[ "$season" == "none" ]] && echo "$pose_string" && return

    local prefix="" suffix=""
    case "$season" in
        christmas)  prefix="🎄 " ; suffix=" 🎁" ;;
        halloween)  prefix="🦇 " ; suffix=" 🎃" ;;
        summer)     prefix="🌻 " ; suffix=" 🌻" ;;
        winter)     prefix="❄ "  ; suffix=" ❄" ;;
        birthday)   prefix="🎂 " ; suffix=" 🎈" ;;
    esac

    # Split pose into lines, decorate first and last
    local -a lines
    IFS=$'\n' read -r -d '' -a lines <<< "$pose_string" || true

    local count=${#lines[@]}
    if [[ "$count" -eq 0 ]]; then
        echo "$pose_string"
        return
    fi

    lines[0]="${prefix}${lines[0]}"
    lines[count - 1]="${lines[$((count - 1))]}${suffix}"

    local i
    for i in "${!lines[@]}"; do
        if [[ "$i" -lt $((count - 1)) ]]; then
            printf '%s\n' "${lines[$i]}"
        else
            printf '%s' "${lines[$i]}"
        fi
    done
}

# --- Time-of-day context detection ---
# Usage: _bunny_detect_time_context
# Returns: late_night|early_morning|weekend|none
_bunny_detect_time_context() {
    local hour day_of_week
    hour=$(date '+%-H')
    day_of_week=$(date '+%u')  # 1=Monday, 7=Sunday

    # Late night: 22:00-04:59
    if [[ "$hour" -ge 22 ]] || [[ "$hour" -lt 5 ]]; then
        echo "late_night"
        return
    fi

    # Early morning: 05:00-06:59
    if [[ "$hour" -ge 5 ]] && [[ "$hour" -lt 7 ]]; then
        echo "early_morning"
        return
    fi

    # Weekend: Saturday(6) or Sunday(7)
    if [[ "$day_of_week" -ge 6 ]]; then
        echo "weekend"
        return
    fi

    echo "none"
}

# --- Special context detection ---
# Usage: _bunny_detect_special_context <base_context> <total_updates>
# May override to first_run|returning|big_update
_bunny_detect_special_context() {
    local base_context="$1" total_updates="${2:-0}"

    # Only override prompt context
    if [[ "$base_context" != "prompt" ]]; then
        echo "$base_context"
        return
    fi

    # Check first run
    if [[ ! -f "$_BUNNY_INSTALL_DATE_FILE" ]]; then
        echo "first_run"
        return
    fi

    # Check returning (>7 days since last seen)
    if [[ -f "$_BUNNY_LAST_SEEN_FILE" ]]; then
        local last_seen diff_days
        last_seen=$(cat "$_BUNNY_LAST_SEEN_FILE" 2>/dev/null) || last_seen=""
        if [[ -n "$last_seen" ]]; then
            local last_epoch now_epoch
            last_epoch=$(date -d "$last_seen" '+%s' 2>/dev/null) || last_epoch=0
            now_epoch=$(date '+%s')
            if [[ "$last_epoch" -gt 0 ]]; then
                diff_days=$(( (now_epoch - last_epoch) / 86400 ))
                if [[ "$diff_days" -ge 7 ]]; then
                    echo "returning"
                    return
                fi
            fi
        fi
    fi

    # Check big update
    if [[ "$total_updates" -ge 50 ]]; then
        echo "big_update"
        return
    fi

    echo "$base_context"
}

# --- Pose selection ---
# Usage: _bunny_select_pose <context> <streak>
_bunny_select_pose() {
    local context="$1" streak="${2:-0}"

    case "$context" in
        first_run|big_update)
            echo "looking_up"
            ;;
        returning)
            echo "waving"
            ;;
        accepted|security)
            echo "jumping"
            ;;
        zero)
            echo "sleeping"
            ;;
        reboot)
            echo "tapping"
            ;;
        snapshot)
            echo "handing"
            ;;
        selfupdate)
            echo "peeking"
            ;;
        network)
            echo "hugging"
            ;;
        prompt)
            if [[ "$streak" -ge 6 ]]; then
                echo "hiding"
            elif [[ "$streak" -ge 4 ]]; then
                echo "tapping"
            elif [[ "$streak" -ge 2 ]]; then
                echo "peeking"
            else
                echo "sitting"
            fi
            ;;
        declined)
            if [[ "$streak" -ge 6 ]]; then
                echo "hiding"
            elif [[ "$streak" -ge 2 ]]; then
                echo "peeking"
            else
                echo "waving"
            fi
            ;;
        *)
            echo "sitting"
            ;;
    esac
}

# --- Primary render API ---
# Usage: bunny_render <context> <detail> [total_updates]
# Returns complete multi-line bunny string
bunny_render() {
    local context="$1" detail="${2:-}" total_updates="${3:-0}"
    local personality="${BUNNY_PERSONALITY:-disney}"

    # Classic mode — exact legacy output
    if [[ "$personality" == "classic" ]]; then
        local classic_msg
        classic_msg=$(_bunny_message_classic "$context")
        if [[ -n "$detail" ]]; then
            printf ' (\\__/)\n %s  %s\n (")_(")  %s' "$BUNNY_FACE_NORMAL" "$classic_msg" "$detail"
        elif [[ -n "$classic_msg" ]]; then
            printf ' (\\__/)\n %s  %s\n (")_(")' "$BUNNY_FACE_NORMAL" "$classic_msg"
        else
            printf ' (\\__/)\n %s\n (")_(")' "$BUNNY_FACE_NORMAL"
        fi
        return
    fi

    # Disney mode — full living character
    local streak
    streak=$(bunny_get_streak)

    # Detect special context override
    local effective_context
    effective_context=$(_bunny_detect_special_context "$context" "$total_updates")

    # Select face
    local face
    face=$(bunny_face "$effective_context" "$streak")

    # Select message
    local msg
    msg=$(_bunny_message_disney "$effective_context")

    # Build message with detail
    local full_msg="$msg"
    if [[ -n "$detail" && -n "$msg" ]]; then
        full_msg="${msg}"
    elif [[ -z "$msg" && -n "$detail" ]]; then
        full_msg=""
    fi

    # Select and render pose
    local pose
    pose=$(_bunny_select_pose "$effective_context" "$streak")

    local pose_output
    pose_output=$(bunny_pose "$pose" "$face" "$full_msg")

    # Apply seasonal decoration
    local season
    season=$(_bunny_detect_season)
    local decorated
    decorated=$(_bunny_season_decorate "$pose_output" "$season")

    # If detail is provided, append it on the feet line
    if [[ -n "$detail" ]]; then
        # Replace the last line to include detail
        local -a out_lines
        IFS=$'\n' read -r -d '' -a out_lines <<< "$decorated" || true
        local count=${#out_lines[@]}
        if [[ "$count" -ge 3 ]]; then
            out_lines[count - 1]="${out_lines[$((count - 1))]}  ${detail}"
        fi
        local i
        for i in "${!out_lines[@]}"; do
            if [[ "$i" -lt $((count - 1)) ]]; then
                printf '%s\n' "${out_lines[$i]}"
            else
                printf '%s' "${out_lines[$i]}"
            fi
        done
    else
        printf '%s' "$decorated"
    fi
}

# --- Deprecated wrapper (backward compatibility) ---
# Usage: bunny_dialog <context> [extra_data]
bunny_dialog() {
    local context="$1"
    local extra="${2:-}"
    local streak
    streak=$(bunny_get_streak)

    local face
    face=$(bunny_face "$context" "$streak")
    local msg
    msg=$(bunny_message "$context" "$extra")

    if [[ -n "$msg" ]]; then
        printf ' (\\__/)\n %s  %s\n (")_(")' "$face" "$msg"
    else
        printf ' (\\__/)\n %s\n (")_(")' "$face"
    fi
}
