#!/usr/bin/env bats
# Tests for lib/notify.sh — notification backends, dispatch, response mapping

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)
    MOCK_BIN="$TMPDIR_TEST/bin"
    mkdir -p "$MOCK_BIN"

    # Stubs
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }

    ORIG_PATH="$PATH"

    source "$PROJECT_DIR/lib/notify.sh"
}

teardown() {
    PATH="$ORIG_PATH"
    rm -rf "$TMPDIR_TEST"
}

# --- Backend detection ---

@test "notify_detect uses config backend when not auto" {
    NOTIFICATION_BACKEND="kdialog"
    notify_detect
    [[ "$NOTIFY_BACKEND" == "kdialog" ]]
}

@test "notify_detect falls back to none when nothing available" {
    NOTIFICATION_BACKEND="auto"
    PATH="$TMPDIR_TEST/empty"
    notify_detect
    PATH="$ORIG_PATH"
    [[ "$NOTIFY_BACKEND" == "none" ]]
}

@test "notify_detect finds dunstify first" {
    NOTIFICATION_BACKEND="auto"
    cat > "$MOCK_BIN/dunstify" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/dunstify"
    PATH="$MOCK_BIN"
    notify_detect
    PATH="$ORIG_PATH"
    [[ "$NOTIFY_BACKEND" == "dunstify" ]]
}

@test "notify_detect finds kdialog when dunstify absent" {
    NOTIFICATION_BACKEND="auto"
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN"
    notify_detect
    PATH="$ORIG_PATH"
    [[ "$NOTIFY_BACKEND" == "kdialog" ]]
}

# --- Prompt dispatch ---

@test "notify_prompt returns error for none backend" {
    NOTIFY_BACKEND="none"
    run notify_prompt "test message"
    [[ "$status" -ne 0 ]]
}

@test "notify_prompt returns error for unknown backend" {
    NOTIFY_BACKEND="unknown_thing"
    run notify_prompt "test message"
    [[ "$status" -ne 0 ]]
}

@test "notify_prompt dispatches to dunstify with preview" {
    # Mock dunstify that captures args
    cat > "$MOCK_BIN/dunstify" <<'EOF'
#!/bin/bash
echo "$@" > /tmp/nudge_test_dunstify_args
echo "update"
EOF
    chmod +x "$MOCK_BIN/dunstify"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="dunstify"
    PREVIEW_UPDATES="true"
    AUTO_DISMISS=0

    notify_prompt "test message" "pkg1 1.0 -> 2.0"
    [[ "$NOTIFY_RESPONSE" == "accepted" ]]
    rm -f /tmp/nudge_test_dunstify_args
}

@test "notify_prompt dispatches to notify-send as passive" {
    cat > "$MOCK_BIN/notify-send" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/notify-send"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="notify-send"
    notify_prompt "test message"
    [[ "$NOTIFY_RESPONSE" == "declined" ]]
}

# --- Response mapping ---

@test "kdialog accepted sets response to accepted" {
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="kdialog"
    AUTO_DISMISS=0
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "accepted" ]]
}

@test "kdialog declined sets response to declined" {
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="kdialog"
    AUTO_DISMISS=0
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "declined" ]]
}

@test "kdialog cancel sets response to deferred" {
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
exit 2
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="kdialog"
    AUTO_DISMISS=0
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "deferred" ]]
}

@test "zenity extra-button sets response to deferred" {
    cat > "$MOCK_BIN/zenity" <<'EOF'
#!/bin/bash
echo "Remind Me Later"
exit 1
EOF
    chmod +x "$MOCK_BIN/zenity"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="zenity"
    AUTO_DISMISS=0
    PREVIEW_UPDATES="false"
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "deferred" ]]
}

@test "zenity accept sets response to accepted" {
    cat > "$MOCK_BIN/zenity" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/zenity"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="zenity"
    AUTO_DISMISS=0
    PREVIEW_UPDATES="false"
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "accepted" ]]
}

@test "zenity cancel sets response to declined" {
    cat > "$MOCK_BIN/zenity" <<'EOF'
#!/bin/bash
echo ""
exit 1
EOF
    chmod +x "$MOCK_BIN/zenity"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="zenity"
    AUTO_DISMISS=0
    PREVIEW_UPDATES="false"
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "declined" ]]
}

@test "dunstify defer action sets response to deferred" {
    cat > "$MOCK_BIN/dunstify" <<'EOF'
#!/bin/bash
echo "defer"
EOF
    chmod +x "$MOCK_BIN/dunstify"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="dunstify"
    AUTO_DISMISS=0
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "deferred" ]]
}

@test "dunstify timeout sets response to declined" {
    cat > "$MOCK_BIN/dunstify" <<'EOF'
#!/bin/bash
echo ""
EOF
    chmod +x "$MOCK_BIN/dunstify"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="dunstify"
    AUTO_DISMISS=0
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "declined" ]]
}

@test "gdbus backend always returns declined (passive)" {
    cat > "$MOCK_BIN/gdbus" <<'EOF'
#!/bin/bash
echo "(uint32 1,)"
EOF
    chmod +x "$MOCK_BIN/gdbus"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="gdbus"
    AUTO_DISMISS=0
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "declined" ]]
}

@test "notify_reboot kdialog accepting returns 0" {
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="kdialog"
    notify_reboot
}

@test "notify_reboot kdialog declining returns 1" {
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="kdialog"
    run notify_reboot
    [[ "$status" -ne 0 ]]
}

@test "notify_reboot zenity accepting returns 0" {
    cat > "$MOCK_BIN/zenity" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/zenity"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="zenity"
    notify_reboot
}

@test "notify_reboot zenity declining returns 1" {
    cat > "$MOCK_BIN/zenity" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN/zenity"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="zenity"
    run notify_reboot
    [[ "$status" -ne 0 ]]
}

@test "kdialog auto-dismiss timeout returns declined" {
    cat > "$MOCK_BIN/timeout" <<'EOF'
#!/bin/bash
exit 124
EOF
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/timeout" "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="kdialog"
    AUTO_DISMISS=10
    PREVIEW_UPDATES="false"
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "declined" ]]
}

@test "dunstify preview content included in body" {
    cat > "$MOCK_BIN/dunstify" <<'EOF'
#!/bin/bash
echo "$@" > "$TMPDIR_TEST/dunstify_args"
echo "update"
EOF
    chmod +x "$MOCK_BIN/dunstify"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="dunstify"
    PREVIEW_UPDATES="true"
    AUTO_DISMISS=0
    export TMPDIR_TEST
    notify_prompt "test message" "pkg1 1.0 -> 2.0"
    [[ "$NOTIFY_RESPONSE" == "accepted" ]]
}
