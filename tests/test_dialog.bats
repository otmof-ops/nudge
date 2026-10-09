#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause

bats_require_minimum_version 1.5.0
# Tests for lib/dialog.sh — the dialogs' bodies, the scope and deferral pickers

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)
    MOCK_BIN="$TMPDIR_TEST/bin"
    mkdir -p "$MOCK_BIN" "$TMPDIR_TEST/mascot"
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }
    ORIG_PATH="$PATH"
    source "$PROJECT_DIR/lib/dialog.sh"
    # a mascot of two moods: the rest fall back to the resting one
    echo '<svg/>' > "$TMPDIR_TEST/mascot/bunny.svg"
    echo '<svg/>' > "$TMPDIR_TEST/mascot/bunny-happy.svg"
    NUDGE_MASCOT_DIR="$TMPDIR_TEST/mascot"
    DETECTED_PKGMGR="apt"
    PKG_UPDATES_TOTAL=4 PKG_UPDATES_FLATPAK=1 PKG_UPDATES_SNAP=1
    PKG_UPDATE_LIST=$'vim|1|2|STANDARD|amd64|0\nlinux-image|5.1|5.2|CRITICAL|amd64|0\nopenssl|3.0|3.1|SECURITY|amd64|1\nlibxml2|1|2|STANDARD|i386|0'
    PKG_FLATPAK_LIST='app|app/org.mozilla.firefox/x86_64/stable|org.mozilla.firefox|Firefox|128'
    PKG_SNAP_LIST='core22|20240101|1234|70MB|canonical**'
    NOTIFY_BACKEND="kdialog"
    pkgmgr_native_arch() { echo amd64; }
}

teardown() {
    PATH="$ORIG_PATH"
    rm -rf "$TMPDIR_TEST"
}

_mock_kdialog() {
    # $1 what to print, $2 exit code; every call's args land in KDIALOG_ARGS (appended)
    cat > "$MOCK_BIN/kdialog" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >> "\$KDIALOG_ARGS"
printf '%s\n' "$1"
exit ${2:-0}
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"
    export KDIALOG_ARGS="$TMPDIR_TEST/kdialog_args"
}

# --- escaping and helpers ---

@test "dialog_escape covers the four entities" {
    [[ "$(dialog_escape 'a<b>&"c"')" == 'a&lt;b&gt;&amp;&quot;c&quot;' ]]
}

@test "_dialog_trim cuts with an ellipsis" {
    [[ "$(_dialog_trim abcdefghij 5)" == "abcd…" ]]
    [[ "$(_dialog_trim abc 5)" == "abc" ]]
}

@test "dialog_plain_html escapes and breaks lines" {
    [[ "$(dialog_plain_html 'x <y>\nz')" == '<html><body>x &lt;y&gt;<br>z</body></html>' ]]
}

@test "dialog_mascot_file finds a mood and falls back to the resting bunny" {
    [[ "$(dialog_mascot_file happy)" == "$TMPDIR_TEST/mascot/bunny-happy.svg" ]]
    [[ "$(dialog_mascot_file crying)" == "$TMPDIR_TEST/mascot/bunny.svg" ]]
    [[ "$(dialog_mascot_file normal)" == "$TMPDIR_TEST/mascot/bunny.svg" ]]
    NUDGE_MASCOT_DIR=""
    run ! dialog_mascot_file happy
}

# --- the rows and the tally ---

@test "_dialog_rows puts critical first, then security, then the rest, then flatpak and snap" {
    run _dialog_rows
    [[ "${lines[0]}" == "system|critical|linux-image|5.1|5.2" ]]
    [[ "${lines[1]}" == "system|security|openssl|3.0|3.1" ]]
    [[ "${lines[2]}" == "system|standard|libxml2:i386|1|2" ]]
    [[ "${lines[3]}" == "system|standard|vim|1|2" ]]
    [[ "${lines[4]}" == "flatpak|app|Firefox||128" ]]
    [[ "${lines[5]}" == "snap|snap|core22||20240101" ]]
}

