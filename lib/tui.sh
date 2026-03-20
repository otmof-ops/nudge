#!/usr/bin/env bash
# nudge — lib/tui.sh
# TUI rendering — whiptail full-screen dialogs with numbered-list fallback
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

# --- Whiptail/dialog backend ---
_WT_CMD="none"
_WT_H=20
_WT_W=70
_WT_MENU_H=12
_WT_MSG_BUF=""
_WT_BUNNY_TEXT=""

# Interactive TUI flag — controls accumulator behavior for _tui_info/warn/error
_TUI_INTERACTIVE=false

# Menu choice result
_MENU_CHOICE=""

# --- Display file descriptor (fallback mode) ---
_TUI_DISPLAY_FD=""

# --- Check if whiptail interactive mode is active ---
_is_wt_mode() {
    [[ "$_WT_CMD" != "none" ]] && [[ "$_TUI_INTERACTIVE" == "true" ]]
}

_tui_open_display() {
    if [[ -z "$_TUI_DISPLAY_FD" ]] && [[ -w /dev/tty ]] 2>/dev/null; then
        exec 3>/dev/tty 2>/dev/null && _TUI_DISPLAY_FD=3 || true
    fi
}

# --- Output helpers (fallback mode) ---
_tui_out() {
    if [[ -n "$_TUI_DISPLAY_FD" ]]; then
        printf '%s\n' "$*" >&"$_TUI_DISPLAY_FD"
    else
        printf '%s\n' "$*"
    fi
}

_tui_out_n() {
    if [[ -n "$_TUI_DISPLAY_FD" ]]; then
        printf '%s' "$*" >&"$_TUI_DISPLAY_FD"
    else
        printf '%s' "$*"
    fi
}

_tui_out_e() {
    if [[ -n "$_TUI_DISPLAY_FD" ]]; then
        echo -e "$*" >&"$_TUI_DISPLAY_FD"
    else
        echo -e "$*"
    fi
}

# --- Terminal size detection ---
_wt_size() {
    local lines cols
    lines=$(tput lines 2>/dev/null) || lines=24
    cols=$(tput cols 2>/dev/null) || cols=80
    _WT_H=$((lines - 4))
    _WT_W=$((cols - 10))
    [[ "$_WT_H" -lt 20 ]] && _WT_H=20
    [[ "$_WT_W" -lt 60 ]] && _WT_W=60
    [[ "$_WT_H" -gt 40 ]] && _WT_H=40
    [[ "$_WT_W" -gt 100 ]] && _WT_W=100
    _WT_MENU_H=$((_WT_H - 8))
    [[ "$_WT_MENU_H" -lt 6 ]] && _WT_MENU_H=6
}

# --- Build bunny text for whiptail dialogs ---
_wt_bunny_text() {
    local msg1="${1:-}" msg2="${2:-}"
    local text=' (\__/)'$'\n'
    text+=" (='.'=)  ${msg1}"$'\n'
    if [[ -n "$msg2" ]]; then
        text+=" (\")_(\")  ${msg2}"
    else
        text+=' (")_(")'
    fi
    printf '%s' "$text"
}

# --- Color initialization ---
_tui_init() {
    # Detect whiptail or dialog
    if command -v whiptail &>/dev/null; then
        _WT_CMD="whiptail"
    elif command -v dialog &>/dev/null; then
        _WT_CMD="dialog"
    else
        _WT_CMD="none"
    fi

    # Fallback mode needs display fd
    if [[ "$_WT_CMD" == "none" ]]; then
        _tui_open_display
    fi

    if [[ "${_TUI_NO_COLOR:-false}" == "true" ]] || [[ -n "${NO_COLOR:-}" ]] || \
       { [[ "$_WT_CMD" == "none" ]] && [[ -z "$_TUI_DISPLAY_FD" ]] && [[ ! -t 1 ]]; }; then
        _TUI_BOLD='' _TUI_GREEN='' _TUI_YELLOW='' _TUI_CYAN='' _TUI_RED='' _TUI_RESET=''
    else
        _TUI_BOLD='\033[1m'
        _TUI_GREEN='\033[0;32m'
        _TUI_YELLOW='\033[0;33m'
        _TUI_CYAN='\033[0;36m'
        _TUI_RED='\033[0;31m'
        _TUI_RESET='\033[0m'
    fi
    _MENU_CHOICE=""
    _WT_MSG_BUF=""
    trap '_tui_cleanup' EXIT
}

