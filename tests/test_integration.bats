#!/usr/bin/env bats
# Integration tests for nudge.sh

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    NUDGE="$PROJECT_DIR/nudge.sh"
}

teardown() {
    [[ -n "${_INTEGRATION_TMPDIR:-}" ]] && rm -rf "$_INTEGRATION_TMPDIR" || true
}

@test "nudge --version prints 2.0.0" {
    run "$NUDGE" --version
    [[ "$status" -eq 0 ]]
    [[ "$output" == "nudge 2.0.0" ]]
}

@test "nudge --help prints usage with bunny mascot" {
    run "$NUDGE" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'(\('* ]]
    [[ "$output" == *"nudge 2.0.0"* ]]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--json"* ]]
    [[ "$output" == *"--history"* ]]
    [[ "$output" == *"--defer"* ]]
}

@test "nudge --help includes all new flags" {
    run "$NUDGE" --help
    [[ "$output" == *"--self-update"* ]]
    [[ "$output" == *"--config"* ]]
    [[ "$output" == *"--validate"* ]]
    [[ "$output" == *"--migrate"* ]]
    [[ "$output" == *"--verbose"* ]]
}

@test "nudge --config prints resolved configuration" {
    run "$NUDGE" --config
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"ENABLED"* ]]
    [[ "$output" == *"DELAY"* ]]
    [[ "$output" == *"SCHEDULE_MODE"* ]]
}

@test "nudge --validate passes with defaults" {
    run "$NUDGE" --validate
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"passed"* ]]
}

@test "nudge --history with no history shows message" {
    # Use temp data dir with no history
    _INTEGRATION_TMPDIR=$(mktemp -d)
    export XDG_DATA_HOME="$_INTEGRATION_TMPDIR"
    run "$NUDGE" --history
    [[ "$status" -eq 0 ]]
}

@test "nudge --defer 1h creates deferral" {
    _INTEGRATION_TMPDIR=$(mktemp -d)
    export XDG_DATA_HOME="$_INTEGRATION_TMPDIR"
    run "$NUDGE" --defer 1h
    [[ "$status" -eq 9 ]]  # EXIT_DEFERRED
    [[ "$output" == *"deferred"* ]]
}

@test "install.sh --version prints version via setup.sh" {
    run "$PROJECT_DIR/install.sh" --version
    [[ "$status" -eq 0 ]]
    [[ "$output" == "nudge setup 2.0.0" ]]
}

@test "install.sh --help shows setup.sh flags" {
    run "$PROJECT_DIR/install.sh" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--upgrade"* ]]
    [[ "$output" == *"--config-only"* ]]
    [[ "$output" == *"--systemd"* ]]
    [[ "$output" == *"--xdg"* ]]
    [[ "$output" == *"--install"* ]]
    [[ "$output" == *"--uninstall"* ]]
}

@test "uninstall.sh --help shows help" {
    run "$PROJECT_DIR/uninstall.sh" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--yes"* ]]
    [[ "$output" == *"--keep-config"* ]]
}

@test "lib modules are all present" {
    [[ -f "$PROJECT_DIR/lib/output.sh" ]]
    [[ -f "$PROJECT_DIR/lib/config.sh" ]]
    [[ -f "$PROJECT_DIR/lib/lock.sh" ]]
    [[ -f "$PROJECT_DIR/lib/network.sh" ]]
    [[ -f "$PROJECT_DIR/lib/pkgmgr.sh" ]]
    [[ -f "$PROJECT_DIR/lib/notify.sh" ]]
    [[ -f "$PROJECT_DIR/lib/schedule.sh" ]]
    [[ -f "$PROJECT_DIR/lib/history.sh" ]]
    [[ -f "$PROJECT_DIR/lib/safety.sh" ]]
    [[ -f "$PROJECT_DIR/lib/selfupdate.sh" ]]
    [[ -f "$PROJECT_DIR/lib/bunny.sh" ]]
}

@test "all shell scripts pass bash -n syntax check" {
    bash -n "$PROJECT_DIR/nudge.sh"
    bash -n "$PROJECT_DIR/install.sh"
    bash -n "$PROJECT_DIR/uninstall.sh"
    for f in "$PROJECT_DIR"/lib/*.sh; do
        bash -n "$f"
    done
}

@test "man page exists" {
    [[ -f "$PROJECT_DIR/share/man/nudge.1" ]]
}

@test "bash completion exists" {
    [[ -f "$PROJECT_DIR/share/bash-completion/nudge" ]]
}

@test "systemd units exist" {
    [[ -f "$PROJECT_DIR/share/systemd/nudge.timer" ]]
    [[ -f "$PROJECT_DIR/share/systemd/nudge.service" ]]
}

@test "Makefile exists" {
    [[ -f "$PROJECT_DIR/Makefile" ]]
}

@test "setup.sh exists and is executable" {
    [[ -f "$PROJECT_DIR/setup.sh" ]]
    [[ -x "$PROJECT_DIR/setup.sh" ]]
}

@test "install.sh --help still works via delegation" {
    run "$PROJECT_DIR/install.sh" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--install"* ]]
}
