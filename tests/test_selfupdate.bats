#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# Tests for lib/selfupdate.sh — version comparison and self-update

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)

    # Stubs
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }

    NUDGE_STATE_DIR="$TMPDIR_TEST"
    NUDGE_VERSION="2.0.0"
    SELF_UPDATE_CHECK=true

    source "$PROJECT_DIR/lib/selfupdate.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "version_gt: 2.1.0 > 2.0.0" {
    version_gt "2.1.0" "2.0.0"
}

@test "version_gt: 2.0.1 > 2.0.0" {
    version_gt "2.0.1" "2.0.0"
}

@test "version_gt: 3.0.0 > 2.9.9" {
    version_gt "3.0.0" "2.9.9"
}

@test "version_gt: 2.0.0 not > 2.0.0 (equal)" {
    run ! version_gt "2.0.0" "2.0.0"
}

@test "version_gt: 1.9.9 not > 2.0.0" {
    run ! version_gt "1.9.9" "2.0.0"
}

@test "version_gt handles v prefix" {
    version_gt "v2.1.0" "v2.0.0"
}

@test "version_gt ranks a pre-release below its release" {
    version_gt "2.1.0" "2.1.0-rc1"
    run ! version_gt "2.1.0-rc1" "2.1.0"
    version_gt "2.1.0-rc1" "2.0.0"
}

@test "_selfupdate_verify_tree accepts a fully listed tree" {
    local tree="$TMPDIR_TEST/tree"
    mkdir -p "$tree/lib"
    echo "a" > "$tree/nudge.sh"; echo "b" > "$tree/setup.sh"
    echo "c" > "$tree/install.sh"; echo "d" > "$tree/uninstall.sh"
    echo "e" > "$tree/lib/output.sh"
    (cd "$tree" && sha256sum nudge.sh setup.sh install.sh uninstall.sh lib/output.sh > "$TMPDIR_TEST/SHA256SUMS")
    _selfupdate_verify_tree "$tree" "$TMPDIR_TEST/SHA256SUMS"
}

@test "_selfupdate_verify_tree rejects a shipped script missing from SHA256SUMS" {
    local tree="$TMPDIR_TEST/tree"
    mkdir -p "$tree/lib"
    echo "a" > "$tree/nudge.sh"; echo "b" > "$tree/setup.sh"
    echo "c" > "$tree/install.sh"; echo "d" > "$tree/uninstall.sh"
    echo "e" > "$tree/lib/output.sh"; echo "f" > "$tree/lib/bunny.sh"
    (cd "$tree" && sha256sum nudge.sh setup.sh install.sh uninstall.sh lib/output.sh > "$TMPDIR_TEST/SHA256SUMS")
    run _selfupdate_verify_tree "$tree" "$TMPDIR_TEST/SHA256SUMS"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"lib/bunny.sh"* ]]
}

@test "_selfupdate_verify_tree rejects a checksum mismatch" {
    local tree="$TMPDIR_TEST/tree"
    mkdir -p "$tree/lib"
    echo "a" > "$tree/nudge.sh"; echo "b" > "$tree/setup.sh"
    echo "c" > "$tree/install.sh"; echo "d" > "$tree/uninstall.sh"
    (cd "$tree" && sha256sum nudge.sh setup.sh install.sh uninstall.sh > "$TMPDIR_TEST/SHA256SUMS")
    echo "tampered" > "$tree/nudge.sh"
    run _selfupdate_verify_tree "$tree" "$TMPDIR_TEST/SHA256SUMS"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"mismatch"* ]]
}

@test "selfupdate_check_due returns 0 when no state file" {
    SELFUPDATE_STATE_FILE="$TMPDIR_TEST/nonexistent"
    selfupdate_check_due
}

@test "selfupdate_check_due returns 1 when checked recently" {
    SELFUPDATE_STATE_FILE="$TMPDIR_TEST/selfupdate_check"
    date -Iseconds > "$SELFUPDATE_STATE_FILE"
    run ! selfupdate_check_due
}

@test "selfupdate_check_due returns 1 when disabled" {
    SELF_UPDATE_CHECK=false
    run ! selfupdate_check_due
}

@test "selfupdate_mark_checked creates state file" {
    SELFUPDATE_STATE_FILE="$TMPDIR_TEST/selfupdate_check"
    selfupdate_mark_checked
    [[ -f "$SELFUPDATE_STATE_FILE" ]]
}

@test "selfupdate_check returns newer version when available" {
    SELFUPDATE_STATE_FILE="$TMPDIR_TEST/selfupdate_check_never"
    NUDGE_VERSION="2.0.0"
    SELF_UPDATE_CHECK=true
    SELF_UPDATE_CHANNEL="stable"

    # Mock curl to return canned API response
    curl() {
        echo '{"tag_name": "v2.1.0", "tarball_url": "https://example.com/tarball"}'
    }
    export -f curl

    local result
    result=$(selfupdate_check 2>/dev/null) || true
    [[ "$result" == "2.1.0" ]]
}

@test "selfupdate_check returns empty when up to date" {
    SELFUPDATE_STATE_FILE="$TMPDIR_TEST/selfupdate_check_never"
    NUDGE_VERSION="2.0.0"
    SELF_UPDATE_CHECK=true
    SELF_UPDATE_CHANNEL="stable"

    # Mock curl to return current version
    curl() {
        echo '{"tag_name": "v2.0.0"}'
    }
    export -f curl

    run selfupdate_check
    [[ "$status" -ne 0 ]]
}

@test "selfupdate_check returns 1 on empty API response" {
    SELFUPDATE_STATE_FILE="$TMPDIR_TEST/selfupdate_check_never"
    NUDGE_VERSION="2.0.0"
    SELF_UPDATE_CHECK=true
    SELF_UPDATE_CHANNEL="stable"

    # Mock curl to return empty
    curl() {
        echo ""
    }
    export -f curl

    run selfupdate_check
    [[ "$status" -ne 0 ]]
}

@test "release versions and download hosts are validated" {
    _selfupdate_valid_version "2.1.0"
    _selfupdate_valid_version "2.1.0-rc1"
    run ! _selfupdate_valid_version 'BASH_VERSINFO[$(id)].0.0'
    run ! _selfupdate_valid_version "2.1"
    _selfupdate_valid_url "https://api.github.com/repos/otmof-ops/nudge/tarball/v2.1.0"
    _selfupdate_valid_url "https://github.com/otmof-ops/nudge/releases/download/v2.1.0/SHA256SUMS"
    run ! _selfupdate_valid_url "http://github.com/otmof-ops/nudge/x"
    run ! _selfupdate_valid_url "https://evil.example/x"
}

@test "selfupdate_check keeps the 24h window open when GitHub does not answer" {
    SELFUPDATE_STATE_FILE="$TMPDIR_TEST/selfupdate_check_never"
    SELF_UPDATE_CHECK=true
    SELF_UPDATE_CHANNEL="stable"
    curl() { echo ""; }
    export -f curl
    run selfupdate_check
    [[ ! -f "$SELFUPDATE_STATE_FILE" ]]
}

@test "the beta channel asks the releases list" {
    SELF_UPDATE_CHANNEL="beta"
    [[ "$(_selfupdate_api_url)" == "https://api.github.com/repos/otmof-ops/nudge/releases" ]]
    SELF_UPDATE_CHANNEL="stable"
    [[ "$(_selfupdate_api_url)" == "https://api.github.com/repos/otmof-ops/nudge/releases/latest" ]]
}
