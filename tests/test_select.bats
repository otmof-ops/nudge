#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause

bats_require_minimum_version 1.5.0
# Tests for lib/select.sh — the update selection menu

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    _TUI_NO_COLOR=true
    source "$PROJECT_DIR/lib/tui.sh"
    _tui_init
    source "$PROJECT_DIR/lib/select.sh"
    select_reset
    select_add system critical "linux-image  1 → 2" linux-image
    select_add system security "libxml2  1 → 2" libxml2
    select_add system security "libxml2:i386  1 → 2" libxml2:i386
    select_add system standard "thermald  1 → 2" thermald
    select_add flatpak app "Firefox" app/org.mozilla.firefox/x86_64/stable
    select_add flatpak runtime "Platform" runtime/org.freedesktop.Platform/x86_64/23.08
    select_add snap snap "firefox" firefox
}

@test "everything starts selected" {
    [[ "$(select_count system)" == "4 4" ]]
    [[ "$(select_count flatpak)" == "2 2" ]]
    [[ "$(select_count snap)" == "1 1" ]]
    select_all_on system
    select_all_on flatpak
}

@test "select_count narrows to a subcategory" {
    [[ "$(select_count system security)" == "2 2" ]]
    [[ "$(select_count system critical)" == "1 1" ]]
    [[ "$(select_count flatpak runtime)" == "1 1" ]]
    [[ "$(select_count snap nothing)" == "0 0" ]]
}

@test "select_set_all none then all" {
    select_set_all 0
    [[ "$(select_count system)" == "0 4" ]]
    run ! select_any_on snap
    select_set_all 1
    [[ "$(select_count snap)" == "1 1" ]]
}

@test "select_toggle flips a whole list" {
    select_toggle system
    [[ "$(select_count system)" == "0 4" ]]
    [[ "$(select_count flatpak)" == "2 2" ]]
    select_toggle system
    [[ "$(select_count system)" == "4 4" ]]
}

@test "select_toggle flips a subcategory and a partial list toggles back to all" {
    select_toggle system security
    [[ "$(select_count system security)" == "0 2" ]]
    [[ "$(select_count system)" == "2 4" ]]
    run ! select_all_on system
    select_any_on system
    select_toggle system
    [[ "$(select_count system)" == "4 4" ]]
}

@test "select_toggle_item flips one row" {
    select_toggle_item 1
    [[ "$(select_count system security)" == "1 2" ]]
    select_toggle_item 1
    [[ "$(select_count system security)" == "2 2" ]]
    run ! select_toggle_item 99
}

@test "select_targets lists only selected targets of a list" {
    select_toggle_item 2
    run select_targets system
    [[ "${lines[*]}" == "linux-image libxml2 thermald" ]]
    run select_targets flatpak
    [[ "${lines[0]}" == "app/org.mozilla.firefox/x86_64/stable" ]]
}

@test "select_has and select_any_on" {
    select_has system
    run ! select_has nothing
    select_set system "" 0
    run ! select_any_on system
    select_any_on snap
}

@test "atomic lists are marked and queried" {
    run ! select_is_atomic system
    select_mark_atomic system
    select_is_atomic system
    run ! select_is_atomic snap
}

@test "select_render shows lists, subcategories, counts and keys" {
    select_set_list_title system "System packages (apt)"
    run select_render
    [[ "$output" == *"System packages (apt)"* ]]
    [[ "$output" == *"1a)"* ]]
    [[ "$output" == *"Critical system packages"* ]]
    [[ "$output" == *"Security updates"* ]]
    [[ "$output" == *"Other updates"* ]]
    [[ "$output" == *"Applications"* ]]
    [[ "$output" == *"Runtimes"* ]]
    [[ "$output" == *"Snaps"* ]]
    [[ "$output" == *"4 of 4"* ]]
    [[ "$output" == *"[x]"* ]]
}

@test "select_render marks partial lists and empty subcategories are hidden" {
    select_toggle_item 0
    run select_render
    [[ "$output" == *"[-] System packages"* ]]
    select_reset
    select_add snap snap "firefox" firefox
    run select_render
    [[ "$output" != *"System packages"* ]]
    [[ "$output" == *"1) [x] Snap"* ]]
}

@test "select_render notes an atomic list" {
    select_mark_atomic system
    run select_render
    [[ "$output" == *"everything or nothing"* ]]
}

@test "select_run proceeds on Enter with everything selected" {
    run select_run <<< $'\n'
    [[ "$status" -eq 0 ]]
}

@test "select_run cancels on q" {
    run select_run <<< $'q\n'
    [[ "$status" -eq 1 ]]
}

@test "select_run cancels on end of input" {
    run select_run < /dev/null
    [[ "$status" -eq 1 ]]
}

@test "select_run applies list, subcategory and single-package toggles" {
    # untick list 2 (flatpak), untick 1b (security), then pick one security package back
    select_run <<< $'2\n1b\nv1b\n2\nb\n\n'
    [[ "$(select_count flatpak)" == "0 2" ]]
    [[ "$(select_count system security)" == "1 2" ]]
    run select_targets system
    [[ "${lines[*]}" == "linux-image libxml2:i386 thermald" ]]
}

@test "select_run n then a select none then all" {
    select_run <<< $'n\n\n'
    [[ "$(select_count system)" == "0 4" ]]
    select_run <<< $'a\n\n'
    [[ "$(select_count system)" == "4 4" ]]
}

@test "select_run on an atomic list toggles the whole list from a subcategory key" {
    select_mark_atomic system
    select_run <<< $'1b\n\n'
    [[ "$(select_count system)" == "0 4" ]]
    select_run <<< $'v1a\n\n'
    [[ "$(select_count system)" == "4 4" ]]
}

@test "select_run ignores unknown input and keeps going" {
    run select_run <<< $'zzz\n9\n\n'
    [[ "$status" -eq 0 ]]
}

@test "subcategory view pages through long lists" {
    select_reset
    local i
    for i in $(seq 1 45); do select_add system standard "pkg-$i" "pkg-$i"; done
    run _select_render_sub system standard 0 20
    [[ "$output" == *"page 1 of 3"* ]]
    [[ "$output" == *"pkg-20"* ]]
    [[ "$output" != *"pkg-21"* ]]
    run _select_render_sub system standard 2 20
    [[ "$output" == *"page 3 of 3"* ]]
    [[ "$output" == *"pkg-45"* ]]
}
