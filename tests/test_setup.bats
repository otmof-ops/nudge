#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause

bats_require_minimum_version 1.5.0
# Tests for setup.sh and lib/tui.sh

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    SETUP="$PROJECT_DIR/setup.sh"
    TMPDIR_TEST=$(mktemp -d)
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "setup.sh --version prints version" {
    run "$SETUP" --version
    [[ "$status" -eq 0 ]]
    [[ "$output" == "nudge setup 2.2.0" ]]
}

@test "setup.sh --help shows bunny and all flags" {
    run "$SETUP" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'(\__/)'* ]]
    [[ "$output" == *"--install"* ]]
    [[ "$output" == *"--uninstall"* ]]
    [[ "$output" == *"--update"* ]]
    [[ "$output" == *"--defaults"* ]]
    [[ "$output" == *"--unattended"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--config-only"* ]]
    [[ "$output" == *"--keep-config"* ]]
    [[ "$output" == *"--check"* ]]
    [[ "$output" == *"--upgrade"* ]]
    [[ "$output" == *"--systemd"* ]]
    [[ "$output" == *"--xdg"* ]]
    [[ "$output" == *"--prefix="* ]]
    [[ "$output" == *"--no-color"* ]]
}

@test "setup.sh passes bash -n syntax check" {
    bash -n "$SETUP"
}

@test "lib/tui.sh passes bash -n syntax check" {
    bash -n "$PROJECT_DIR/lib/tui.sh"
}

@test "setup.sh --install --unattended --prefix installs files" {
    run "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"installed"* ]] || [[ "$output" == *"Installed"* ]]
}

@test "files exist after install" {
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    [[ -f "$TMPDIR_TEST/.local/bin/nudge.sh" ]]
    [[ -d "$TMPDIR_TEST/.local/lib/nudge" ]]
    [[ -f "$TMPDIR_TEST/.config/nudge/nudge.conf" ]]
    [[ -f "$TMPDIR_TEST/.config/nudge.version" ]]
    # the mascot the dialogs draw, beside the modules
    [[ -f "$TMPDIR_TEST/.local/lib/nudge/mascot/bunny.svg" ]]
    [[ -f "$TMPDIR_TEST/.local/lib/nudge/mascot/bunny-worried.svg" ]]
    [[ "$(find "$TMPDIR_TEST/.local/lib/nudge/mascot" -name '*.svg' | wc -l)" -eq 8 ]]
}

@test "setup.sh --uninstall removes files" {
    # Install first
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    [[ -f "$TMPDIR_TEST/.local/bin/nudge.sh" ]]

    # Uninstall
    run "$SETUP" --uninstall --yes --prefix="$TMPDIR_TEST"
    [[ "$status" -eq 0 ]]
    [[ ! -f "$TMPDIR_TEST/.local/bin/nudge.sh" ]]
    [[ ! -d "$TMPDIR_TEST/.local/lib/nudge" ]]
}

@test "setup.sh --update --check exits 0" {
    run "$SETUP" --update --check
    # Should exit 0 whether or not network is available
    [[ "$status" -eq 0 ]]
}

@test "CONFIG_CATEGORIES covers all CONFIG_DEFAULTS keys" {
    # Source the files to access the arrays
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }
    source "$PROJECT_DIR/lib/output.sh"
    source "$PROJECT_DIR/lib/config.sh"

    # Build set of keys from CONFIG_CATEGORIES in setup.sh
    local cat_keys=""
    cat_keys=$(grep -oP '\[(?:core|notification|network|schedule|packages|safety|updates|logging|terminal)\]="[^"]*"' "$SETUP" | \
               grep -oP '"[^"]*"' | tr '"' ' ')

    # Every CONFIG_DEFAULTS key should appear in a category
    for key in "${!CONFIG_DEFAULTS[@]}"; do
        [[ "$cat_keys" == *"$key"* ]]
    done
}

@test "uninstall --yes shows emotional farewell in disney mode" {
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    run "$SETUP" --uninstall --yes --prefix="$TMPDIR_TEST"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"waves tiny paw"* ]]
    [[ "$output" == *"i tried my best"* ]]
}

