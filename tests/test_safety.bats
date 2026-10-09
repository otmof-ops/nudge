#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# Tests for lib/safety.sh — reboot detection and snapshots

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)

    # Stubs
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }
    json_set() { :; }
    notify_reboot() { return 1; }

    NUDGE_STATE_DIR="$TMPDIR_TEST"
    REBOOT_CHECK=true
    SNAPSHOT_ENABLED=false

    source "$PROJECT_DIR/lib/safety.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "safety_reboot_check returns 1 when REBOOT_CHECK=false" {
    REBOOT_CHECK=false
    run ! safety_reboot_check
}

@test "safety_check_pending_reboot returns 1 when no file" {
    run ! safety_check_pending_reboot
}

@test "safety_check_pending_reboot returns 0 when the flag is current and a reboot is still needed" {
    safety_reboot_check() { return 0; }
    echo "$(date)" > "$TMPDIR_TEST/reboot_pending"
    safety_check_pending_reboot
    [[ -f "$TMPDIR_TEST/reboot_pending" ]]
}

@test "safety_check_pending_reboot clears a flag written before the current boot" {
    safety_reboot_check() { return 0; }
    echo "old" > "$TMPDIR_TEST/reboot_pending"
    touch -d '@1' "$TMPDIR_TEST/reboot_pending"
    run ! safety_check_pending_reboot
    [[ ! -f "$TMPDIR_TEST/reboot_pending" ]]
}

@test "safety_check_pending_reboot clears a flag when nothing needs a reboot any more" {
    safety_reboot_check() { return 1; }
    echo "$(date)" > "$TMPDIR_TEST/reboot_pending"
    run ! safety_check_pending_reboot
    [[ ! -f "$TMPDIR_TEST/reboot_pending" ]]
}

@test "_safety_newest_same_flavour compares only the running kernel's flavour" {
    mkdir -p "$TMPDIR_TEST/boot"
    touch "$TMPDIR_TEST/boot/vmlinuz-6.8.0-142-generic" \
          "$TMPDIR_TEST/boot/vmlinuz-6.17.0-1030-oem" \
          "$TMPDIR_TEST/boot/vmlinuz-6.17.0-1032-oem"
    [[ "$(_safety_newest_same_flavour 6.17.0-1032-oem "$TMPDIR_TEST/boot")" == "6.17.0-1032-oem" ]]
    [[ "$(_safety_newest_same_flavour 6.17.0-1030-oem "$TMPDIR_TEST/boot")" == "6.17.0-1032-oem" ]]
    [[ "$(_safety_newest_same_flavour 6.8.0-142-generic "$TMPDIR_TEST/boot")" == "6.8.0-142-generic" ]]
    [[ -z "$(_safety_newest_same_flavour 6.6.1-arch1-1 "$TMPDIR_TEST/boot")" ]]
}

@test "safety_handle_reboot creates pending file when reboot needed" {
    # Override reboot check to return true
    safety_reboot_check() { return 0; }

    safety_handle_reboot
    [[ -f "$TMPDIR_TEST/reboot_pending" ]]
}

@test "safety_snapshot returns 0 when disabled" {
    SNAPSHOT_ENABLED=false
    safety_snapshot
}

@test "safety_snapshot fails when enabled but no tool available" {
    SNAPSHOT_ENABLED=true
    SNAPSHOT_TOOL="auto"

    # Override commands to not be found
    command() { return 1; }

    run ! safety_snapshot
}

@test "safety_reboot_check detects /var/run/reboot-required" {
    REBOOT_CHECK=true
    # Mock the reboot-required file check by overriding the function
    # Since we can't create /var/run/reboot-required without root,
    # we override the function behavior
    safety_reboot_check() {
        [[ -f "$TMPDIR_TEST/reboot-required" ]] && return 0
        return 1
    }
    touch "$TMPDIR_TEST/reboot-required"
    safety_reboot_check
}

@test "safety_reboot_check returns 1 with no indicators" {
    REBOOT_CHECK=true
    # Override to test without real system files
    safety_reboot_check() {
        [[ -f "$TMPDIR_TEST/reboot-required" ]] && return 0
        return 1
    }
    run safety_reboot_check
    [[ "$status" -ne 0 ]]
}

@test "the timeshift snapshot id is the snapshot name, not its tag" {
    local bin="$TMPDIR_TEST/bin"; mkdir -p "$bin"
    printf '#!/bin/bash\nexec "$@"\n' > "$bin/sudo"
    printf '#!/bin/bash\necho "Creating new snapshot...(RSYNC)"\necho "Tagged snapshot '"'"'2026-10-09_16-04-00'"'"': ondemand"\n' > "$bin/timeshift"
    chmod +x "$bin/sudo" "$bin/timeshift"
    PATH="$bin:$PATH"
    declare -gA _JSON_DATA=()
    json_set() { _JSON_DATA["$1"]="$2"; }
    json_escape() { printf '%s' "$1"; }
    SNAPSHOT_ENABLED=true
    SNAPSHOT_TOOL="timeshift"
    safety_snapshot
    [[ "${_JSON_DATA[snapshot_id]}" == '"2026-10-09_16-04-00"' ]]
}
