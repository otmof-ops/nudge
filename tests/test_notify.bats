#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
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
    # Mock kdialog so command -v check passes
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"
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
    [[ "$NOTIFY_RESPONSE" == "passive" ]]
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

@test "kdialog No button (Remind Me Later) sets response to deferred" {
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="kdialog"
    AUTO_DISMISS=0
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "deferred" ]]
}

@test "kdialog Cancel button, Esc or closing (Not Now) sets response to declined" {
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
exit 2
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="kdialog"
    AUTO_DISMISS=0
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "declined" ]]
}

@test "kdialog buttons are labelled Update Now / Remind Me Later / Not Now" {
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$KDIALOG_ARGS"
exit 0
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"
    export KDIALOG_ARGS="$TMPDIR_TEST/kdialog_args"

    NOTIFY_BACKEND="kdialog"
    AUTO_DISMISS=0
    PREVIEW_UPDATES="false"
    notify_prompt "test"
    grep -qx -- '--yes-label' "$KDIALOG_ARGS"
    grep -qx 'Update Now' "$KDIALOG_ARGS"
    grep -qx 'Remind Me Later' "$KDIALOG_ARGS"
    grep -qx 'Not Now' "$KDIALOG_ARGS"
}

@test "kdialog failing to open the display is a backend failure, not a decline" {
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
echo "qt.qpa.xcb: could not connect to display :99" >&2
exit 1
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="kdialog"
    AUTO_DISMISS=0
    PREVIEW_UPDATES="false"
    run notify_prompt "test"
    [[ "$status" -ne 0 ]]
}

@test "zenity failing to open the display is a backend failure, not a decline" {
    cat > "$MOCK_BIN/zenity" <<'EOF'
#!/bin/bash
echo "(zenity:1): Gtk-WARNING **: cannot open display: :99" >&2
exit 1
EOF
    chmod +x "$MOCK_BIN/zenity"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="zenity"
    AUTO_DISMISS=0
    PREVIEW_UPDATES="false"
    run notify_prompt "test"
    [[ "$status" -ne 0 ]]
}

@test "a benign Qt warning on stderr is not mistaken for a display failure" {
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
echo "qt.qpa.wayland: Wayland does not support QWindow::requestActivate()" >&2
exit 2
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="kdialog"
    AUTO_DISMISS=0
    PREVIEW_UPDATES="false"
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "declined" ]]
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

@test "gdbus backend reports passive, never a decline" {
    cat > "$MOCK_BIN/gdbus" <<'EOF'
#!/bin/bash
echo "(uint32 1,)"
EOF
    chmod +x "$MOCK_BIN/gdbus"
    PATH="$MOCK_BIN:$PATH"

    NOTIFY_BACKEND="gdbus"
    AUTO_DISMISS=0
    notify_prompt "test"
    [[ "$NOTIFY_RESPONSE" == "passive" ]]
}

@test "the kdialog preview honours AUTO_DISMISS" {
    cat > "$MOCK_BIN/timeout" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$TIMEOUT_ARGS"
exit 0
EOF
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/timeout" "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"
    export TIMEOUT_ARGS="$TMPDIR_TEST/timeout_args"
    NOTIFY_BACKEND="kdialog"
    AUTO_DISMISS=30
    PREVIEW_UPDATES="true"
    notify_prompt "test" "pkg 1 -> 2"
    # both the preview and the question went through timeout
    [[ "$(grep -c '^30$' "$TIMEOUT_ARGS")" -eq 2 ]]
    grep -q -- '--textbox' "$TIMEOUT_ARGS"
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

@test "zenity 4's 'Failed to open display' is a backend failure too" {
    cat > "$MOCK_BIN/zenity" <<'EOF'
#!/bin/bash
echo "(zenity:1): Gtk-WARNING **: 17:09:19.536: Failed to open display" >&2
exit 1
EOF
    chmod +x "$MOCK_BIN/zenity"
    PATH="$MOCK_BIN:$PATH"
    NOTIFY_BACKEND="zenity"
    AUTO_DISMISS=0
    PREVIEW_UPDATES="false"
    run notify_prompt "test"
    [[ "$status" -ne 0 ]]
}

@test "the dialogs use the Nudge Bunny icon once it is installed" {
    [[ "$(_notify_icon name)" == "system-software-update" ]]
    local prefix="$TMPDIR_TEST/prefix"
    mkdir -p "$prefix/.local/share/icons/hicolor/scalable/apps"
    echo '<svg/>' > "$prefix/.local/share/icons/hicolor/scalable/apps/nudge.svg"
    NUDGE_PREFIX="$prefix"
    [[ "$(_notify_icon name)" == "nudge" ]]
    [[ "$(_notify_icon path)" == "$prefix/.local/share/icons/hicolor/scalable/apps/nudge.svg" ]]
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$KDIALOG_ARGS"
exit 0
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"
    export KDIALOG_ARGS="$TMPDIR_TEST/kdialog_args"
    NOTIFY_BACKEND="kdialog"
    AUTO_DISMISS=0
    PREVIEW_UPDATES="false"
    notify_prompt "test"
    grep -qx 'nudge' "$KDIALOG_ARGS"
}