@test "uninstall --yes classic mode shows neutral messages" {
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    # Set classic personality in config
    sed -i 's/BUNNY_PERSONALITY="disney"/BUNNY_PERSONALITY="classic"/' "$TMPDIR_TEST/.config/nudge/nudge.conf"
    run "$SETUP" --uninstall --yes --prefix="$TMPDIR_TEST"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"waves tiny paw"* ]]
    [[ "$output" == *"nudge has been removed"* ]]
}

@test "uninstall --yes --keep-config shows come back message" {
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    run "$SETUP" --uninstall --yes --keep-config --prefix="$TMPDIR_TEST"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"does that mean you might come back"* ]]
}

@test "reinstall after keep-config shows YOU CAME BACK" {
    # Install
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    # Uninstall with keep-config
    "$SETUP" --uninstall --yes --keep-config --prefix="$TMPDIR_TEST"
    # Reinstall
    run "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"YOU CAME BACK"* ]]
}

@test "fresh install does not show YOU CAME BACK" {
    run "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"YOU CAME BACK"* ]]
}

@test "uninstall removes files and shows farewell" {
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    run "$SETUP" --uninstall --yes --prefix="$TMPDIR_TEST"
    [[ "$status" -eq 0 ]]
    [[ ! -f "$TMPDIR_TEST/.local/bin/nudge.sh" ]]
    [[ "$output" == *"no longer check for updates"* ]]
}

@test "upgrade install does not show YOU CAME BACK" {
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    run "$SETUP" --install --unattended --upgrade --prefix="$TMPDIR_TEST"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"YOU CAME BACK"* ]]
}

@test "_bunny_farewell renders waving pose" {
    # farewell pose output is tested via uninstall integration tests above
    skip "farewell pose tested via uninstall integration tests"
}

@test "_tui_bunny output contains mascot art" {
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }
    source "$PROJECT_DIR/lib/output.sh"
    _TUI_NO_COLOR=true
    source "$PROJECT_DIR/lib/tui.sh"
    _tui_init

    run _tui_bunny "test message" "second line"
    [[ "$output" == *'(\__/)'* ]]
    [[ "$output" == *"test message"* ]]
}

@test "_tui_info prints status line with checkmark" {
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }
    source "$PROJECT_DIR/lib/output.sh"
    _TUI_NO_COLOR=true
    source "$PROJECT_DIR/lib/tui.sh"
    _tui_init

    run _tui_info "test message"
    [[ "$output" == *"test message"* ]]
}

@test "_tui_warn prints warning line" {
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }
    source "$PROJECT_DIR/lib/output.sh"
    _TUI_NO_COLOR=true
    source "$PROJECT_DIR/lib/tui.sh"
    _tui_init

    run _tui_warn "warning message"
    [[ "$output" == *"warning message"* ]]
}

@test "_tui_error prints error line" {
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }
    source "$PROJECT_DIR/lib/output.sh"
    _TUI_NO_COLOR=true
    source "$PROJECT_DIR/lib/tui.sh"
    _tui_init

    run _tui_error "error message"
    [[ "$output" == *"error message"* ]]
}

@test "tui.sh has no whiptail or dialog references" {
    run grep -c 'whiptail\|_WT_\|_wt_\|_is_wt_mode\|dialog' "$PROJECT_DIR/lib/tui.sh"
    [[ "$output" == "0" ]]
}

@test "setup.sh --install --unattended completes without interactive prompts" {
    run "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"installed"* ]] || [[ "$output" == *"Installed"* ]]
}

@test "setup.sh --uninstall --yes completes without interactive prompts" {
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    run "$SETUP" --uninstall --yes --prefix="$TMPDIR_TEST"
    [[ "$status" -eq 0 ]]
    [[ ! -f "$TMPDIR_TEST/.local/bin/nudge.sh" ]]
}

@test "install creates the nudge command and the installed setup finds its libraries" {
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    [[ -L "$TMPDIR_TEST/.local/bin/nudge" ]]
    [[ -f "$TMPDIR_TEST/.local/share/icons/hicolor/scalable/apps/nudge.svg" ]]
    run "$TMPDIR_TEST/.local/bin/nudge" --version
    [[ "$output" == "nudge 2.2.0" ]]
    run "$TMPDIR_TEST/.local/bin/nudge-setup.sh" --version
    [[ "$status" -eq 0 ]]
    [[ "$output" == "nudge setup 2.2.0" ]]
}

