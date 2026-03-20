#!/usr/bin/env bash
# nudge — lib/bunny-dialogue.sh
# Bunny dialogue arrays — 100+ rotating messages with no-repeat selection
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

# --- Message arrays ---

_BUNNY_MSG_PROMPT=(
    "oh! you gots updates! wanna get em?"
    "guess what guess what! new stuff!"
    "hey hey! i found some updates for you!"
    "psst! there's new things to install!"
    "ooh i been waiting to tell you! updates!"
    "hiii! your computer has presents!"
    "good news good news! update time!"
    "i checked and there's new stuff ready!"
)

_BUNNY_MSG_DECLINED_0=(
    "okie dokie! i come back later~"
    "no worries! i'll ask again soon!"
    "okay! i'll keep an eye on things!"
)

_BUNNY_MSG_DECLINED_1=(
    "is okay... i just checkin on you"
    "i'll try again later, promise!"
    "that's okay! maybe next time!"
)

_BUNNY_MSG_DECLINED_2=(
    "maybe tomorrow? i'll be here!"
    "but... some of em are the portant ones..."
    "i keep askin cause i care about you..."
)

_BUNNY_MSG_DECLINED_3=(
    "i don't want the bad things to get you..."
    "the updates are getting kinda old now..."
    "please? just the safety ones at least?"
)

_BUNNY_MSG_DECLINED_4=(
    "i been asking real nice..."
    "my heart hurts when you say no..."
)

_BUNNY_MSG_DECLINED_5=(
    "i don't want the bad things to get you..."
    "please... i'm trying so hard..."
)

_BUNNY_MSG_DECLINED_6=(
    "why you no let me help..."
    "*sniffles* ...okay..."
)

# Streak 7+ — silent treatment (empty string = no message)
_BUNNY_MSG_DECLINED_7=("")

_BUNNY_MSG_ACCEPTED=(
    "yay!! all safe now! you da best!"
    "*happy bounces* we did it we did it!"
    "woohoo! everything is all fresh now!"
    "you're the best human ever!!"
    "i'm so proud of us!!"
    "see? that wasn't so bad! all done!"
    "yayyy! your computer is happy now!"
)

_BUNNY_MSG_SECURITY=(
    "we got the portant ones!! no more scaries!"
    "the shields are back up! safe safe safe!"
    "security stuff all done! you're protected!"
    "no more vulnerabilities! we got em all!"
)

_BUNNY_MSG_ZERO=(
    "everything all clean! good job!"
    "*inspects everything* yep! all good here!"
    "nothing to update! you're already perfect!"
    "all clean! i checked twice just to be sure!"
    "zero updates! your system is tip top!"
    "i don't have nothing to do right now so i came to say henlo"
    "guess what! ...i forgetted. but hi!"
    "i was counting all the updates in my sleepy time... there was zero!"
    "hi! i just wanted to see your face. okay bye!"
    "sometimes i just check for fun. still zero!"
)

_BUNNY_MSG_REBOOT=(
    "um... you might need to do a restart thingy"
    "the computer wants to take a little nap"
    "a reboot would make everything feel better!"
)

_BUNNY_MSG_SNAPSHOT=(
    "i saved a backup just in case! i gotchu"
    "made a safety copy! just bein careful!"
    "snapshot done! now we got a safety net!"
)

_BUNNY_MSG_NETWORK=(
    "can't reach the internet thingy... i try later"
    "the internet went bye bye..."
    "i can't see the outside world right now..."
)

_BUNNY_MSG_SELFUPDATE=(
    "oh oh! there's a newer me! wanna get it?"
    "they made improvements to me!!"
    "there's a shinier version of me out there!"
)

_BUNNY_MSG_FIRST_RUN=(
    "oh hello! i'm nudge! i'm gonna help keep you safe!"
    "hi there! i'm your new update buddy!"
)

_BUNNY_MSG_RETURNING=(
    "you're back!! i missed you!"
    "omg hi!! it's been so long!"
    "i waited for you every day!!"
    "i waited and waited and you didn't come... but you're here now!"
    "sometimes when you're gone i just sit here and wait for you"
)

_BUNNY_MSG_BIG_UPDATE=(
    "wow that's a lot of updates! let's do this!"
    "big update day! this is gonna be fun!"
)

# --- Late night messages (22:00-04:59) ---
_BUNNY_MSG_LATE_NIGHT=(
    "you're still awake? me too... i couldn't sleepy"
    "i woked up and it was all dark and scary..."
    "i heared a big noise... you still here right?"
    "it's late... you should rest. i'll watch over things!"
)

# --- Early morning messages (05:00-06:59) ---
_BUNNY_MSG_EARLY_MORNING=(
    "*rubs eyes* ...oh! you're here already! i'm not even ready!"
    "it's so early! did you have a sleepy time too?"
    "good morning! the sun is barely even up yet!"
)

# --- Weekend messages (Saturday-Sunday) ---
_BUNNY_MSG_WEEKEND=(
    "no work today! just me and you! ...and zero updates!"
    "it's the weekend! but i still checked for you!"
    "lazy day! everything is all good!"
)

# --- First login of the day ---
_BUNNY_MSG_FIRST_LOGIN=(
    "good morning fren! i been waiting for you!"
    "you're here! i missed you since yesterday!"
    "hi hi hi! new day new us!"
)

# --- Last message state I/O ---

_bunny_load_last_message() {
    local -n _ctx_ref="$1" _idx_ref="$2"
    local state_file="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}/bunny_last_message"
    _ctx_ref=""
    _idx_ref="-1"
    if [[ -f "$state_file" ]]; then
        local lines
        mapfile -t lines < "$state_file" 2>/dev/null || return 0
        _ctx_ref="${lines[0]:-}"
        _idx_ref="${lines[1]:--1}"
    fi
}

_bunny_save_last_message() {
    local arr_name="$1" idx="$2"
    local state_file="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}/bunny_last_message"
    mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
    local tmp
    tmp=$(mktemp "${state_file}.XXXXXX") && printf '%s\n%s\n' "$arr_name" "$idx" > "$tmp" && mv "$tmp" "$state_file"
}

# --- Random message picker with no-repeat ---
# Usage: _bunny_pick_message <array_name>
# Returns: selected message string via stdout
_bunny_pick_message() {
    local arr_name="$1"
    # shellcheck disable=SC2178
    local -n arr="$arr_name"
    local len=${#arr[@]}
    [[ "$len" -eq 0 ]] && return
    [[ "$len" -eq 1 ]] && echo "${arr[0]}" && return

    local pick=$(( RANDOM % len ))

    # Check last used, skip if repeat
    local last_ctx last_idx
    _bunny_load_last_message last_ctx last_idx
    if [[ "$last_ctx" == "$arr_name" && "$pick" -eq "$last_idx" ]]; then
        pick=$(( (pick + 1) % len ))
    fi

    _bunny_save_last_message "$arr_name" "$pick"
    echo "${arr[$pick]}"
}
