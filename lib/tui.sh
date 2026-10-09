#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/tui.sh
# TUI rendering: the palette (truecolor, 256 colours or the basic 16, by what
# the terminal reports), frames, menus, prompts, and the text bunny.

set -euo pipefail

# --- Menu choice result ---
_MENU_CHOICE=""

# --- Colour codes: empty until _tui_init, and whenever colour is off ---
_TUI_BOLD='' _TUI_RESET='' _TUI_DIMMED=''
_TUI_ACCENT='' _TUI_CRIT='' _TUI_SEC='' _TUI_SNAP='' _TUI_FLATPAK='' _TUI_PINK='' _TUI_GRAY=''
# The older names, kept for the setup TUI and the modules that use them
_TUI_GREEN='' _TUI_YELLOW='' _TUI_CYAN='' _TUI_RED='' _TUI_PURPLE='' _TUI_WHITE='' _TUI_BORDER=''
# Semantic aliases
_TUI_SUCCESS='' _TUI_ERROR='' _TUI_WARNING='' _TUI_INFO='' _TUI_SHADOW='' _TUI_PROMPT=''
_TUI_DEPTH=0

# --- Terminal width ---
_TUI_WIDTH=60

# How many colours the terminal can show: 24 (truecolor), 256, 16, or 0 (none)
# Usage: _tui_color_depth [true|false]   whether stdout is a terminal; the
# caller says, because inside a command substitution stdout is a pipe.
_tui_color_depth() {
    local tty="${1:-}"
    if [[ -z "$tty" ]]; then
        if [[ -t 1 ]]; then tty=true; else tty=false; fi
    fi
    if [[ "${_TUI_NO_COLOR:-false}" == "true" ]] || [[ -n "${NO_COLOR:-}" ]] || [[ "$tty" != "true" ]]; then
        echo 0
        return 0
    fi
    case "${COLORTERM:-}" in
        truecolor|24bit) echo 24; return 0 ;;
    esac
    local n=8
    if command -v tput &>/dev/null; then n=$(tput colors 2>/dev/null || echo 8); fi
    [[ "$n" =~ ^[0-9]+$ ]] || n=8
    if [[ "$n" -ge 256 ]]; then echo 256; elif [[ "$n" -ge 8 ]]; then echo 16; else echo 0; fi
}

# --- Initialize the palette and the width ---
_tui_init() {
    if command -v tput &>/dev/null && [[ -t 1 ]]; then
        _TUI_WIDTH=$(tput cols 2>/dev/null || echo 60)
        [[ "$_TUI_WIDTH" =~ ^[0-9]+$ ]] || _TUI_WIDTH=60
        (( _TUI_WIDTH > 80 )) && _TUI_WIDTH=80
        (( _TUI_WIDTH < 40 )) && _TUI_WIDTH=40
    fi

    local tty=false
    [[ -t 1 ]] && tty=true
    _TUI_DEPTH=$(_tui_color_depth "$tty")
    _TUI_BOLD='' _TUI_RESET='' _TUI_DIMMED=''
    _TUI_ACCENT='' _TUI_CRIT='' _TUI_SEC='' _TUI_SNAP='' _TUI_FLATPAK='' _TUI_PINK='' _TUI_GRAY=''
    case "$_TUI_DEPTH" in
        24)
            _TUI_ACCENT='\033[38;2;46;164;79m'    # the badge green, #2ea44f
            _TUI_CRIT='\033[38;2;217;59;59m'      # #d93b3b
            _TUI_SEC='\033[38;2;224;162;29m'      # #e0a21d
            _TUI_SNAP='\033[38;2;59;125;216m'     # #3b7dd8
            _TUI_FLATPAK='\033[38;2;42;157;143m'  # #2a9d8f
            _TUI_PINK='\033[38;2;231;140;160m'    # the nose, #e78ca0
            _TUI_GRAY='\033[38;2;138;143;152m'    # #8a8f98
            ;;
        256)
            _TUI_ACCENT='\033[38;5;35m' _TUI_CRIT='\033[38;5;167m' _TUI_SEC='\033[38;5;178m'
            _TUI_SNAP='\033[38;5;68m' _TUI_FLATPAK='\033[38;5;37m' _TUI_PINK='\033[38;5;211m'
            _TUI_GRAY='\033[38;5;245m'
            ;;
        16)
            _TUI_ACCENT='\033[0;32m' _TUI_CRIT='\033[0;31m' _TUI_SEC='\033[0;33m'
            _TUI_SNAP='\033[0;34m' _TUI_FLATPAK='\033[0;36m' _TUI_PINK='\033[0;35m'
            _TUI_GRAY='\033[0;90m'
            ;;
    esac
    if [[ "$_TUI_DEPTH" -gt 0 ]]; then
        _TUI_BOLD='\033[1m' _TUI_RESET='\033[0m' _TUI_DIMMED='\033[2m'
    fi
    # The older names
    _TUI_GREEN="$_TUI_ACCENT" _TUI_RED="$_TUI_CRIT" _TUI_YELLOW="$_TUI_SEC" _TUI_CYAN="$_TUI_ACCENT"
    _TUI_PURPLE="$_TUI_PINK" _TUI_WHITE="$_TUI_BOLD" _TUI_BORDER="$_TUI_GRAY"
    # Semantic aliases
    _TUI_SUCCESS="$_TUI_ACCENT" _TUI_ERROR="$_TUI_CRIT" _TUI_WARNING="$_TUI_SEC" _TUI_INFO="$_TUI_SNAP"
    _TUI_SHADOW="$_TUI_GRAY" _TUI_PROMPT="$_TUI_ACCENT"
}