@test "_dialog_tally counts the kinds" {
    _dialog_tally
    [[ "$_DLG_TOTAL" -eq 6 ]]
    [[ "$_DLG_CRIT" -eq 1 ]]
    [[ "$_DLG_SEC" -eq 1 ]]
    [[ "$_DLG_IMPORTANT" -eq 2 ]]
    [[ "$(_dialog_headline)" == "6 updates are ready" ]]
    [[ "$(_dialog_sources)" == "apt 4 · flatpak 1 · snap 1" ]]
    [[ "$(_dialog_sources_long)" == "6 updates · 1 critical · 1 security" ]]
}

# --- the prompt ---

@test "the rich prompt carries the mascot, the headline, the chips, the quote, the names and the hint" {
    run dialog_prompt_html "oh! you gots updates!" happy "You choose what to install next." "nudge v9 is available"
    [[ "$output" == *"<img src=\"$TMPDIR_TEST/mascot/bunny-happy.svg\" width=\"104\" height=\"125\">"* ]]
    [[ "$output" == *"6 updates are ready"* ]]
    [[ "$output" == *"★ 1 critical"* ]]
    [[ "$output" == *"⚠ 1 security"* ]]
    [[ "$output" == *"&#8220;oh! you gots updates!&#8221;"* ]]
    # the display copies carry non-breaking hyphens (U+2011)
    [[ "$output" == *"linux‑image"*"openssl"*"libxml2:i386"*"vim"*"Firefox"*"core22"* ]]
    [[ "$output" == *"You choose what to install next."* ]]
    [[ "$output" == *"nudge v9 is available"* ]]
}

@test "zero chips are left out and the names are capped with a count" {
    PKG_UPDATE_LIST="" PKG_FLATPAK_LIST=""
    PKG_UPDATES_TOTAL=0 PKG_UPDATES_FLATPAK=0 PKG_UPDATES_SNAP=12
    PKG_SNAP_LIST=""
    local i
    for i in $(seq 1 12); do PKG_SNAP_LIST+="snap-$i|1|1|1MB|x"$'\n'; done
    run dialog_prompt_html "" normal "" ""
    [[ "$output" != *"critical"* ]]
    [[ "$output" != *"security"* ]]
    [[ "$output" == *"12 updates are ready"* ]]
    [[ "$output" == *"snap‑8"* ]]
    [[ "$output" != *"snap‑9"* ]]
    [[ "$output" == *"…and 4 more"* ]]
}

@test "the prompt without a mascot has no image and a single update reads as one" {
    NUDGE_MASCOT_DIR=""
    PKG_UPDATES_TOTAL=1 PKG_UPDATES_FLATPAK=0 PKG_UPDATES_SNAP=0
    PKG_UPDATE_LIST='vim|1|2|STANDARD|amd64|0'
    run dialog_prompt_html "" normal "" ""
    [[ "$output" != *"<img"* ]]
    [[ "$output" == *"1 update is ready"* ]]
}

@test "package names are escaped before they reach the rich text" {
    PKG_UPDATE_LIST='evil<b>name|1|2|STANDARD|amd64|0'
    PKG_UPDATES_TOTAL=1 PKG_UPDATES_FLATPAK=0 PKG_UPDATES_SNAP=0
    PKG_FLATPAK_LIST="" PKG_SNAP_LIST=""
    run dialog_prompt_html "" normal "" ""
    [[ "$output" == *"evil&lt;b&gt;name"* ]]
    [[ "$output" != *"evil<b>name"* ]]
    run dialog_prompt_pango "" "" ""
    [[ "$output" == *"evil&lt;b&gt;name"* ]]
    run dialog_fulllist_html
    [[ "$output" == *"evil&lt;b&gt;name"* ]]
}

@test "the Pango prompt uses Pango spans" {
    run dialog_prompt_pango "hi" "pick next" ""
    [[ "$output" == *'<span size="large" weight="bold">6 updates are ready</span>'* ]]
    [[ "$output" == *'<span background="#d93b3b" foreground="#ffffff" weight="bold"> ★ 1 critical </span>'* ]]
    [[ "$output" == *"<i>&#8220;hi&#8221;</i>"* ]]
    [[ "$output" == *"pick next"* ]]
}

# --- the full list ---

