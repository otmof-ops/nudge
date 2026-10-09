#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause

bats_require_minimum_version 1.5.0
# Integration tests for nudge.sh

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    NUDGE="$PROJECT_DIR/nudge.sh"
}

teardown() {
    [[ -n "${_INTEGRATION_TMPDIR:-}" ]] && rm -rf "$_INTEGRATION_TMPDIR" || true
}

@test "nudge --version prints 2.1.0" {
    run "$NUDGE" --version
    [[ "$status" -eq 0 ]]
    [[ "$output" == "nudge 2.1.0" ]]
}

@test "nudge --help prints usage with bunny mascot" {
    run "$NUDGE" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'(\__/)'* ]]
    [[ "$output" == *"nudge 2.1.0"* ]]
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
    [[ "$output" == "nudge setup 2.1.0" ]]
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
    [[ -f "$PROJECT_DIR/lib/bunny-poses.sh" ]]
    [[ -f "$PROJECT_DIR/lib/bunny-dialogue.sh" ]]
    [[ -f "$PROJECT_DIR/lib/errorreport.sh" ]]
    [[ -f "$PROJECT_DIR/lib/tui.sh" ]]
    [[ -f "$PROJECT_DIR/lib/select.sh" ]]
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

# --- End-to-end through mocked tools ---

_integration_mocks() {
    _INTEGRATION_TMPDIR=$(mktemp -d)
    export HOME="$_INTEGRATION_TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_RUNTIME_DIR="$_INTEGRATION_TMPDIR/run"
    export NUDGE_APT_CHECK="$_INTEGRATION_TMPDIR/no-apt-check"
    mkdir -p "$XDG_CONFIG_HOME/nudge" "$XDG_RUNTIME_DIR" "$_INTEGRATION_TMPDIR/bin"
    printf 'PKGMGR_OVERRIDE="apt"\nFLATPAK_ENABLED=false\nSNAP_ENABLED=false\nSELF_UPDATE_CHECK=false\nDELAY=0\n' > "$XDG_CONFIG_HOME/nudge/nudge.conf"
    printf '#!/bin/bash\nexit 0\n' > "$_INTEGRATION_TMPDIR/bin/curl"
    printf '#!/bin/bash\nexit 1\n' > "$_INTEGRATION_TMPDIR/bin/fuser"
    cat > "$_INTEGRATION_TMPDIR/bin/apt" <<'EOT'
#!/bin/bash
cat <<"ROWS"
Listing...
openssl/noble-security 3.0.13-0ubuntu3.16 amd64 [upgradable from: 3.0.13-0ubuntu3.15]
vim/noble-updates 2:9.1.0016-1ubuntu7.9 amd64 [upgradable from: 2:9.1.0016-1ubuntu7.8]
ROWS
EOT
    chmod +x "$_INTEGRATION_TMPDIR/bin/"*
    export PATH="$_INTEGRATION_TMPDIR/bin:$PATH"
}

@test "check-only --json is valid JSON with no stray terminal bytes" {
    _integration_mocks
    run "$NUDGE" --check-only --json
    [[ "$status" -eq 0 ]]
    [[ "$output" != *$'\033'* ]]
    [[ "$output" == *'"total": 2'* ]]
    [[ "$output" == *'"security": 1'* ]]
    [[ "$output" == *'"critical": 1'* ]]
    [[ "$output" == *'"name":"openssl"'* ]]
    if command -v jq &>/dev/null; then
        echo "$output" | jq -e '.exit_reason == "OK" and (.packages | length) == 2' >/dev/null
    fi
}

@test "dry-run shows the preview with critical packages first" {
    _integration_mocks
    run "$NUDGE" --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Preview:"* ]]
    local first
    first=$(echo "$output" | sed -n '/^Preview:/{n;p;}')
    [[ "$first" == *"openssl"*"CRITICAL"* ]]
}

@test "a timer run with no display skips quietly instead of failing" {
    _integration_mocks
    _NUDGE_TRIGGER=timer run env -u DISPLAY -u WAYLAND_DISPLAY _NUDGE_TRIGGER=timer "$NUDGE"
    [[ "$status" -eq 0 ]]
    grep -q '"outcome":"SKIPPED_NO_DISPLAY"' "$XDG_DATA_HOME/nudge/history.jsonl"
    [[ ! -d "$XDG_DATA_HOME/nudge/crash-reports" ]] || [[ -z "$(ls -A "$XDG_DATA_HOME/nudge/crash-reports")" ]]
}

