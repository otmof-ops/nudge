#!/usr/bin/env bats
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
    grep -q 'CONF_VERSION="2.0.0"' "$outfile"
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
    grep -q 'CONF_VERSION="2.0.0"' "$NUDGE_CONFIG_FILE"
}
