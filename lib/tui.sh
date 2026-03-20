#!/usr/bin/env bash
# nudge — lib/tui.sh
# TUI rendering — VOIDWAVE-style visual primitives
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

# --- Menu choice result ---
_MENU_CHOICE=""

# --- Color codes ---
_TUI_BOLD='' _TUI_GREEN='' _TUI_YELLOW='' _TUI_CYAN='' _TUI_RED='' _TUI_RESET=''
_TUI_PURPLE='' _TUI_WHITE='' _TUI_GRAY='' _TUI_BORDER=''
# Semantic aliases (set in _tui_init)
_TUI_SUCCESS='' _TUI_ERROR='' _TUI_WARNING='' _TUI_INFO=''
_TUI_SHADOW='' _TUI_PROMPT=''

# --- Terminal width ---
_TUI_WIDTH=60

# --- Initialize colors ---
_tui_init() {
    # Detect terminal width
    if command -v tput &>/dev/null && [[ -t 1 ]]; then
        _TUI_WIDTH=$(tput cols 2>/dev/null || echo 60)
        (( _TUI_WIDTH > 80 )) && _TUI_WIDTH=80
        (( _TUI_WIDTH < 40 )) && _TUI_WIDTH=40
    fi

    if [[ "${_TUI_NO_COLOR:-false}" == "true" ]] || [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
        _TUI_BOLD='' _TUI_GREEN='' _TUI_YELLOW='' _TUI_CYAN='' _TUI_RED='' _TUI_RESET=''
        _TUI_PURPLE='' _TUI_WHITE='' _TUI_GRAY='' _TUI_BORDER=''
        _TUI_SUCCESS='' _TUI_ERROR='' _TUI_WARNING='' _TUI_INFO=''
        _TUI_SHADOW='' _TUI_PROMPT=''
    else
        _TUI_BOLD='\033[1m'
        _TUI_GREEN='\033[0;32m'
        _TUI_YELLOW='\033[0;33m'
        _TUI_CYAN='\033[0;36m'
        _TUI_RED='\033[0;31m'
        _TUI_PURPLE='\033[0;35m'
        _TUI_WHITE='\033[1;37m'
        _TUI_GRAY='\033[0;90m'
        _TUI_BORDER='\033[0;36m'
        _TUI_RESET='\033[0m'
        # Semantic aliases
        _TUI_SUCCESS="$_TUI_GREEN"
        _TUI_ERROR="$_TUI_RED"
        _TUI_WARNING="$_TUI_YELLOW"
        _TUI_INFO="$_TUI_CYAN"
        _TUI_SHADOW="$_TUI_GRAY"
        _TUI_PROMPT="$_TUI_YELLOW"
    fi
}

# --- Clear screen ---
_tui_clear() {
    [[ -t 1 ]] && printf '\033[2J\033[H'
}

# --- Horizontal separator ---
# Usage: _tui_separator [width] [char]
_tui_separator() {
    local width="${1:-$(( _TUI_WIDTH - 4 ))}"
    local char="${2:-─}"
    local line=""
    for (( i=0; i<width; i++ )); do line+="$char"; done
    echo -e "    ${_TUI_SHADOW}${line}${_TUI_RESET}"
}

# --- Double-line box header ---
# Usage: _tui_draw_header "TITLE" ["subtitle"]
_tui_draw_header() {
    local title="$1"
    local subtitle="${2:-}"
    local inner_width=$(( _TUI_WIDTH - 8 ))
    local title_len=${#title}
    local pad_total=$(( inner_width - title_len ))
    local pad_left=$(( pad_total / 2 ))
    local pad_right=$(( pad_total - pad_left ))

    local top_line="╔"
    local bot_line="╚"
    for (( i=0; i<inner_width; i++ )); do
        top_line+="═"
        bot_line+="═"
    done
    top_line+="╗"
    bot_line+="╝"

    local left_pad="" right_pad=""
    for (( i=0; i<pad_left; i++ )); do left_pad+=" "; done
    for (( i=0; i<pad_right; i++ )); do right_pad+=" "; done

    echo ""
    echo -e "    ${_TUI_BORDER}${top_line}${_TUI_RESET}"
    echo -e "    ${_TUI_BORDER}║${_TUI_RESET}${left_pad}${_TUI_BOLD}${_TUI_WHITE}${title}${_TUI_RESET}${right_pad}${_TUI_BORDER}║${_TUI_RESET}"
    echo -e "    ${_TUI_BORDER}${bot_line}${_TUI_RESET}"

    if [[ -n "$subtitle" ]]; then
        local sub_len=${#subtitle}
        local sub_pad=$(( (inner_width - sub_len) / 2 + 4 ))
        local sub_spaces=""
        for (( i=0; i<sub_pad; i++ )); do sub_spaces+=" "; done
        echo -e "${sub_spaces}${_TUI_SHADOW}${subtitle}${_TUI_RESET}"
    fi
}

# --- Menu header ---
# Usage: _tui_menu_header "TITLE"
_tui_menu_header() {
    local title="$1"
    echo ""
    echo -e "    ${_TUI_BOLD}${_TUI_CYAN}◆ ${title}${_TUI_RESET}"
    _tui_separator
}

# --- Menu section ---
# Usage: _tui_menu_section "Section Name"
_tui_menu_section() {
    local name="$1"
    echo -e "    ${_TUI_BOLD}${_TUI_PURPLE}▸ ${name}${_TUI_RESET}"
}

# --- Menu item with description ---
# Usage: _tui_menu_item NUMBER "Label" ["description"]
_tui_menu_item() {
    local num="$1"
    local label="$2"
    local desc="${3:-}"
    local num_display
    num_display=$(printf "%2s" "$num")

    if [[ -n "$desc" ]]; then
        local label_pad=22
        local padded_label
        padded_label=$(printf "%-${label_pad}s" "$label")
        echo -e "    ${_TUI_CYAN}${num_display})${_TUI_RESET} ${padded_label} ${_TUI_SHADOW}${desc}${_TUI_RESET}"
    else
        echo -e "    ${_TUI_CYAN}${num_display})${_TUI_RESET} ${label}"
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
_tui_prompt_choice() {
    local max="${1:-}"
    local hint=""
    [[ -n "$max" ]] && hint=" [0-${max}]"
    echo ""
    read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} Select${hint}: ")" _MENU_CHOICE </dev/tty 2>/dev/null \
        || read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} Select${hint}: ")" _MENU_CHOICE
    _MENU_CHOICE="${_MENU_CHOICE:-0}"
}

# --- Spinner ---
# Usage: _tui_spinner PID ["message"]
_tui_spinner() {
    local pid="$1"
    local msg="${2:-Working...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r    ${_TUI_CYAN}%s${_TUI_RESET} %s" "${frames[$i]}" "$msg"
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

    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done

    if [[ -n "$label" ]]; then
        printf "    ${_TUI_BOLD}%-14s${_TUI_RESET} ${_TUI_CYAN}%s${_TUI_RESET} %3d%%\n" "$label" "$bar" "$percent"
    else
        printf "    ${_TUI_CYAN}%s${_TUI_RESET} %3d%%\n" "$bar" "$percent"
    fi
}

# --- Operation header ---
# Usage: _tui_operation_header "Title"
_tui_operation_header() {
    local title="$1"
    local title_len=${#title}
    local line=""
    for (( i=0; i<title_len+2; i++ )); do line+="─"; done
    echo -e "    ${_TUI_BORDER}┌${line}┐${_TUI_RESET}"
    echo -e "    ${_TUI_BORDER}│${_TUI_RESET} ${_TUI_BOLD}${_TUI_WHITE}${title}${_TUI_RESET} ${_TUI_BORDER}│${_TUI_RESET}"
    echo -e "    ${_TUI_BORDER}└${line}┘${_TUI_RESET}"
}

# --- Pause / press Enter ---
# Usage: _tui_pause
_tui_pause() {
    echo ""
    read -rp "$(echo -e "    ${_TUI_SHADOW}Press Enter to continue...${_TUI_RESET}")" </dev/tty 2>/dev/null \
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
    # Find longest key
    for (( i=0; i<${#args[@]}; i+=2 )); do
        local key="${args[$i]}"
        (( ${#key} > max_key_len )) && max_key_len=${#key}
    done
    # Render rows
    for (( i=0; i<${#args[@]}; i+=2 )); do
        local key="${args[$i]}"
        local val="${args[$i+1]:-}"
        printf "    ${_TUI_CYAN}%-${max_key_len}s${_TUI_RESET}  ${_TUI_BOLD}%s${_TUI_RESET}\n" "$key" "$val"
    done
}

# --- Render bunny with message (framed) ---
_tui_bunny() {
    local msg1="${1:-}" msg2="${2:-}"
    _tui_clear

    # Calculate frame dimensions
    local bunny_width=8  # Width of bunny art
    local msg_len=${#msg1}
    local msg2_len=${#msg2}
    local content_width=$(( bunny_width + 2 + (msg_len > msg2_len ? msg_len : msg2_len) ))
    (( content_width < 30 )) && content_width=30
    (( content_width > _TUI_WIDTH - 8 )) && content_width=$(( _TUI_WIDTH - 8 ))

    echo ""
    echo -e "    ${_TUI_SHADOW}(\\(\\${_TUI_RESET}"
    echo -e "    ${_TUI_SHADOW}( -.-)${_TUI_RESET}  ${_TUI_BOLD}${msg1}${_TUI_RESET}"
    if [[ -n "$msg2" ]]; then
        echo -e "    ${_TUI_SHADOW}o_(\")(\")\${_TUI_RESET}  ${_TUI_SHADOW}${msg2}${_TUI_RESET}"
    else
        echo -e "    ${_TUI_SHADOW}o_(\")(\")${_TUI_RESET}"
    fi
    echo ""
}

# --- Numbered menu (rewritten with new primitives) ---
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

    local max=$(( has_footer == true ? count - 1 : count ))
    _tui_prompt_choice "$max"
}

# --- Yes/No confirmation ---
_tui_confirm() {
    local prompt="$1" default="${2:-true}"
    local hint
    if [[ "$default" == "true" ]]; then hint="Y/n"; else hint="y/N"; fi
    local answer
    read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} ${prompt} [${hint}]: ")" answer </dev/tty 2>/dev/null \
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
    read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} ${prompt} [${default}]: ")" answer </dev/tty 2>/dev/null \
        || read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} ${prompt} [${default}]: ")" answer
    echo "${answer:-$default}"
}

# --- Numbered option picker ---
_tui_choice() {
    local prompt="$1" default="$2"
    shift 2
    local options=("$@")
    echo -e "    ${prompt}"
    local i=1
    for opt in "${options[@]}"; do
        local marker=""
        [[ "$opt" == "$default" ]] && marker="${_TUI_SHADOW} (current)${_TUI_RESET}"
        echo -e "    ${_TUI_CYAN}  ${i})${_TUI_RESET} ${opt}${marker}"
        i=$((i + 1))
    done
    local result
    read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} Choice [1]: ")" result </dev/tty 2>/dev/null \
        || read -rp "$(echo -e "    ${_TUI_PROMPT}▶${_TUI_RESET} Choice [1]: ")" result
    local idx=$(( ${result:-1} - 1 ))
    if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "${#options[@]}" ]]; then
        echo "${options[$idx]}"
    else
        echo "$default"
    fi
}

# --- Status messages (4-space indent, VOIDWAVE style) ---
_tui_info() {
    echo -e "    ${_TUI_SUCCESS}[✓]${_TUI_RESET} $1"
}

_tui_warn() {
    echo -e "    ${_TUI_WARNING}[!]${_TUI_RESET} $1"
}

_tui_error() {
    echo -e "    ${_TUI_ERROR}[✗]${_TUI_RESET} $1"
}

# --- Section header (◆ prefix + underline) ---
_tui_header() {
    echo -e "    ${_TUI_BOLD}${_TUI_CYAN}◆ $1${_TUI_RESET}"
}

# --- Setting display (aligned key=value) ---
_tui_setting() {
    printf "    ${_TUI_CYAN}%-18s${_TUI_RESET} ${_TUI_BOLD}%s${_TUI_RESET}\n" "$1" "$2"
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
    local line_char="─"
    local top_line="" bot_line=""
    for (( i=0; i<inner_width; i++ )); do
        top_line+="$line_char"
        bot_line+="$line_char"
    done

    echo ""
    echo -e "    ${_TUI_WARNING}┌${top_line}┐${_TUI_RESET}"
    local title_pad=$(( inner_width - ${#title} - 4 ))
    local title_spaces=""
    for (( i=0; i<title_pad; i++ )); do title_spaces+=" "; done
    echo -e "    ${_TUI_WARNING}│${_TUI_RESET} ${_TUI_BOLD}${_TUI_WARNING}⚠  ${title}${_TUI_RESET}${title_spaces}${_TUI_WARNING}│${_TUI_RESET}"
    echo -e "    ${_TUI_WARNING}│$(printf "%-${inner_width}s" "")│${_TUI_RESET}"
    for msg in "${lines[@]}"; do
        local msg_pad=$(( inner_width - ${#msg} - 2 ))
        local msg_spaces=""
        for (( i=0; i<msg_pad; i++ )); do msg_spaces+=" "; done
        echo -e "    ${_TUI_WARNING}│${_TUI_RESET} ${msg}${msg_spaces} ${_TUI_WARNING}│${_TUI_RESET}"
    done
    echo -e "    ${_TUI_WARNING}└${bot_line}┘${_TUI_RESET}"
    echo ""
}