@test "the upgrade runner cancels at the menu and reports through the status file" {
    _integration_mocks
    local sess="$XDG_DATA_HOME/nudge/upgrade-session.test"
    mkdir -p "$XDG_DATA_HOME/nudge"
    printf 'pkgmgr=apt\narch=amd64\n[system]\nvim|1|2|STANDARD|amd64|0\n[flatpak]\n[snap]\n' > "$sess"
    chmod 600 "$sess"
    : > "$sess.status"
    run bash -c "printf 'q\n' | '$NUDGE' --_run-upgrade '$sess'"
    [[ "$status" -eq 0 ]]
    grep -q '^cancelled=1$' "$sess.status"
    grep -q '^done=1$' "$sess.status"
    grep -q '^total_system=1$' "$sess.status"
}

@test "the upgrade runner refuses a session file it cannot trust" {
    _integration_mocks
    run "$NUDGE" --_run-upgrade "$_INTEGRATION_TMPDIR/does-not-exist"
    [[ "$status" -ne 0 ]]
}

@test "nudge.sh finds its libraries from an installed prefix" {
    _integration_mocks
    local prefix="$_INTEGRATION_TMPDIR/prefix"
    mkdir -p "$prefix/.local/bin" "$prefix/.local/lib/nudge"
    cp "$NUDGE" "$prefix/.local/bin/nudge.sh"
    cp "$PROJECT_DIR"/lib/*.sh "$prefix/.local/lib/nudge/"
    run env -u NUDGE_LIB_DIR HOME="$_INTEGRATION_TMPDIR/elsewhere" "$prefix/.local/bin/nudge.sh" --version
    [[ "$status" -eq 0 ]]
    [[ "$output" == "nudge 2.1.0" ]]
}

@test "flags that need a value or a parent flag are usage errors, not silent runs" {
    _integration_mocks
    run "$NUDGE" --defer
    [[ "$status" -eq 10 ]]
    run "$NUDGE" --history --since
    [[ "$status" -eq 10 ]]
    run "$NUDGE" --since 2026-01-01
    [[ "$status" -eq 10 ]]
    run "$NUDGE" --clear
    [[ "$status" -eq 10 ]]
}

@test "check-only leaves no state behind" {
    _integration_mocks
    run "$NUDGE" --check-only
    [[ "$status" -eq 0 ]]
    [[ ! -f "$XDG_DATA_HOME/nudge/last_check" ]]
    [[ ! -f "$XDG_DATA_HOME/nudge/history.jsonl" ]]
}

@test "check-only prints a count even when there are no updates" {
    _integration_mocks
    printf '#!/bin/bash\necho "Listing..."\n' > "$_INTEGRATION_TMPDIR/bin/apt"
    run "$NUDGE" --check-only
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"0 updates available"* ]]
}

@test "an offline check-only --json still prints JSON and writes no crash report" {
    _integration_mocks
    printf '#!/bin/bash\nexit 1\n' > "$_INTEGRATION_TMPDIR/bin/curl"
    printf '#!/bin/bash\nexit 1\n' > "$_INTEGRATION_TMPDIR/bin/wget"
    printf '#!/bin/bash\nexit 1\n' > "$_INTEGRATION_TMPDIR/bin/ping"
    chmod +x "$_INTEGRATION_TMPDIR/bin/"*
    run "$NUDGE" --check-only --json
    [[ "$status" -eq 5 ]]
    [[ "$output" == *'"exit_reason": "NETWORK_FAIL"'* ]]
    [[ ! -d "$XDG_DATA_HOME/nudge/crash-reports" ]] || [[ -z "$(ls -A "$XDG_DATA_HOME/nudge/crash-reports")" ]]
}

@test "dry-run --json prints only JSON" {
    _integration_mocks
    run "$NUDGE" --dry-run --json
    [[ "$status" -eq 0 ]]
    [[ "${lines[0]}" == "{" ]]
    [[ "$output" != *"Preview:"* ]]
}
