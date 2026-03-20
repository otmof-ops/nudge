#!/usr/bin/env bash
# nudge — lib/tui.sh
# TUI rendering — pure bash numbered menus
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

# --- Menu choice result ---
_MENU_CHOICE=""

# --- Color codes ---
_TUI_BOLD='' _TUI_GREEN='' _TUI_YELLOW='' _TUI_CYAN='' _TUI_RED='' _TUI_RESET=''

# --- Initialize colors ---
_tui_init() {
    if [[ "${_TUI_NO_COLOR:-false}" == "true" ]] || [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
        _TUI_BOLD='' _TUI_GREEN='' _TUI_YELLOW='' _TUI_CYAN='' _TUI_RED='' _TUI_RESET=''
    else
        _TUI_BOLD='\033[1m'
        _TUI_GREEN='\033[0;32m'
        _TUI_YELLOW='\033[0;33m'
        _TUI_CYAN='\033[0;36m'
        _TUI_RED='\033[0;31m'
        _TUI_RESET='\033[0m'
    fi
}

# --- Clear screen ---
_tui_clear() {
    [[ -t 1 ]] && printf '\033[2J\033[H'
}

# --- Render bunny with message ---
_tui_bunny() {
    local msg1="${1:-}" msg2="${2:-}"
    _tui_clear
    echo ""
    echo " (\\__/)"
    echo " (='.'=)  ${msg1}"
    if [[ -n "$msg2" ]]; then
        echo " (\")_(\")  ${msg2}"
    else
        echo " (\")_(\")"
    fi
    echo ""
}

# --- Numbered menu ---
# Usage: _tui_menu "Item 1" "Item 2" "Exit"
# Last item auto-numbered 0 if Exit/Back/Save & back
# Sets _MENU_CHOICE to selected number
_tui_menu() {
    local items=("$@")
    local i=1
    for item in "${items[@]}"; do
        if [[ "$i" -eq "${#items[@]}" ]] && \
           [[ "$item" == "Exit" || "$item" == "Back" || "$item" == "Save & back" || "$item" == "Keep it" ]]; then
            echo -e " ${_TUI_CYAN}0)${_TUI_RESET} ${item}"
        else
            echo -e " ${_TUI_CYAN}${i})${_TUI_RESET} ${item}"
            i=$((i + 1))
        fi
    done
    echo ""
    read -rp " > " _MENU_CHOICE </dev/tty 2>/dev/null || read -rp " > " _MENU_CHOICE
    _MENU_CHOICE="${_MENU_CHOICE:-0}"
}

# --- Yes/No confirmation ---
_tui_confirm() {
    local prompt="$1" default="${2:-true}"
    local hint
    if [[ "$default" == "true" ]]; then hint="Y/n"; else hint="y/N"; fi
    local answer
    read -rp " ${prompt} [${hint}]: " answer </dev/tty 2>/dev/null || read -rp " ${prompt} [${hint}]: " answer
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
    read -rp " ${prompt} [${default}]: " answer </dev/tty 2>/dev/null || read -rp " ${prompt} [${default}]: " answer
    echo "${answer:-$default}"
}

# --- Numbered option picker ---
_tui_choice() {
    local prompt="$1" default="$2"
    shift 2
    local options=("$@")
    echo -e " ${prompt}"
    local i=1
    for opt in "${options[@]}"; do
        local marker=""
        [[ "$opt" == "$default" ]] && marker=" (current)"
        echo -e "   ${_TUI_CYAN}${i})${_TUI_RESET} ${opt}${marker}"
        i=$((i + 1))
    done
    local result
    read -rp " Choice [1]: " result </dev/tty 2>/dev/null || read -rp " Choice [1]: " result
    local idx=$(( ${result:-1} - 1 ))
    if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "${#options[@]}" ]]; then
        echo "${options[$idx]}"
    else
        echo "$default"
    fi
}

# --- Status messages ---
_tui_info() {
    echo -e " ${_TUI_GREEN}[✓]${_TUI_RESET} $1"
}

_tui_warn() {
    echo -e " ${_TUI_YELLOW}[!]${_TUI_RESET} $1"
}

_tui_error() {
    echo -e " ${_TUI_RED}[✗]${_TUI_RESET} $1"
}

# --- Section header ---
_tui_header() {
    echo -e " ${_TUI_BOLD}${_TUI_CYAN}$1${_TUI_RESET}"
}

# --- Setting display ---
_tui_setting() {
    echo -e "   ${_TUI_CYAN}$1${_TUI_RESET} = ${_TUI_BOLD}$2${_TUI_RESET}"
}

# --- Wait for Enter ---
_tui_wait() {
    echo ""
    read -rp " Press Enter to continue..." </dev/tty 2>/dev/null || read -rp " Press Enter to continue..."
}
