#!/usr/bin/env bats
# Tests for lib/network.sh — multi-method network probe

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)
    MOCK_BIN="$TMPDIR_TEST/bin"
    mkdir -p "$MOCK_BIN"

    # Stub logging and exit codes
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }
    EXIT_NETWORK_FAIL=5
    NUDGE_STATE_DIR="$TMPDIR_TEST/state"
    mkdir -p "$NUDGE_STATE_DIR"

    source "$PROJECT_DIR/lib/network.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "network_probe_once succeeds with working curl" {
    # Create mock curl that always succeeds
    cat > "$MOCK_BIN/curl" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/curl"

    NETWORK_HOST="example.com"
    NETWORK_TIMEOUT=2
    PATH="$MOCK_BIN:$PATH" network_probe_once
}

@test "network_probe_once falls back to wget" {
    # No curl, mock wget succeeds
    cat > "$MOCK_BIN/wget" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/wget"

    # Remove curl from path
    cat > "$MOCK_BIN/curl" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN/curl"

    NETWORK_HOST="example.com"
    NETWORK_TIMEOUT=2
    PATH="$MOCK_BIN:$PATH" network_probe_once
}

@test "network_probe_once falls back to ping" {
    # Both curl and wget fail
    cat > "$MOCK_BIN/curl" << 'EOF'
#!/bin/bash
exit 1
EOF
    cat > "$MOCK_BIN/wget" << 'EOF'
#!/bin/bash
exit 1
EOF
    cat > "$MOCK_BIN/ping" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/curl" "$MOCK_BIN/wget" "$MOCK_BIN/ping"

    NETWORK_HOST="example.com"
    NETWORK_TIMEOUT=2
    PATH="$MOCK_BIN:$PATH" network_probe_once
}

@test "network_probe_once fails when all methods fail" {
    cat > "$MOCK_BIN/curl" << 'EOF'
#!/bin/bash
exit 1
EOF
    cat > "$MOCK_BIN/wget" << 'EOF'
#!/bin/bash
exit 1
EOF
    cat > "$MOCK_BIN/ping" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN/curl" "$MOCK_BIN/wget" "$MOCK_BIN/ping"

    NETWORK_HOST="example.com"
    NETWORK_TIMEOUT=1
    ! PATH="$MOCK_BIN:$PATH" network_probe_once
}

@test "network_check retries on failure" {
    local attempt=0
    # Override probe to fail twice then succeed
    network_probe_once() {
        attempt=$((attempt + 1))
        [[ "$attempt" -ge 3 ]] && return 0
        return 1
    }

    NETWORK_RETRIES=3
    DRY_RUN=true
    CHECK_ONLY=true
    network_check
}

@test "network_handle_offline queue writes pending file" {
    OFFLINE_MODE="queue"
    network_handle_offline || true
    [[ -f "$NUDGE_STATE_DIR/pending_check" ]]
}