# --- Cleanup on exit ---
_tui_cleanup() {
    # Restore cursor visibility if hidden
    printf '\033[?25h' 2>/dev/null || true
    # Close display fd
    if [[ -n "$_TUI_DISPLAY_FD" ]]; then
        exec 3>&- 2>/dev/null || true
    fi
}

# --- Clear screen ---
_tui_clear() {
    if [[ "$_WT_CMD" != "none" ]]; then
        return  # whiptail redraws full screen
    fi
    if [[ -n "$_TUI_DISPLAY_FD" ]]; then
        printf '\033[2J\033[H' >&"$_TUI_DISPLAY_FD"
    elif [[ -t 1 ]]; then
        printf '\033[2J\033[H'
    fi
}

# --- Render bunny with message ---
_tui_bunny() {
    local msg1="${1:-}" msg2="${2:-}"
    if _is_wt_mode; then
        _WT_BUNNY_TEXT=$(_wt_bunny_text "$msg1" "$msg2")
        return
    fi
    # Fallback / CLI mode
    _tui_clear
    _tui_out ""
    local personality="${BUNNY_PERSONALITY:-disney}"
    if [[ "$personality" != "classic" ]] && type bunny_render &>/dev/null; then
        local rendered
        rendered=$(bunny_render "prompt" "$msg2")
        if [[ -n "$_TUI_DISPLAY_FD" ]]; then
            output_render "$rendered" >&"$_TUI_DISPLAY_FD"
        else
            output_render "$rendered"
        fi
    else
        if [[ -n "$_TUI_DISPLAY_FD" ]]; then
            output_banner "$msg1" "$msg2" >&"$_TUI_DISPLAY_FD"
        else
            output_banner "$msg1" "$msg2"
        fi
    fi
    _tui_out ""
}

