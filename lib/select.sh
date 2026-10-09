#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/select.sh
# The update selection menu: every source of updates (a "list": system
# packages, Flatpak, Snap) with its subcategories (security, critical, other;
# applications, runtimes), select-all at every level, and per-package picking.
# A pure data model plus a line-based TUI: no curses, no dialog binary.

set -euo pipefail

# --- Model: parallel arrays, one row per update ---
_SEL_LIST=()      # system | flatpak | snap
_SEL_SUB=()       # critical | security | standard | app | runtime | snap
_SEL_LABEL=()     # what the user sees
_SEL_TARGET=()    # what the package manager gets
_SEL_ON=()        # 1 selected, 0 not
_SEL_INFO=()      # what sits beside the label: the versions
_SEL_ATOMIC=" "   # lists that only update as a whole, e.g. " system " on pacman
_SEL_LIST_ORDER=(system flatpak snap)
declare -gA _SEL_LIST_TITLE=(
    [system]="System packages"
    [flatpak]="Flatpak"
    [snap]="Snap"
)
declare -gA _SEL_SUB_TITLE=(
    [critical]="Critical system packages"
    [security]="Security updates"
    [standard]="Other updates"
    [app]="Applications"
    [runtime]="Runtimes"
    [snap]="Snaps"
)
declare -gA _SEL_SUB_ORDER=(
    [system]="critical security standard"
    [flatpak]="app runtime"
    [snap]="snap"
)
# Rendering maps (rebuilt by _select_build_map)
_SEL_MAP_LIST=()            # index n-1 -> list name shown as "n)"
declare -gA _SEL_MAP_SUB=() # "1a" -> "list sub"
_SEL_VIEW_IDX=()            # rows of the subcategory currently viewed

# --- Model operations ---

select_reset() {
    _SEL_LIST=(); _SEL_SUB=(); _SEL_LABEL=(); _SEL_TARGET=(); _SEL_ON=(); _SEL_INFO=()
    _SEL_ATOMIC=" "
}

# Usage: select_add <list> <sub> <label> <target> [info]
select_add() {
    _SEL_LIST+=("$1"); _SEL_SUB+=("$2"); _SEL_LABEL+=("$3"); _SEL_TARGET+=("$4"); _SEL_ON+=(1); _SEL_INFO+=("${5:-}")
}

select_size() { echo "${#_SEL_LIST[@]}"; }

select_set_list_title() { _SEL_LIST_TITLE["$1"]="$2"; }

# A list that cannot be applied partially (pacman: never partial-upgrade)
select_mark_atomic() { _SEL_ATOMIC+="$1 "; }
select_is_atomic() { [[ "$_SEL_ATOMIC" == *" $1 "* ]]; }

# Usage: select_count <list> [sub]  ->  "<selected> <total>"
select_count() {
    local list="$1" sub="${2:-}" i sel=0 tot=0
    for i in "${!_SEL_LIST[@]}"; do
        [[ "${_SEL_LIST[$i]}" == "$list" ]] || continue
        [[ -z "$sub" || "${_SEL_SUB[$i]}" == "$sub" ]] || continue
        tot=$((tot + 1))
        [[ "${_SEL_ON[$i]}" == "1" ]] && sel=$((sel + 1))
    done
    echo "$sel $tot"
}

# Usage: select_set <list> <sub-or-empty> <0|1>
select_set() {
    local list="$1" sub="$2" value="$3" i
    for i in "${!_SEL_LIST[@]}"; do
        [[ "${_SEL_LIST[$i]}" == "$list" ]] || continue
        [[ -z "$sub" || "${_SEL_SUB[$i]}" == "$sub" ]] || continue
        _SEL_ON[$i]="$value"
    done
}

select_set_all() {
    local value="$1" i
    for i in "${!_SEL_ON[@]}"; do _SEL_ON[$i]="$value"; done
}

select_toggle_item() {
    local i="$1"
    [[ -n "${_SEL_ON[$i]+x}" ]] || return 1
    if [[ "${_SEL_ON[$i]}" == "1" ]]; then _SEL_ON[$i]=0; else _SEL_ON[$i]=1; fi
}