@test "the full list groups by source with badges and versions" {
    run dialog_fulllist_html
    [[ "$output" == *"System packages (apt) · 4"* ]]
    [[ "$output" == *"critical&nbsp;</span></td><td>linux-image</td>"* ]]
    [[ "$output" == *"5.1 → 5.2"* ]]
    [[ "$output" == *"Flatpak · 1"* ]]
    [[ "$output" == *"Snaps · 1"* ]]
    run dialog_fulllist_text
    [[ "${lines[0]}" == "System packages (apt) · 4" ]]
    [[ "${lines[1]}" == "  ★ linux-image  5.1 → 5.2" ]]
    [[ "$output" == *"Flatpak · 1"*"◆ Firefox  → 128"* ]]
}

@test "dialog_show_fulllist writes a private file for kdialog and honours AUTO_DISMISS" {
    cat > "$MOCK_BIN/timeout" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$TIMEOUT_ARGS"
# the file kdialog is given must exist and be private
f="${@: -3:1}"
stat -c %a "$f" >> "$TIMEOUT_ARGS"
grep -c '<html>' "$f" >> "$TIMEOUT_ARGS"
exit 0
EOF
    _mock_kdialog "" 0
    chmod +x "$MOCK_BIN/timeout"
    export TIMEOUT_ARGS="$TMPDIR_TEST/timeout_args"
    AUTO_DISMISS=20
    dialog_show_fulllist
    grep -qx '20' "$TIMEOUT_ARGS"
    grep -qx -- '--textbox' "$TIMEOUT_ARGS"
    grep -qx '600' "$TIMEOUT_ARGS"
    grep -qx '1' "$TIMEOUT_ARGS"
}

# --- the scope picker ---

@test "_dialog_scope_items offers the important ones and every source when there are several" {
    run _dialog_scope_items
    [[ "${lines[0]}" == "all|Everything  (6 updates)|on" ]]
    [[ "${lines[1]}" == "important|Critical and security updates only  (2)|off" ]]
    [[ "${lines[2]}" == "system|System packages only  (4, apt)|off" ]]
    [[ "${lines[3]}" == "flatpak|Flatpak only  (1)|off" ]]
    [[ "${lines[4]}" == "snap|Snaps only  (1)|off" ]]
    [[ "${lines[5]}" == "pick|Let me pick one by one…|off" ]]
    [[ "${lines[6]}" == "list|Show me the full list first|off" ]]
}

@test "_dialog_scope_items leaves out what makes no difference" {
    # one source, nothing important: everything, pick, list
    PKG_UPDATES_FLATPAK=0 PKG_UPDATES_SNAP=0 PKG_FLATPAK_LIST="" PKG_SNAP_LIST=""
    PKG_UPDATE_LIST=$'vim|1|2|STANDARD|amd64|0\nnano|1|2|STANDARD|amd64|0'
    PKG_UPDATES_TOTAL=2
    run _dialog_scope_items
    [[ "${#lines[@]}" -eq 3 ]]
    [[ "${lines[0]}" == "all|Everything  (2 updates)|on" ]]
    # everything important: "important" would be "everything"
    PKG_UPDATE_LIST=$'linux-image|1|2|CRITICAL|amd64|0'
    PKG_UPDATES_TOTAL=1
    run _dialog_scope_items
    [[ "${lines[0]}" == "all|Everything  (1 update)|on" ]]
    [[ "$output" != *"important"* ]]
    # pacman never partially upgrades
    DETECTED_PKGMGR=pacman
    PKG_UPDATE_LIST=$'linux|1|2|CRITICAL||0\nvim|1|2|STANDARD||0'
    PKG_UPDATES_TOTAL=2
    run _dialog_scope_items
    [[ "$output" != *"important"* ]]
}

@test "dialog_scope_pick returns the choice, shows the list first when asked, and 1 on cancel" {
    # first call: the list; second call: important
    cat > "$MOCK_BIN/kdialog" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$KDIALOG_ARGS"
n=$(cat "$KDIALOG_COUNT" 2>/dev/null || echo 0)
echo $((n + 1)) > "$KDIALOG_COUNT"
case "$*" in
    *--textbox*) exit 0 ;;