# --- Numbered menu / whiptail --menu ---
# Usage: _tui_menu "Item 1" "Item 2" "Item 3"
# Sets _MENU_CHOICE to the selected number (1-N, 0 for last item if Exit/Back)
_tui_menu() {
    local items=("$@")
    if _is_wt_mode; then
        _wt_size
        local wt_args=()
        local text="${_WT_BUNNY_TEXT:-Choose an option:}"
        _WT_BUNNY_TEXT=""
        local i=1
        local menu_h=${#items[@]}
        [[ "$menu_h" -gt "$_WT_MENU_H" ]] && menu_h="$_WT_MENU_H"
        for item in "${items[@]}"; do
            if [[ "$i" -eq "${#items[@]}" ]] && \
               [[ "$item" == "Exit" || "$item" == "Back" || "$item" == "Save & back" || "$item" == "Keep it" ]]; then
                wt_args+=("0" "$item")
            else
                wt_args+=("$i" "$item")
                i=$((i + 1))
            fi
        done
        local result
        result=$("$_WT_CMD" --backtitle "nudge setup v${VERSION:-2.0.0}" \
            --title "" --menu "$text" \
            "$_WT_H" "$_WT_W" "$menu_h" \
            "${wt_args[@]}" 3>&1 1>&2 2>&3) || result="0"
        _MENU_CHOICE="$result"
        return
    fi
    # Fallback mode
    local i=1
    for item in "${items[@]}"; do
        if [[ "$i" -eq "${#items[@]}" ]] && \
           [[ "$item" == "Exit" || "$item" == "Back" || "$item" == "Save & back" || "$item" == "Keep it" ]]; then
            _tui_out_e "  ${_TUI_CYAN}[0]${_TUI_RESET} ${item}"
        else
            _tui_out_e "  ${_TUI_CYAN}[$i]${_TUI_RESET} ${item}"
            i=$((i + 1))
        fi
    done
    _tui_out ""
    _tui_out_n "  > "
    read -r _MENU_CHOICE </dev/tty 2>/dev/null || read -r _MENU_CHOICE
    _MENU_CHOICE="${_MENU_CHOICE:-0}"
}

# --- Yes/No confirmation ---
_tui_confirm() {
    local prompt="$1" default="${2:-true}"
    if [[ "$_WT_CMD" != "none" ]]; then
        _wt_size
        local wt_args=("--backtitle" "nudge setup v${VERSION:-2.0.0}")
        [[ "$default" == "false" ]] && wt_args+=("--defaultno")
        wt_args+=("--yesno" "$prompt" "8" "$_WT_W")
        if "$_WT_CMD" "${wt_args[@]}"; then
            echo "true"
        else
            echo "false"
        fi
        return
    fi
    # Fallback mode
    local hint
    if [[ "$default" == "true" ]]; then hint="Y/n"; else hint="y/N"; fi
    _tui_out_n "  ${prompt} ${_TUI_CYAN}[${hint}]${_TUI_RESET}: "
    local answer
    read -r answer </dev/tty 2>/dev/null || read -r answer
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
    if [[ "$_WT_CMD" != "none" ]]; then
        _wt_size
        local result
        result=$("$_WT_CMD" --backtitle "nudge setup v${VERSION:-2.0.0}" \
            --inputbox "$prompt" 8 "$_WT_W" "$default" 3>&1 1>&2 2>&3) || result="$default"
        echo "$result"
        return
    fi
    # Fallback mode
    _tui_out_n "  ${prompt} ${_TUI_CYAN}[${default}]${_TUI_RESET}: "
    local answer
    read -r answer </dev/tty 2>/dev/null || read -r answer
    echo "${answer:-$default}"
}

# --- Numbered option picker / whiptail --radiolist ---
_tui_choice() {
    local prompt="$1" default="$2"
    shift 2
    local options=("$@")
    if [[ "$_WT_CMD" != "none" ]]; then
        _wt_size
        local wt_args=()
        for opt in "${options[@]}"; do
            local state="OFF"
            [[ "$opt" == "$default" ]] && state="ON"
            wt_args+=("$opt" "" "$state")
        done
        local menu_h=${#options[@]}
        [[ "$menu_h" -gt "$_WT_MENU_H" ]] && menu_h="$_WT_MENU_H"
        local result
        result=$("$_WT_CMD" --backtitle "nudge setup v${VERSION:-2.0.0}" \
            --radiolist "$prompt" "$_WT_H" "$_WT_W" "$menu_h" \
            "${wt_args[@]}" 3>&1 1>&2 2>&3) || result="$default"
        echo "$result"
        return
    fi
    # Fallback mode
    _tui_out_e "  ${prompt}"
    local i=1
    for opt in "${options[@]}"; do
        local marker=""
        [[ "$opt" == "$default" ]] && marker=" (default)"
        _tui_out_e "    ${_TUI_CYAN}[$i]${_TUI_RESET} ${opt}${marker}"
        i=$((i + 1))
    done
    _tui_out_n "  Choice ${_TUI_CYAN}[1]${_TUI_RESET}: "
    local result
    read -r result </dev/tty 2>/dev/null || read -r result
    local idx=$(( ${result:-1} - 1 ))
    if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "${#options[@]}" ]]; then
        echo "${options[$idx]}"
    else
        echo "$default"
    fi
}

# --- Status messages (accumulate in whiptail mode, print in fallback) ---
_tui_info() {
    if _is_wt_mode; then
        _WT_MSG_BUF+="[OK] $1"$'\n'
        return
    fi
    _tui_out_e "  ${_TUI_GREEN}[✓]${_TUI_RESET} $1"
}

_tui_warn() {
    if _is_wt_mode; then
        _WT_MSG_BUF+="[!]  $1"$'\n'
        return
    fi
    _tui_out_e "  ${_TUI_YELLOW}[!]${_TUI_RESET} $1"
}