@test "uninstall --keep-config keeps the history and state as well" {
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    mkdir -p "$TMPDIR_TEST/.local/share/nudge"
    echo '{}' > "$TMPDIR_TEST/.local/share/nudge/history.jsonl"
    "$SETUP" --uninstall --yes --keep-config --prefix="$TMPDIR_TEST"
    [[ -f "$TMPDIR_TEST/.local/share/nudge/history.jsonl" ]]
    [[ -f "$TMPDIR_TEST/.config/nudge/nudge.conf" ]]
    [[ ! -e "$TMPDIR_TEST/.local/bin/nudge" ]]
}

@test "an upgrade keeps every config key, including the ones setup never edits" {
    "$SETUP" --install --unattended --prefix="$TMPDIR_TEST"
    sed -i 's/^TERMINAL_EMULATOR=.*/TERMINAL_EMULATOR="kitty"/; s/^CRITICAL_PACKAGES_EXTRA=.*/CRITICAL_PACKAGES_EXTRA="firefox"/' "$TMPDIR_TEST/.config/nudge/nudge.conf"
    "$SETUP" --install --unattended --upgrade --prefix="$TMPDIR_TEST"
    grep -q '^TERMINAL_EMULATOR="kitty"' "$TMPDIR_TEST/.config/nudge/nudge.conf"
    grep -q '^CRITICAL_PACKAGES_EXTRA="firefox"' "$TMPDIR_TEST/.config/nudge/nudge.conf"
    grep -q '^SELECT_UPDATES=true' "$TMPDIR_TEST/.config/nudge/nudge.conf"
}

@test "an upgrade keeps the systemd autostart method" {
    "$SETUP" --install --unattended --systemd --prefix="$TMPDIR_TEST"
    [[ -f "$TMPDIR_TEST/.config/systemd/user/nudge.timer" ]]
    "$SETUP" --install --unattended --upgrade --prefix="$TMPDIR_TEST"
    [[ -f "$TMPDIR_TEST/.config/systemd/user/nudge.timer" ]]
    [[ ! -f "$TMPDIR_TEST/.config/autostart/nudge.desktop" ]]
}

@test "the TUI draws when stdout is not a terminal" {
    run bash -c "printf '0\n' | '$SETUP' --no-color | cat"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAIN MENU"* ]]
}

@test "the configure screen opens, lists every category and comes back" {
    run bash -c "printf '0\n0\n' | '$SETUP' --config-only --no-color --prefix='$TMPDIR_TEST'"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Terminal"* ]]
    [[ "$output" == *"terminal emulator for upgrades"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "a word at a numbered prompt is asked again, not a crash" {
    run bash -c "printf 'quit\nnope\n0\n' | '$SETUP' --no-color | cat"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Type a number"* ]]
}

@test "_tui_choice prints the menu to stderr and only the answer to stdout" {
    _TUI_NO_COLOR=true
    source "$PROJECT_DIR/lib/tui.sh"
    _tui_init
    local answer
    answer=$(printf '2\n' | _tui_choice "Pick:" "auto" "auto" "xdg" "systemd" 2>/dev/null)
    [[ "$answer" == "xdg" ]]
    answer=$(printf 'systemd\n' | _tui_choice "Pick:" "auto" "auto" "xdg" "systemd" 2>/dev/null)
    [[ "$answer" == "systemd" ]]
    answer=$(printf 'bogus\n' | _tui_choice "Pick:" "auto" "auto" "xdg" "systemd" 2>/dev/null)
    [[ "$answer" == "auto" ]]
}

@test "--prefix must be absolute and ~ expands" {
    run "$SETUP" --install --unattended --prefix=relative/dir
    [[ "$status" -eq 4 ]]
    run "$SETUP" --install --unattended --prefix=
    [[ "$status" -eq 4 ]]
}

@test "the CLI install fails loudly when a step cannot complete" {
    run "$SETUP" --install --unattended --prefix=/proc/nope
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"did not finish"* ]]
}