esac
if [[ "$n" -eq 0 ]]; then echo list; else echo important; fi
exit 0
EOF
    chmod +x "$MOCK_BIN/kdialog"
    PATH="$MOCK_BIN:$PATH"
    export KDIALOG_ARGS="$TMPDIR_TEST/kdialog_args" KDIALOG_COUNT="$TMPDIR_TEST/count"
    run dialog_scope_pick happy
    [[ "$status" -eq 0 ]]
    [[ "$output" == "important" ]]
    grep -q -- '--textbox' "$KDIALOG_ARGS"
    grep -q 'What should I install?' "$KDIALOG_ARGS"
    grep -q "bunny-happy.svg" "$KDIALOG_ARGS"
    [[ "$(grep -c -- '--radiolist' "$KDIALOG_ARGS")" -eq 2 ]]
    _mock_kdialog "" 1
    run dialog_scope_pick
    [[ "$status" -eq 1 ]]
}

@test "without kdialog or zenity the scope is the terminal menu" {
    NOTIFY_BACKEND="dunstify"
    PATH="$TMPDIR_TEST/empty"
    run dialog_scope_pick
    PATH="$ORIG_PATH"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "pick" ]]
}

@test "zenity's radiolist gets the tag column hidden and printed" {
    NOTIFY_BACKEND="zenity"
    cat > "$MOCK_BIN/zenity" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$ZENITY_ARGS"
echo "snap"
exit 0
EOF
    chmod +x "$MOCK_BIN/zenity"
    PATH="$MOCK_BIN:$PATH"
    export ZENITY_ARGS="$TMPDIR_TEST/zenity_args"
    run dialog_scope_pick
    [[ "$output" == "snap" ]]
    grep -qx -- '--radiolist' "$ZENITY_ARGS"
    grep -qx -- '--hide-column=2' "$ZENITY_ARGS"
    grep -qx -- '--print-column=2' "$ZENITY_ARGS"
    grep -qx 'TRUE' "$ZENITY_ARGS"
    grep -qx 'Snaps only  (1)' "$ZENITY_ARGS"
}

# --- deferral ---

@test "_dialog_defer_label speaks plainly" {
    [[ "$(_dialog_defer_label 1h)" == "In an hour" ]]
    [[ "$(_dialog_defer_label 4h)" == "In 4 hours" ]]
    [[ "$(_dialog_defer_label 1d)" == "Tomorrow" ]]
    [[ "$(_dialog_defer_label 3d)" == "In 3 days" ]]
    [[ "$(_dialog_defer_label 1w)" == "Next week" ]]
    [[ "$(_dialog_defer_label 2w)" == "In 2 weeks" ]]
    [[ "$(_dialog_defer_label soon)" == "soon" ]]
}

@test "dialog_defer_pick lists the configured options with the first one on" {
    _mock_kdialog "4h" 0
    DEFERRAL_OPTIONS="1h,4h,1d"
    run dialog_defer_pick "okie dokie"
    [[ "$output" == "4h" ]]
    grep -q 'When should I ask again?' "$KDIALOG_ARGS"
    grep -q 'okie dokie' "$KDIALOG_ARGS"
    grep -qx 'In an hour' "$KDIALOG_ARGS"
    grep -qx 'Tomorrow' "$KDIALOG_ARGS"
    [[ "$(grep -cx 'on' "$KDIALOG_ARGS")" -eq 1 ]]
    _mock_kdialog "" 1
    run dialog_defer_pick
    [[ "$status" -eq 1 ]]
}

@test "without a picker the deferral is the first option" {
    NOTIFY_BACKEND="notify-send"
    PATH="$TMPDIR_TEST/empty"
    DEFERRAL_OPTIONS="2h,1d"
    run dialog_defer_pick
    PATH="$ORIG_PATH"
    [[ "$output" == "2h" ]]
}

# --- reboot ---

@test "dialog_reboot_ask maps the buttons and draws the worried bunny" {
    echo '<svg/>' > "$TMPDIR_TEST/mascot/bunny-worried.svg"
    _mock_kdialog "" 0
    dialog_reboot_ask "nap time"
    grep -q 'bunny-worried.svg' "$KDIALOG_ARGS"
    grep -q 'nap time' "$KDIALOG_ARGS"
    grep -qx 'Later' "$KDIALOG_ARGS"
    _mock_kdialog "" 1
    run ! dialog_reboot_ask
}