_tui_error() {
    if _is_wt_mode; then
        _WT_MSG_BUF+="[X]  $1"$'\n'
        return
    fi
    _tui_out_e "  ${_TUI_RED}[✗]${_TUI_RESET} $1"
}

# --- Section header ---
_tui_header() {
    if _is_wt_mode; then
        _WT_MSG_BUF+=$'\n'"--- $1 ---"$'\n'
        return
    fi
    _tui_out_e "  ${_TUI_BOLD}${_TUI_CYAN}$1${_TUI_RESET}"
}

# --- Wait / flush accumulated messages ---
_tui_wait() {
    if _is_wt_mode; then
        if [[ -n "$_WT_MSG_BUF" ]]; then
            _wt_size
            local wt_args=("--backtitle" "nudge setup v${VERSION:-2.0.0}" "--title" "")
            [[ "$_WT_CMD" == "whiptail" ]] && wt_args+=("--scrolltext")
            wt_args+=("--msgbox" "$_WT_MSG_BUF" "$_WT_H" "$_WT_W")
            "$_WT_CMD" "${wt_args[@]}" 3>&1 1>&2 2>&3 || true
            _WT_MSG_BUF=""
        fi
        return
    fi
    _tui_out ""
    _tui_out_n "  Press Enter to continue..."
    read -r </dev/tty 2>/dev/null || read -r
}

# --- Setting display ---
_tui_setting() {
    if _is_wt_mode; then
        _WT_MSG_BUF+="  $1 = $2"$'\n'
        return
    fi
    _tui_out_e "    ${_TUI_CYAN}$1${_TUI_RESET} = ${_TUI_BOLD}$2${_TUI_RESET}"
}

# --- Whiptail msgbox (direct, for emotional/farewell displays) ---
_wt_msgbox() {
    local text="${1:-}"
    if [[ "$_WT_CMD" != "none" ]]; then
        _wt_size
        "$_WT_CMD" --backtitle "nudge setup v${VERSION:-2.0.0}" \
            --title "" --msgbox "$text" "$_WT_H" "$_WT_W" 3>&1 1>&2 2>&3 || true
        return
    fi
    # Fallback
    echo ""
    echo "$text"
    echo ""
    _tui_out_n "  Press Enter to continue..."
    read -r </dev/tty 2>/dev/null || read -r
}

# --- Whiptail checklist (multiple bool toggles) ---
_wt_checklist() {
    local text="$1"
    shift
    if [[ "$_WT_CMD" == "none" ]]; then
        return 1
    fi
    _wt_size
    local menu_h=$(( $# / 3 ))
    [[ "$menu_h" -gt "$_WT_MENU_H" ]] && menu_h="$_WT_MENU_H"
    local result
    result=$("$_WT_CMD" --backtitle "nudge setup v${VERSION:-2.0.0}" \
        --title "" --checklist "$text" \
        "$_WT_H" "$_WT_W" "$menu_h" "$@" 3>&1 1>&2 2>&3) || true
    echo "$result"
}

# --- Whiptail radiolist (enum selection) ---
_wt_radiolist() {
    local text="$1"
    shift
    if [[ "$_WT_CMD" == "none" ]]; then
        return 1
    fi
    _wt_size
    local menu_h=$(( $# / 3 ))
    [[ "$menu_h" -gt "$_WT_MENU_H" ]] && menu_h="$_WT_MENU_H"
    local result
    result=$("$_WT_CMD" --backtitle "nudge setup v${VERSION:-2.0.0}" \
        --title "" --radiolist "$text" \
        "$_WT_H" "$_WT_W" "$menu_h" "$@" 3>&1 1>&2 2>&3) || true
    echo "$result"
}

# --- Whiptail gauge (progress bar) ---
_wt_gauge() {
    local text="$1" percent="$2"
    if [[ "$_WT_CMD" == "none" ]]; then
        printf '  %s (%d%%)\n' "$text" "$percent"
        return
    fi
    _wt_size
    echo "$percent" | "$_WT_CMD" --backtitle "nudge setup v${VERSION:-2.0.0}" \
        --gauge "$text" 6 "$_WT_W" "$percent" 3>&1 1>&2 2>&3 || true
}