# Toggle a whole list or subcategory: all on -> all off, anything else -> all on
select_toggle() {
    local list="$1" sub="${2:-}" sel tot
    read -r sel tot <<< "$(select_count "$list" "$sub")"
    [[ "$tot" -eq 0 ]] && return 0
    if [[ "$sel" -eq "$tot" ]]; then
        select_set "$list" "$sub" 0
    else
        select_set "$list" "$sub" 1
    fi
}

# Usage: select_targets <list>  -> selected targets, one per line
select_targets() {
    local list="$1" i
    for i in "${!_SEL_LIST[@]}"; do
        [[ "${_SEL_LIST[$i]}" == "$list" && "${_SEL_ON[$i]}" == "1" ]] || continue
        printf '%s\n' "${_SEL_TARGET[$i]}"
    done
}

# 0 when every row of the list is selected (and the list is not empty)
select_all_on() {
    local sel tot
    read -r sel tot <<< "$(select_count "$1")"
    [[ "$tot" -gt 0 && "$sel" -eq "$tot" ]]
}

# 0 when at least one row of the list is selected
select_any_on() {
    local sel tot
    read -r sel tot <<< "$(select_count "$1")"
    [[ "$sel" -gt 0 ]]
}

# Usage: select_apply_scope all|important|system|flatpak|snap|pick
# What the dialog's scope picker chose: everything, the critical and security
# system packages only, one source only, or everything ticked for the menu.
select_apply_scope() {
    case "${1:-all}" in
        all|pick)
            select_set_all 1 ;;
        important)
            select_set_all 0
            if select_is_atomic system; then
                # pacman never partially upgrades: the whole system list or nothing
                select_set system "" 1
            else
                select_set system critical 1
                select_set system security 1
            fi ;;
        system|flatpak|snap)
            select_set_all 0
            select_set "$1" "" 1 ;;
        *) return 1 ;;
    esac
}

# 0 when the list has rows at all
select_has() {
    local sel tot
    read -r sel tot <<< "$(select_count "$1")"
    [[ "$tot" -gt 0 ]]
}

# --- Rendering ---

# Cut a label to a width, with an ellipsis
_select_fit() {
    local s="${1:-}" max="${2:-30}"
    if [[ "${#s}" -gt "$max" ]]; then printf '%s…' "${s:0:$((max - 1))}"; else printf '%s' "$s"; fi
}

# The marker kind for a subcategory
_select_sub_kind() {
    case "${1:-}" in
        critical|security) printf '%s' "$1" ;;
        app|runtime)       printf 'flatpak' ;;
        snap)              printf 'snap' ;;
        *)                 printf 'standard' ;;
    esac
}

# A tick box without lib/tui.sh (the tests source both; the runner has both)
_select_box() {
    if declare -F _tui_tick >/dev/null 2>&1; then _tui_tick "$1" "$2"; return 0; fi
    local sel="$1" tot="$2"
    if [[ "$tot" -eq 0 || "$sel" -eq 0 ]]; then printf '[ ]'
    elif [[ "$sel" -eq "$tot" ]]; then printf '[✓]'
    else printf '[-]'
    fi
}
_select_badge() {
    if declare -F _tui_badge >/dev/null 2>&1; then _tui_badge "$@"; else printf ' '; fi
}
_select_key() {
    if declare -F _tui_key >/dev/null 2>&1; then _tui_key "$@"; else printf '%s  %s' "$1" "${2:-}"; fi
}

# Build the number/letter map for the visible lists and subcategories
_select_build_map() {
    _SEL_MAP_LIST=()
    _SEL_MAP_SUB=()
    local list sub n=0 letters="abcdefghij" li sel tot
    for list in "${_SEL_LIST_ORDER[@]}"; do
        read -r sel tot <<< "$(select_count "$list")"
        [[ "$tot" -eq 0 ]] && continue
        n=$((n + 1))
        _SEL_MAP_LIST+=("$list")
        li=0
        for sub in ${_SEL_SUB_ORDER[$list]}; do
            read -r sel tot <<< "$(select_count "$list" "$sub")"
            [[ "$tot" -eq 0 ]] && continue
            _SEL_MAP_SUB["${n}${letters:$li:1}"]="$list $sub"
            li=$((li + 1))
        done
    done
}

