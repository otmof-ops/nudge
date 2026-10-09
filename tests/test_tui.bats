#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause

bats_require_minimum_version 1.5.0
# Tests for lib/tui.sh — the palette and the primitives

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    source "$PROJECT_DIR/lib/tui.sh"
}

@test "colour is off outside a terminal and under NO_COLOR" {
    _tui_init
    [[ -z "$_TUI_ACCENT" && -z "$_TUI_BOLD" && -z "$_TUI_RESET" ]]
    [[ "$_TUI_DEPTH" -eq 0 ]]
    [[ "$(COLORTERM=truecolor NO_COLOR=1 _tui_color_depth true)" == "0" ]]
}

@test "the depth follows COLORTERM and tput when colour is on" {
    # pretend stdout is a terminal by answering the test itself
    _tui_color_depth() { echo 24; }
    _tui_init
    [[ "$_TUI_ACCENT" == '\033[38;2;46;164;79m' ]]
    [[ "$_TUI_CYAN" == "$_TUI_ACCENT" ]]
    [[ "$_TUI_SUCCESS" == "$_TUI_ACCENT" ]]
    _tui_color_depth() { echo 256; }
    _tui_init
    [[ "$_TUI_CRIT" == '\033[38;5;167m' ]]
    _tui_color_depth() { echo 16; }
    _tui_init
    [[ "$_TUI_SEC" == '\033[0;33m' ]]
    [[ "$_TUI_BOLD" == '\033[1m' ]]
}

@test "_tui_color_depth answers for a terminal it is told about" {
    [[ "$(COLORTERM=truecolor _tui_color_depth true)" == "24" ]]
    [[ "$(COLORTERM=24bit _tui_color_depth true)" == "24" ]]
    [[ "$(COLORTERM='' _tui_color_depth false)" == "0" ]]
    [[ "$(COLORTERM=truecolor NO_COLOR=1 _tui_color_depth true)" == "0" ]]
    # without COLORTERM, tput decides: 256 or 16 on any real TERM
    local d
    d=$(COLORTERM='' TERM=xterm-256color _tui_color_depth true)
    [[ "$d" == "256" || "$d" == "16" ]]
    [[ "$(COLORTERM='' _tui_color_depth)" == "0" ]]   # a pipe is not a terminal
}

@test "_tui_tick draws all, some and none" {
    _TUI_NO_COLOR=true _tui_init
    [[ "$(_tui_tick 3 3)" == "[✓]" ]]
    [[ "$(_tui_tick 1 3)" == "[-]" ]]
    [[ "$(_tui_tick 0 3)" == "[ ]" ]]
    [[ "$(_tui_tick 0 0)" == "[ ]" ]]
}

@test "_tui_badge marks every kind" {
    _TUI_NO_COLOR=true _tui_init
    [[ "$(_tui_badge critical)" == "★" ]]
    [[ "$(_tui_badge security "x")" == "⚠ x" ]]
    [[ "$(_tui_badge flatpak)" == "◆" ]]
    [[ "$(_tui_badge snap)" == "●" ]]
    [[ "$(_tui_badge ok "done")" == "✓ done" ]]
    [[ "$(_tui_badge fail)" == "✗" ]]
    [[ "$(_tui_badge standard)" == " " ]]
}

@test "_tui_key and _tui_result read plainly without colour" {
    _TUI_NO_COLOR=true _tui_init
    [[ "$(_tui_key a 'select all')" == "a select all" ]]
    run _tui_result ok "System packages: done"
    [[ "$output" == "    ✓ System packages: done" ]]
    run _tui_result fail "exit 1"
    [[ "$output" == "    ✗ exit 1" ]]
}

@test "_tui_draw_header draws a rounded frame around the title" {
    _TUI_NO_COLOR=true _tui_init
    _TUI_WIDTH=40
    run _tui_draw_header "nudge" "update session"
    local rule
    rule=$(_tui_rule_str 32)
    # bats drops the empty first line
    [[ "${lines[0]}" == "    ╭${rule}╮" ]]
    [[ "${lines[1]}" == *"│"*"nudge"*"│" ]]
    [[ "${lines[2]}" == "    ╰${rule}╯" ]]
    [[ "${lines[3]}" == *"update session" ]]
}

@test "_tui_operation_header is a one-line rule with the title" {
    _TUI_NO_COLOR=true _tui_init
    _TUI_WIDTH=40
    run _tui_operation_header "Snap: all refreshes"
    [[ "$output" == "    ── Snap: all refreshes ─────────────" ]]
}

@test "_tui_bunny keeps the three-line text bunny" {
    _TUI_NO_COLOR=true _tui_init
    run _tui_bunny "hello" "world" "^.^"
    [[ "${lines[0]}" == '    (\__/)' ]]
    [[ "${lines[1]}" == "    (=^.^=)  hello" ]]
    [[ "${lines[2]}" == '    (")_(")  world' ]]
}

@test "_tui_title writes nothing outside a terminal" {
    run _tui_title "nudge"
    [[ -z "$output" ]]
}