# --- Clear screen ---
_tui_clear() {
    [[ -t 1 ]] && printf '\033[2J\033[H'
    return 0
}

# --- The terminal's window title (where there is a terminal) ---
_tui_title() {
    [[ -t 1 ]] && printf '\033]0;%s\007' "${1:-nudge}"
    return 0
}

# A run of one character: _tui_rule_str <width> [char]
_tui_rule_str() {
    local width="${1:-10}" char="${2:-─}" line="" i
    for (( i=0; i<width; i++ )); do line+="$char"; done
    printf '%s' "$line"
}

# --- Horizontal separator ---
# Usage: _tui_separator [width] [char]
_tui_separator() {
    local width="${1:-$(( _TUI_WIDTH - 4 ))}"
    local char="${2:-─}"
    echo -e "    ${_TUI_SHADOW}$(_tui_rule_str "$width" "$char")${_TUI_RESET}"
}

# --- Framed title, rounded corners ---
# Usage: _tui_draw_header "TITLE" ["subtitle"]
_tui_draw_header() {
    local title="$1"
    local subtitle="${2:-}"
    local inner_width=$(( _TUI_WIDTH - 8 ))
    if (( ${#title} > inner_width - 2 )); then title="${title:0:$((inner_width - 3))}…"; fi
    local pad_total=$(( inner_width - ${#title} ))
    local pad_left=$(( pad_total / 2 ))
    local pad_right=$(( pad_total - pad_left ))
    local rule
    rule=$(_tui_rule_str "$inner_width")

    echo ""
    echo -e "    ${_TUI_ACCENT}╭${rule}╮${_TUI_RESET}"
    echo -e "    ${_TUI_ACCENT}│${_TUI_RESET}$(printf '%*s' "$pad_left" '')${_TUI_BOLD}${title}${_TUI_RESET}$(printf '%*s' "$pad_right" '')${_TUI_ACCENT}│${_TUI_RESET}"
    echo -e "    ${_TUI_ACCENT}╰${rule}╯${_TUI_RESET}"

    if [[ -n "$subtitle" ]]; then
        local sub_pad=$(( (inner_width - ${#subtitle}) / 2 + 5 ))
        (( sub_pad < 4 )) && sub_pad=4
        echo -e "$(printf '%*s' "$sub_pad" '')${_TUI_SHADOW}${subtitle}${_TUI_RESET}"
    fi
}

# --- Menu header ---
# Usage: _tui_menu_header "TITLE"
_tui_menu_header() {
    local title="$1"
    echo ""
    echo -e "    ${_TUI_BOLD}${_TUI_ACCENT}◆ ${title}${_TUI_RESET}"
    _tui_separator
}

# --- Menu section ---
# Usage: _tui_menu_section "Section Name"
_tui_menu_section() {
    echo -e "    ${_TUI_BOLD}${_TUI_PINK}▸ ${1}${_TUI_RESET}"
}

# --- Menu item with description ---
# Usage: _tui_menu_item NUMBER "Label" ["description"]
_tui_menu_item() {
    local num="$1" label="$2" desc="${3:-}"
    local num_display
    num_display=$(printf "%2s" "$num")
    if [[ -n "$desc" ]]; then
        printf '    %b%s)%b %-22s %b%s%b\n' "${_TUI_BOLD}${_TUI_ACCENT}" "$num_display" "$_TUI_RESET" "$label" "$_TUI_SHADOW" "$desc" "$_TUI_RESET"
    else
        printf '    %b%s)%b %s\n' "${_TUI_BOLD}${_TUI_ACCENT}" "$num_display" "$_TUI_RESET" "$label"
    fi
}

# --- Menu footer ---
# Usage: _tui_menu_footer ["Exit"]
_tui_menu_footer() {
    local label="${1:-Exit}"
    _tui_separator
    _tui_menu_item "0" "$label"
}

# --- Styled prompt ---
# Usage: _tui_prompt_choice [max]
# Leaves a number in _MENU_CHOICE (empty input means 0); anything else is
# asked again, and after three tries counts as 0.
_tui_prompt_choice() {
    local max="${1:-}"
    local hint="" tries=0 answer
    [[ -n "$max" ]] && hint=" [0-${max}]"
    echo ""
    while :; do
        answer=""
        read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} Select${hint}: ")" answer 2>/dev/null </dev/tty \
            || read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} Select${hint}: ")" answer \
            || { _MENU_CHOICE=0; return 0; }
        answer="${answer//[[:space:]]/}"
        if [[ -z "$answer" ]]; then _MENU_CHOICE=0; return 0; fi
        if [[ "$answer" =~ ^[0-9]{1,3}$ ]]; then _MENU_CHOICE=$((10#$answer)); return 0; fi
        tries=$((tries + 1))
        if [[ "$tries" -ge 3 ]]; then _MENU_CHOICE=0; return 0; fi
        echo -e "    ${_TUI_WARNING}[!]${_TUI_RESET} Type a number${hint}."
    done
}

# --- Spinner ---
# Usage: _tui_spinner PID ["message"]
_tui_spinner() {
    local pid="$1"
    local msg="${2:-Working...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r    ${_TUI_ACCENT}%s${_TUI_RESET} %s" "${frames[$i]}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
    printf "\r    %-$(( ${#msg} + 4 ))s\r" " "
}

# --- Progress bar ---
# Usage: _tui_progress CURRENT TOTAL ["label"]
_tui_progress() {
    local current="$1"
    local total="$2"
    local label="${3:-}"
    local bar_width=20
    local percent=0
    (( total > 0 )) && percent=$(( current * 100 / total ))
    local filled=$(( bar_width * current / (total > 0 ? total : 1) ))
    local empty=$(( bar_width - filled ))

    local bar
    bar="$(_tui_rule_str "$filled" '█')$(_tui_rule_str "$empty" '░')"

    if [[ -n "$label" ]]; then
        printf "    ${_TUI_BOLD}%-14s${_TUI_RESET} ${_TUI_ACCENT}%s${_TUI_RESET} %3d%%\n" "$label" "$bar" "$percent"
    else
        printf "    ${_TUI_ACCENT}%s${_TUI_RESET} %3d%%\n" "$bar" "$percent"
    fi
}

# --- Operation header: ── Title ───────── ---
# Usage: _tui_operation_header "Title"
_tui_operation_header() {
    local title="$1"
    local rest=$(( _TUI_WIDTH - 4 - ${#title} - 4 ))
    (( rest < 2 )) && rest=2
    echo -e "    ${_TUI_ACCENT}──${_TUI_RESET} ${_TUI_BOLD}${title}${_TUI_RESET} ${_TUI_ACCENT}$(_tui_rule_str "$rest")${_TUI_RESET}"
}

# --- Pause / press Enter ---
# Usage: _tui_pause
_tui_pause() {
    echo ""
    read -rp "$(echo -e "    ${_TUI_SHADOW}Press Enter to continue...${_TUI_RESET}")" 2>/dev/null </dev/tty \
        || read -rp "$(echo -e "    ${_TUI_SHADOW}Press Enter to continue...${_TUI_RESET}")"
}

# --- Typewriter effect ---
# Usage: _tui_typewriter "text" [delay]
_tui_typewriter() {
    local text="$1"
    local delay="${2:-0.03}"
    printf "    "
    for (( i=0; i<${#text}; i++ )); do
        printf '%s' "${text:$i:1}"
        sleep "$delay" 2>/dev/null || true
    done
    echo ""
}

# --- Table display (key=value) ---
# Usage: _tui_table "Key1" "Value1" "Key2" "Value2" ...
_tui_table() {
    local args=("$@")
    local max_key_len=0
    for (( i=0; i<${#args[@]}; i+=2 )); do
        local key="${args[$i]}"
        (( ${#key} > max_key_len )) && max_key_len=${#key}
    done
    for (( i=0; i<${#args[@]}; i+=2 )); do
        local key="${args[$i]}"
        local val="${args[$i+1]:-}"
        printf "    ${_TUI_ACCENT}%-${max_key_len}s${_TUI_RESET}  ${_TUI_BOLD}%s${_TUI_RESET}\n" "$key" "$val"
    done
}

# --- The text bunny with a message: the face in pink, the message in bold ---
# Usage: _tui_bunny "line beside the face" ["line beside the feet"] [face]
_tui_bunny() {
    local msg1="${1:-}" msg2="${2:-}"
    local default_face="'.'"
    local face="${3:-${BUNNY_FACE_NORMAL:-$default_face}}"

    echo ""
    printf '    %s\n' '(\__/)'
    printf '    (=%b%s%b=)  %b%s%b\n' "$_TUI_PINK" "$face" "$_TUI_RESET" "$_TUI_BOLD" "$msg1" "$_TUI_RESET"
    if [[ -n "$msg2" ]]; then
        printf '    %s  %b%s%b\n' '(")_(")' "$_TUI_SHADOW" "$msg2" "$_TUI_RESET"
    else
        printf '    %s\n' '(")_(")'
    fi
    echo ""
}

# --- A coloured marker with its text ---
# Usage: _tui_badge <kind> [text]; kinds: critical security flatpak snap ok fail info standard
_tui_badge() {
    local kind="${1:-standard}" text="${2:-}" mark color=""
    case "$kind" in
        critical) mark="★" color="$_TUI_CRIT" ;;
        security) mark="⚠" color="$_TUI_SEC" ;;
        flatpak)  mark="◆" color="$_TUI_FLATPAK" ;;
        snap)     mark="●" color="$_TUI_SNAP" ;;
        ok)       mark="✓" color="$_TUI_ACCENT" ;;
        fail)     mark="✗" color="$_TUI_CRIT" ;;
        info)     mark="•" color="$_TUI_SNAP" ;;
        *)        mark=" " ;;
    esac
    if [[ -n "$text" ]]; then
        printf '%b%s%b %s' "$color" "$mark" "$_TUI_RESET" "$text"
    else
        printf '%b%s%b' "$color" "$mark" "$_TUI_RESET"
    fi
}

# --- A key hint: the key in the accent colour, what it does in grey ---
# Usage: _tui_key <key> <what it does>
_tui_key() {
    printf '%b%s%b %b%s%b' "${_TUI_BOLD}${_TUI_ACCENT}" "$1" "$_TUI_RESET" "$_TUI_SHADOW" "${2:-}" "$_TUI_RESET"
}

# --- A tick box: [✓] all, [-] some, [ ] none ---
# Usage: _tui_tick <selected> <total>
_tui_tick() {
    local sel="${1:-0}" tot="${2:-0}"
    if [[ "$tot" -eq 0 || "$sel" -eq 0 ]]; then
        printf '[ ]'
    elif [[ "$sel" -eq "$tot" ]]; then
        printf '[%b✓%b]' "$_TUI_ACCENT" "$_TUI_RESET"
    else
        printf '[%b-%b]' "$_TUI_SEC" "$_TUI_RESET"
    fi
}

# --- A result line ---
# Usage: _tui_result ok|fail|skip <text>
_tui_result() {
    case "${1:-}" in
        ok)   echo -e "    ${_TUI_ACCENT}✓${_TUI_RESET} ${2:-}" ;;
        fail) echo -e "    ${_TUI_CRIT}✗${_TUI_RESET} ${2:-}" ;;
        *)    echo -e "    ${_TUI_SHADOW}· ${2:-}${_TUI_RESET}" ;;
    esac
}

# --- Numbered menu ---
# Usage: _tui_menu "Item 1" "Item 2" "Exit"
# Last item auto-numbered 0 if Exit/Back/Save & back/Keep it
_tui_menu() {
    local items=("$@")
    local count=${#items[@]}
    local last_item="${items[$((count - 1))]}"
    local has_footer=false

    if [[ "$last_item" == "Exit" || "$last_item" == "Back" || \
          "$last_item" == "Save & back" || "$last_item" == "Keep it" ]]; then
        has_footer=true
    fi

    local i=1
    for item in "${items[@]}"; do
        if [[ "$has_footer" == "true" ]] && [[ "$i" -eq "$count" ]]; then
            _tui_separator
            _tui_menu_item "0" "$item"
        else
            _tui_menu_item "$i" "$item"
            i=$((i + 1))
        fi
    done

    local max="$count"
    [[ "$has_footer" == "true" ]] && max=$((count - 1))
    _tui_prompt_choice "$max"
}

# --- Yes/No confirmation ---
_tui_confirm() {
    local prompt="$1" default="${2:-true}"
    local hint
    if [[ "$default" == "true" ]]; then hint="Y/n"; else hint="y/N"; fi
    local answer
    read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} ${prompt} [${hint}]: ")" answer 2>/dev/null </dev/tty \
        || read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} ${prompt} [${hint}]: ")" answer
    [[ -z "$answer" ]] && echo "$default" && return
    case "${answer,,}" in
        y|yes) echo "true" ;;
        n|no)  echo "false" ;;
        *)     echo "$default" ;;
    esac
}

# --- Text input with default ---
_tui_input() {
    local prompt="$1" default="${2:-}"
    local answer
    read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} ${prompt} [${default}]: ")" answer 2>/dev/null </dev/tty \
        || read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} ${prompt} [${default}]: ")" answer
    echo "${answer:-$default}"
}

# --- Numbered option picker ---
# The menu goes to stderr: callers capture stdout for the answer alone
_tui_choice() {
    local prompt="$1" default="$2"
    shift 2
    local options=("$@")
    echo -e "    ${prompt}" >&2
    local i=1
    for opt in "${options[@]}"; do
        local marker=""
        [[ "$opt" == "$default" ]] && marker="${_TUI_SHADOW} (current)${_TUI_RESET}"
        echo -e "    ${_TUI_BOLD}${_TUI_ACCENT}  ${i})${_TUI_RESET} ${opt}${marker}" >&2
        i=$((i + 1))
    done
    local result=""
    read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} Choice [1]: ")" result 2>/dev/null </dev/tty \
        || read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} Choice [1]: ")" result \
        || true
    result="${result//[[:space:]]/}"
    # A word is matched against the options; a number picks by position
    local opt
    for opt in "${options[@]}"; do
        [[ "$result" == "$opt" ]] && { echo "$opt"; return 0; }
    done
    if [[ "$result" =~ ^[0-9]{1,3}$ ]]; then
        local idx=$(( 10#$result - 1 ))
        if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "${#options[@]}" ]]; then
            echo "${options[$idx]}"
            return 0
        fi
    fi
    echo "$default"
}

# --- Status messages (4-space indent) ---
_tui_info() {
    echo -e "    ${_TUI_SUCCESS}[✓]${_TUI_RESET} $1"
}

_tui_warn() {
    echo -e "    ${_TUI_WARNING}[!]${_TUI_RESET} $1"
}

_tui_error() {
    echo -e "    ${_TUI_ERROR}[✗]${_TUI_RESET} $1"
}

# --- Section header (◆ prefix) ---
_tui_header() {
    echo -e "    ${_TUI_BOLD}${_TUI_ACCENT}◆ $1${_TUI_RESET}"
}

# --- Setting display (aligned key=value) ---
_tui_setting() {
    printf "    ${_TUI_ACCENT}%-18s${_TUI_RESET} ${_TUI_BOLD}%s${_TUI_RESET}\n" "$1" "$2"
}

# --- Wait for Enter (shadow color) ---
_tui_wait() {
    _tui_pause
}

# --- Warning box (for dangerous operations) ---
# Usage: _tui_warning_box "Title" "message line 1" "message line 2" ...
_tui_warning_box() {
    local title="$1"
    shift
    local lines=("$@")
    local inner_width=$(( _TUI_WIDTH - 8 ))
    local rule
    rule=$(_tui_rule_str "$inner_width")

    echo ""
    echo -e "    ${_TUI_WARNING}╭${rule}╮${_TUI_RESET}"
    local title_pad=$(( inner_width - ${#title} - 4 ))
    (( title_pad < 0 )) && title_pad=0
    echo -e "    ${_TUI_WARNING}│${_TUI_RESET} ${_TUI_BOLD}${_TUI_WARNING}⚠  ${title}${_TUI_RESET}$(printf '%*s' "$title_pad" '')${_TUI_WARNING}│${_TUI_RESET}"
    echo -e "    ${_TUI_WARNING}│$(printf "%-${inner_width}s" "")│${_TUI_RESET}"
    for msg in "${lines[@]}"; do
        local msg_pad=$(( inner_width - ${#msg} - 2 ))
        (( msg_pad < 0 )) && msg_pad=0
        echo -e "    ${_TUI_WARNING}│${_TUI_RESET} ${msg}$(printf '%*s' "$msg_pad" '') ${_TUI_WARNING}│${_TUI_RESET}"
    done
    echo -e "    ${_TUI_WARNING}╰${rule}╯${_TUI_RESET}"
    echo ""
}