# The overview: lists with their subcategories and counts
select_render() {
    _select_build_map
    local c_key="${_TUI_BOLD:-}${_TUI_ACCENT:-}" c_dim="${_TUI_SHADOW:-}" c_bold="${_TUI_BOLD:-}" c_warn="${_TUI_WARNING:-}" c_reset="${_TUI_RESET:-}"
    printf '\n    %b◆ CHOOSE WHAT TO UPDATE%b\n' "$c_key" "$c_reset"
    _tui_separator 2>/dev/null || true
    local n=0 list sub key sel tot letters="abcdefghij" li
    for list in "${_SEL_MAP_LIST[@]}"; do
        n=$((n + 1))
        read -r sel tot <<< "$(select_count "$list")"
        printf '    %b%2d)%b %s %b%-30s%b %b%3d of %-3d%b\n' \
            "$c_key" "$n" "$c_reset" "$(_select_box "$sel" "$tot")" \
            "$c_bold" "$(_select_fit "${_SEL_LIST_TITLE[$list]}" 30)" "$c_reset" "$c_dim" "$sel" "$tot" "$c_reset"
        li=0
        for sub in ${_SEL_SUB_ORDER[$list]}; do
            read -r sel tot <<< "$(select_count "$list" "$sub")"
            [[ "$tot" -eq 0 ]] && continue
            key="${n}${letters:$li:1}"
            li=$((li + 1))
            printf '        %b%3s)%b %s %s %-26s %b%3d of %-3d%b\n' \
                "$c_key" "$key" "$c_reset" "$(_select_box "$sel" "$tot")" \
                "$(_select_badge "$(_select_sub_kind "$sub")")" "$(_select_fit "${_SEL_SUB_TITLE[$sub]}" 26)" \
                "$c_dim" "$sel" "$tot" "$c_reset"
        done
        if select_is_atomic "$list"; then
            printf '        %b    this package manager updates everything or nothing; pick the whole list%b\n' "$c_warn" "$c_reset"
        fi
    done
    _tui_separator 2>/dev/null || true
    printf '    %s   %s   %s   %s\n' "$(_select_key a 'select all')" "$(_select_key n 'select none')" \
        "$(_select_key 1 'toggle a list')" "$(_select_key 1a 'toggle a subcategory')"
    printf '    %s\n' "$(_select_key 'v 1a' 'pick single packages inside a subcategory')"
    printf '    %s   %s\n' "$(_select_key Enter 'update what is ticked')" "$(_select_key q 'cancel, update nothing')"
}

# One subcategory, numbered, paged
_select_render_sub() {
    local list="$1" sub="$2" page="$3" per="${4:-20}"
    local c_key="${_TUI_BOLD:-}${_TUI_ACCENT:-}" c_dim="${_TUI_SHADOW:-}" c_reset="${_TUI_RESET:-}"
    _SEL_VIEW_IDX=()
    local i
    for i in "${!_SEL_LIST[@]}"; do
        [[ "${_SEL_LIST[$i]}" == "$list" && "${_SEL_SUB[$i]}" == "$sub" ]] && _SEL_VIEW_IDX+=("$i")
    done
    local total=${#_SEL_VIEW_IDX[@]}
    local pages=$(( (total + per - 1) / per ))
    [[ "$pages" -lt 1 ]] && pages=1
    local start=$((page * per)) end=$(((page + 1) * per))
    [[ "$end" -gt "$total" ]] && end=$total
    local sel tot kind
    read -r sel tot <<< "$(select_count "$list" "$sub")"
    kind=$(_select_sub_kind "$sub")
    printf '\n    %b◆ %s · %s%b  %b%d of %d selected%b\n' "$c_key" "${_SEL_LIST_TITLE[$list]}" "${_SEL_SUB_TITLE[$sub]}" "$c_reset" "$c_dim" "$sel" "$tot" "$c_reset"
    _tui_separator 2>/dev/null || true
    # the name column is as wide as the longest name on the page, capped
    local k w=0 name
    for (( k=start; k<end; k++ )); do
        name="${_SEL_LABEL[${_SEL_VIEW_IDX[$k]}]}"
        (( ${#name} > w )) && w=${#name}
    done
    (( w > 34 )) && w=34
    for (( k=start; k<end; k++ )); do
        i="${_SEL_VIEW_IDX[$k]}"
        printf '    %b%3d)%b %s %s %-*s  %b%s%b\n' "$c_key" "$((k + 1))" "$c_reset" "$(_select_box "${_SEL_ON[$i]}" 1)" \
            "$(_select_badge "$kind")" "$w" "$(_select_fit "${_SEL_LABEL[$i]}" "$w")" "$c_dim" "${_SEL_INFO[$i]:-}" "$c_reset"
    done
    _tui_separator 2>/dev/null || true
    printf '    %bpage %d of %d%b   %s   %s   %s   %s   %s   %s\n' \
        "$c_dim" "$((page + 1))" "$pages" "$c_reset" "$(_select_key '<' prev)" "$(_select_key '>' next)" \
        "$(_select_key number toggles)" "$(_select_key a all)" "$(_select_key n none)" "$(_select_key b back)"
}

# --- Input ---

# Read one line from the terminal, falling back to stdin; 1 on EOF
_select_read() {
    local prompt="$1" line=""
    local p
    p="$(printf '    %b▶%b %s: ' "${_TUI_PROMPT:-}" "${_TUI_RESET:-}" "$prompt")"
    if read -rp "$p" line 2>/dev/null </dev/tty; then
        printf '%s' "$line"
        return 0
    fi
    if read -rp "$p" line; then
        printf '%s' "$line"
        return 0
    fi
    return 1
}

_select_clear() {
    [[ -t 1 ]] && printf '\033[2J\033[H'
    return 0
}

# The per-package view loop for one subcategory
_select_sub_loop() {
    local list="$1" sub="$2" page=0 per=20 input total pages n
    while true; do
        _select_clear
        _select_render_sub "$list" "$sub" "$page" "$per"
        total=${#_SEL_VIEW_IDX[@]}
        pages=$(( (total + per - 1) / per )); [[ "$pages" -lt 1 ]] && pages=1
        input=$(_select_read "Pick") || return 0
        input="${input,,}"
        input="${input//[[:space:]]/}"
        case "$input" in
            ""|b|back) return 0 ;;
            a|all)  select_set "$list" "$sub" 1 ;;
            n|none) select_set "$list" "$sub" 0 ;;
            "<"|p)  [[ "$page" -gt 0 ]] && page=$((page - 1)) ;;
            ">"|N)  [[ "$page" -lt $((pages - 1)) ]] && page=$((page + 1)) ;;
            *)
                if [[ "$input" =~ ^[0-9]+$ ]]; then
                    n=$((10#$input))
                    if [[ "$n" -ge 1 && "$n" -le "$total" ]]; then
                        select_toggle_item "${_SEL_VIEW_IDX[$((n - 1))]}"
                    fi
                fi
                ;;
        esac
    done
}

# --- The interactive menu ---
# Returns 0 to proceed with the selection, 1 to cancel.
select_run() {
    local input n key target
    while true; do
        _select_clear
        select_render
        input=$(_select_read "Choose") || return 1
        input="${input,,}"
        input="${input//[[:space:]]/}"
        case "$input" in
            "")            return 0 ;;
            q|quit|cancel) return 1 ;;
            a|all)         select_set_all 1 ;;
            n|none)        select_set_all 0 ;;
            v[0-9]*)
                key="${input#v}"
                target="${_SEL_MAP_SUB[$key]:-}"
                if [[ -n "$target" ]]; then
                    read -r list sub <<< "$target"
                    if select_is_atomic "$list"; then
                        select_toggle "$list"
                    else
                        _select_sub_loop "$list" "$sub"
                    fi
                fi
                ;;
            [0-9]|[0-9][0-9])
                n=$((10#$input))
                if [[ "$n" -ge 1 && "$n" -le "${#_SEL_MAP_LIST[@]}" ]]; then
                    select_toggle "${_SEL_MAP_LIST[$((n - 1))]}"
                fi
                ;;
            [0-9][a-j]|[0-9][0-9][a-j])
                target="${_SEL_MAP_SUB[$input]:-}"
                if [[ -n "$target" ]]; then
                    read -r list sub <<< "$target"
                    if select_is_atomic "$list"; then
                        select_toggle "$list"
                    else
                        select_toggle "$list" "$sub"
                    fi
                fi
                ;;
            *) ;;
        esac
    done
}
