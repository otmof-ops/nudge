#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause

bats_require_minimum_version 1.5.0
# Tests for lib/retry.sh — the diagnosis of a failed step, the ledger of
# updates that keep failing, and the failure report

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)
    export NUDGE_STATE_DIR="$TMPDIR_TEST/state"
    mkdir -p "$NUDGE_STATE_DIR"
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }
    source "$PROJECT_DIR/lib/output.sh"
    source "$PROJECT_DIR/lib/retry.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

# A captured stderr to diagnose: _captured <name> <lines...> -> the path
_captured() {
    local name="$1"; shift
    printf '%s\n' "$@" > "$TMPDIR_TEST/$name.log"
    printf '%s' "$TMPDIR_TEST/$name.log"
}

# --- The diagnosis ---

@test "apt: a held lock is diagnosed, with the holder's pid as the name" {
    retry_diagnose system apt 100 "$(_captured a "E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 4321 (apt-get)" "E: Unable to acquire the dpkg frontend lock")"
    [[ "$_RETRY_CAUSE" == "lock" ]]
    [[ "$_RETRY_CULPRITS" == "4321" ]]
    [[ "$_RETRY_EVIDENCE" == *"held by process 4321"* ]]
    [[ "$(retry_cause_headline lock apt system 4321)" == "another package manager is running (pid 4321)" ]]
}

@test "apt: an interrupted dpkg and a damaged index are told apart from a lock" {
    retry_diagnose system apt 100 "$(_captured a "E: dpkg was interrupted, you must manually run 'sudo dpkg --configure -a' to correct the problem.")"
    [[ "$_RETRY_CAUSE" == "dpkg-interrupted" ]]
    retry_diagnose system apt 100 "$(_captured b "E: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/noble/InRelease  Hash Sum mismatch")"
    [[ "$_RETRY_CAUSE" == "index-corrupt" ]]
    retry_diagnose system apt 100 "$(_captured c "E: Release file for http://x/dists/noble/InRelease is not valid yet (invalid for another 2h). Updates for this repository will not be applied.")"
    [[ "$_RETRY_CAUSE" == "index-corrupt" ]]
    [[ "$(retry_cause_remedy index-corrupt apt system)" == *"timedatectl"* ]]
}

@test "apt: a package whose install script failed is named" {
    retry_diagnose system apt 100 "$(_captured a "dpkg: error processing package libfoo-dev (--configure):" " installed libfoo-dev package post-installation script subprocess returned error exit status 1" "Errors were encountered while processing:" " libfoo-dev" "E: Sub-process /usr/bin/dpkg returned an error code (1)")"
    [[ "$_RETRY_CAUSE" == "package-script" ]]
    [[ "$_RETRY_CULPRITS" == "libfoo-dev" ]]
    [[ "$(retry_cause_headline package-script apt system libfoo-dev)" == "the install script of libfoo-dev failed" ]]
    [[ "$(retry_cause_remedy package-script apt system libfoo-dev)" == *"sudo dpkg --configure -a"* ]]
    [[ "$(retry_cause_remedy package-script apt system libfoo-dev)" == *"--reinstall libfoo-dev"* ]]
}

@test "apt: held broken packages, a missing key, a stale mirror and no network each have their cause" {
    retry_diagnose system apt 100 "$(_captured a "The following packages have unmet dependencies:" " libc6 : Depends: libgcc-s1 but it is not going to be installed" "E: Unable to correct problems, you have held broken packages.")"
    [[ "$_RETRY_CAUSE" == "deps-broken" ]]
    [[ "$_RETRY_CULPRITS" == "libc6" ]]
    retry_diagnose system apt 100 "$(_captured b "W: GPG error: https://ppa.launchpadcontent.net/x/y/ubuntu noble InRelease: The following signatures couldn't be verified because the public key is not available: NO_PUBKEY 7F0CEB10E5A1F9CA" "E: The repository 'https://ppa... noble InRelease' is not signed.")"
    [[ "$_RETRY_CAUSE" == "repo-key" ]]
    [[ "$_RETRY_CULPRITS" == "7F0CEB10E5A1F9CA" ]]
    retry_diagnose system apt 100 "$(_captured c "E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/v/vim/vim_9.1.0016-1ubuntu7.9_amd64.deb  404  Not Found [IP: 1.2.3.4 80]" "E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?")"
    [[ "$_RETRY_CAUSE" == "mirror-stale" ]]
    [[ "$_RETRY_CULPRITS" == "vim" ]]
    retry_diagnose system apt 100 "$(_captured d "Err:1 http://archive.ubuntu.com/ubuntu noble InRelease" "  Temporary failure resolving 'archive.ubuntu.com'")"
    [[ "$_RETRY_CAUSE" == "network" ]]
}

@test "a full disk and a refused sudo come before the manager's own messages" {
    retry_diagnose system apt 100 "$(_captured a "dpkg: error processing archive /var/cache/apt/archives/x.deb (--unpack):" " cannot copy extracted data for './usr/lib/x' to '/usr/lib/x.dpkg-new': failed to write (No space left on device)")"
    [[ "$_RETRY_CAUSE" == "disk-full" ]]
    [[ "$(retry_cause_remedy disk-full apt system)" == *"sudo apt clean"* ]]
    retry_diagnose system apt 1 "$(_captured b "Sorry, try again." "sudo: 3 incorrect password attempts")"
    [[ "$_RETRY_CAUSE" == "sudo-password" ]]
    retry_diagnose system apt 1 "$(_captured c "jay is not in the sudoers file.")"
    [[ "$_RETRY_CAUSE" == "sudo-denied" ]]
}

@test "snap: running apps are named, snapd busy and the store unreachable are told apart" {
    retry_diagnose snap apt 1 "$(_captured a 'error: cannot refresh "firefox", "chromium": snap "firefox" has running apps (firefox), pids: 1234' 'snap "chromium" has running apps (chromium), pids: 99')"
    [[ "$_RETRY_CAUSE" == "snap-running" ]]
    [[ "$_RETRY_CULPRITS" == $'firefox\nchromium' ]]
    [[ "$(retry_cause_headline snap-running apt snap firefox chromium)" == "firefox, chromium are still running" ]]
    [[ "$(retry_cause_headline snap-running apt snap firefox)" == "firefox is still running" ]]
    retry_diagnose snap apt 1 "$(_captured b "error: too early for operation, device not yet seeded or device model not acknowledged")"
    [[ "$_RETRY_CAUSE" == "snap-busy" ]]
    retry_diagnose snap apt 1 "$(_captured c "error: cannot refresh: cannot communicate with server: Post ...")"
    [[ "$_RETRY_CAUSE" == "network" ]]
}

@test "flatpak: a remote that cannot be reached is named; an app that failed is named; no room is no room" {
    retry_diagnose flatpak apt 1 "$(_captured a "error: Unable to load summary from remote flathub: Server returned status 503: Service Unavailable")"
    [[ "$_RETRY_CAUSE" == "repo-unreachable" ]]
    [[ "$_RETRY_CULPRITS" == "flathub" ]]
    [[ "$(retry_cause_remedy repo-unreachable apt flatpak flathub)" == *"flatpak remote-ls flathub"* ]]
    retry_diagnose flatpak apt 1 "$(_captured b "Error updating org.videolan.VLC/x86_64/stable: Failed to install bundle" "error: Failed to update org.videolan.VLC/x86_64/stable")"
    [[ "$_RETRY_CAUSE" == "flatpak-app" ]]
    [[ "$_RETRY_CULPRITS" == "org.videolan.VLC/x86_64/stable" ]]
    retry_diagnose flatpak apt 1 "$(_captured c "error: Not enough disk space to complete this operation")"
    [[ "$_RETRY_CAUSE" == "disk-full" ]]
}

@test "dnf, pacman and zypper: their locks, repositories, keys and conflicts" {
    retry_diagnose system dnf 1 "$(_captured a "Error: Failed to download metadata for repo 'rpmfusion-free': Cannot download repomd.xml")"
    [[ "$_RETRY_CAUSE" == "repo-unreachable" ]]
    [[ "$_RETRY_CULPRITS" == "rpmfusion-free" ]]
    [[ "$(retry_cause_remedy repo-unreachable dnf system rpmfusion-free)" == *"--disablerepo=rpmfusion-free"* ]]
    retry_diagnose system dnf 1 "$(_captured b "Public key for foo-1.0-1.fc40.x86_64.rpm is not installed." "Error: GPG check FAILED")"
    [[ "$_RETRY_CAUSE" == "repo-key" ]]
    retry_diagnose system dnf 1 "$(_captured c "Error:" " Problem: conflicting requests" "  - package foo-2.0-1.fc40.x86_64 conflicts with bar provided by bar-1.0-1.fc40.x86_64")"
    [[ "$_RETRY_CAUSE" == "deps-broken" ]]
    retry_diagnose system pacman 1 "$(_captured d "error: failed to init transaction (unable to lock database)")"
    [[ "$_RETRY_CAUSE" == "lock" ]]
    [[ "$(retry_cause_remedy lock pacman system)" == *"sudo rm /var/lib/pacman/db.lck"* ]]
    retry_diagnose system pacman 1 "$(_captured e "error: failed to commit transaction (conflicting files)" "python-foo: /usr/lib/python3.12/site-packages/foo.py exists in filesystem")"
    [[ "$_RETRY_CAUSE" == "file-conflict" ]]
    [[ "$_RETRY_CULPRITS" == "python-foo" ]]
    retry_diagnose system pacman 1 "$(_captured f 'error: libfoo: signature from "Some One <x@y>" is unknown trust')"
    [[ "$_RETRY_CAUSE" == "repo-key" ]]
    [[ "$(retry_cause_remedy repo-key pacman system)" == *"archlinux-keyring"* ]]
    retry_diagnose system zypper 7 "$(_captured g "System management is locked by the application with pid 2222 (zypper).")"
    [[ "$_RETRY_CAUSE" == "lock" ]]
    [[ "$_RETRY_CULPRITS" == "2222" ]]
}

@test "what nobody recognises is unknown, with the error lines as the evidence; an interrupt is its own cause" {
    retry_diagnose system apt 42 "$(_captured a "E: Something odd happened here" "and nobody knows why")"
    [[ "$_RETRY_CAUSE" == "unknown" ]]
    [[ "$_RETRY_EVIDENCE" == "E: Something odd happened here" ]]
    [[ "$(retry_cause_remedy unknown apt system)" == *"saved"* ]]
    retry_diagnose system apt 130 "$(_captured b "^C")"
    [[ "$_RETRY_CAUSE" == "interrupted" ]]
    retry_diagnose system apt 1 "$TMPDIR_TEST/does-not-exist.log"
    [[ "$_RETRY_CAUSE" == "unknown" ]]
    [[ -z "$_RETRY_EVIDENCE" ]]
}

@test "a no to the package manager's own question and an unverifiable repository certificate have their causes" {
    # apt's "Abort." goes to stdout: the capture holds warnings at most, and apt exits 1 (its errors are 100)
    retry_diagnose system apt 1 "$(_captured a "W: Some index files failed to download. They have been ignored, or old ones used instead.")"
    [[ "$_RETRY_CAUSE" == "declined" ]]
    retry_record_failure system apt 1 "$TMPDIR_TEST/a.log" 1 vim
    [[ ! -f "$RETRY_LEDGER_FILE" ]]
    retry_diagnose system apt 1 "$(_captured a2 "E: Unable to locate package foo")"
    [[ "$_RETRY_CAUSE" != "declined" ]]
    retry_diagnose system apt 100 "$(_captured a3 "W: nothing to see")"
    [[ "$_RETRY_CAUSE" == "unknown" ]]
    retry_diagnose flatpak apt 1 "$(_captured a4 "")"
    [[ "$_RETRY_CAUSE" == "unknown" ]]
    retry_diagnose system apt 100 "$(_captured b "W: Failed to fetch https://repo.nordvpn.com/deb/nordvpn/debian/dists/stable/InRelease  Certificate verification failed: The certificate is NOT trusted. The certificate issuer is unknown.  Could not handshake: Error in the certificate verification. [IP: 208.91.112.55 443]" "E: Some index files failed to download.")"
    [[ "$_RETRY_CAUSE" == "repo-tls" ]]
    [[ "$_RETRY_CULPRITS" == "repo.nordvpn.com" ]]
    [[ "$(retry_cause_headline repo-tls apt system repo.nordvpn.com)" == *"repo.nordvpn.com could not be verified" ]]
    [[ "$(retry_cause_remedy repo-tls apt system repo.nordvpn.com)" == *"grep -r \"repo.nordvpn.com\" /etc/apt/sources.list"* ]]
    retry_record_failure system apt 100 "$TMPDIR_TEST/b.log" 1 vim
    [[ "$(retry_ledger_rows | cut -f2)" == "vim" ]]
    [[ "${_RETRY_F_CULPRITS[system]}" == "repo.nordvpn.com" ]]
}

@test "no network comes before a stale mirror; 404 is a status, not a name" {
    retry_diagnose system apt 100 "$(_captured a "E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/v/vim/vim_9.1_amd64.deb  Temporary failure resolving 'archive.ubuntu.com'" "E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?")"
    [[ "$_RETRY_CAUSE" == "network" ]]
    retry_diagnose system apt 100 "$(_captured b "E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/v/vim/vim_9.1_amd64.deb  404  Not Found [IP: 1.2.3.4 80]" "E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?")"
    [[ "$_RETRY_CAUSE" == "mirror-stale" && "$_RETRY_CULPRITS" == "vim" ]]
    retry_diagnose system pacman 1 "$(_captured c "error: failed retrieving file 'core.db' from mirror.example.org : Could not resolve host: mirror.example.org")"
    [[ "$_RETRY_CAUSE" == "network" ]]
    retry_diagnose system apt 100 "$(_captured d "E: Unable to locate package libfoo404")"
    [[ "$_RETRY_CAUSE" == "unknown" ]]
}

@test "no DNS on dnf is the network, never a repository to disable for good" {
    retry_diagnose system dnf 1 "$(_captured a "Errors during downloading metadata for repository 'updates':" "  - Curl error (6): Couldn't resolve host name for https://mirrors.fedoraproject.org/metalink?repo=updates-released-f40 [Could not resolve host: mirrors.fedoraproject.org]" "Error: Failed to download metadata for repo 'updates': Cannot prepare internal mirrorlist: Curl error (6): Couldn't resolve host name")"
    [[ "$_RETRY_CAUSE" == "network" ]]
    [[ "$(retry_cause_remedy repo-unreachable dnf system updates)" != *"set-disabled"* ]]
    retry_diagnose flatpak apt 1 "$(_captured b "error: Unable to load summary from remote flathub: While fetching https://dl.flathub.org/repo/summary.idx: [6] Couldn't resolve host name")"
    [[ "$_RETRY_CAUSE" == "network" ]]
}

@test "what is quoted is scrubbed: credentials in a URL, invisible characters; look-alike letters are not names" {
    retry_diagnose system apt 100 "$(_captured a "E: Failed to fetch https://user:s3cret@repo.example.org/pool/x.deb?token=abc123&x=1  404  Not Found")"
    [[ "$_RETRY_CAUSE" == "mirror-stale" ]]
    [[ "$_RETRY_EVIDENCE" == *"https://[redacted]@repo.example.org/"* ]]
    [[ "$_RETRY_EVIDENCE" == *"token=[redacted]&x=1"* ]]
    [[ "$_RETRY_EVIDENCE" != *"s3cret"* && "$_RETRY_EVIDENCE" != *"abc123"* ]]
    retry_diagnose system apt 100 "$(_captured b $'E: Could not get lock \xe2\x80\xae/var/lib/dpkg/lock\xe2\x80\x8b-frontend. It is held by process 77 (apt)\xc2\x9b')"
    [[ "$_RETRY_EVIDENCE" != *$'\xe2\x80\xae'* && "$_RETRY_EVIDENCE" != *$'\xe2\x80\x8b'* && "$_RETRY_EVIDENCE" != *$'\xc2\x9b'* ]]
    [[ "$_RETRY_CULPRITS" == "77" ]]
    run ! retry_valid_name $'v\xd1\x96m'
    run ! retry_valid_name $'vim\xe2\x80\x8b'
    retry_valid_name "vim"
}

@test "every blamed name is kept, the last one too" {
    retry_diagnose system apt 100 "$(_captured a "dpkg: error processing archive /var/cache/apt/archives/foo_1.0_amd64.deb (--unpack):" " trying to overwrite '/usr/bin/x', which is also in package bar 2.0" "dpkg: error processing archive /var/cache/apt/archives/baz_3.0_amd64.deb (--unpack):" "E: Sub-process /usr/bin/dpkg returned an error code (1)")"
    [[ "$_RETRY_CAUSE" == "package-script" ]]
    [[ "$_RETRY_CULPRITS" == "bar" ]]
    retry_diagnose system apt 100 "$(_captured b "dpkg: error processing archive /var/cache/apt/archives/foo_1.0_amd64.deb (--unpack):" " cannot copy extracted data" "dpkg: error processing archive /var/cache/apt/archives/baz_3.0_amd64.deb (--unpack):" " cannot copy extracted data" "E: Sub-process /usr/bin/dpkg returned an error code (1)")"
    [[ "$_RETRY_CULPRITS" == $'foo\nbaz' ]]
}

@test "snapd not running, a rejected update command, and the user's own no are their own causes" {
    retry_diagnose snap apt 1 "$(_captured a 'error: cannot communicate with server: Get "http://localhost/v2/snaps": dial unix /run/snapd.socket: connect: no such file or directory')"
    [[ "$_RETRY_CAUSE" == "snapd-down" ]]
    [[ "$(retry_cause_remedy snapd-down apt snap)" == *"systemctl start snapd"* ]]
    retry_diagnose system apt 1 "$(_captured b "E: nudge: the update command was rejected: 'rm' is not a known package tool")"
    [[ "$_RETRY_CAUSE" == "config" ]]
    run ! retry_cause_retriable config
    run ! retry_cause_counts config
    retry_cause_retriable sudo-password
    run ! retry_cause_counts sudo-password
    retry_cause_retriable lock
    retry_cause_counts lock
    # apt's no: exit 1 and no E: line; dnf's and pacman's: exit 1 and nothing captured at all
    retry_diagnose system dnf 1 "$(_captured c "")"
    [[ "$_RETRY_CAUSE" == "declined" ]]
    retry_diagnose system dnf 1 "$(_captured d "some words, no error")"
    [[ "$_RETRY_CAUSE" == "unknown" ]]
    retry_diagnose system apt 1 "$(_captured e "E: something")"
    [[ "$_RETRY_CAUSE" == "unknown" ]]
    retry_diagnose system apt 1 "$(_captured f "sudo: a terminal is required to read the password")"
    [[ "$_RETRY_CAUSE" == "sudo-no-tty" ]]
}

@test "a mistyped password, a Ctrl-C and a rejected command are not held against the update" {
    retry_record_failure system apt 1 "$(_captured a "Sorry, try again." "sudo: 3 incorrect password attempts")" 1 vim openssl
    [[ ! -f "$RETRY_LEDGER_FILE" ]]
    [[ "${_RETRY_F_STREAK[system]}" -eq 0 ]]
    printf 'system\tvim\t2\t2026-10-23T09:00:00+08:00\t2026-10-24T09:00:00+08:00\tlock\n' > "$RETRY_LEDGER_FILE"
    retry_record_failure system apt 130 "$(_captured b "^C")" 1 vim
    [[ "${_RETRY_F_STREAK[system]}" -eq 0 ]]
    run ! retry_report_due
    retry_record_failure system apt 1 "$(_captured c "E: nudge: the update command was rejected: bad")" 1 vim
    [[ "${_RETRY_F_CAUSE[system]}" == "config" && "${_RETRY_F_STREAK[system]}" -eq 0 ]]
    [[ "$(awk -F'\t' '$2 == "vim" {print $3}' "$RETRY_LEDGER_FILE")" == "2" ]]
}

@test "a ledger that cannot be written is a warning, not the end of the session" {
    _warned=""
    log_warn() { _warned="$*"; }
    printf 'system\tvim\t1\t2026-10-23T09:00:00+08:00\t2026-10-24T09:00:00+08:00\tlock\n' > "$RETRY_LEDGER_FILE"
    local log
    log=$(_captured a "E: Could not get lock x")
    chmod 500 "$NUDGE_STATE_DIR"
    retry_record_failure system apt 100 "$log" 1 vim
    [[ "${_RETRY_F_CAUSE[system]}" == "lock" ]]
    [[ "$_warned" == *"ledger could not be written"* ]]
    _warned=""
    retry_record_success system vim
    [[ "$_warned" == *"ledger could not be written"* ]]
    chmod 700 "$NUDGE_STATE_DIR"
}

@test "the capture of an attempt that went through on the next try is deleted, and logs rotate as they are made" {
    local log
    log=$(retry_log_path system 1)
    echo "E: Could not get lock x" > "$log"
    retry_record_failure system apt 100 "$log" 1 vim
    retry_record_success system vim
    [[ ! -e "$log" ]]
    RETRY_LOG_MAX=2
    local l1 l2 l3
    l1=$(retry_log_path system 1); sleep 1; l2=$(retry_log_path system 2); sleep 1; l3=$(retry_log_path system 3)
    [[ ! -e "$l1" && -e "$l2" && -e "$l3" ]]
}

@test "colour codes and control characters are stripped before the output is read" {
    retry_diagnose system apt 100 "$(_captured a $'\e[31mE: Could not get lock /var/lib/dpkg/lock-frontend\e[0m. It is held by process 77 (apt)\r')"
    [[ "$_RETRY_CAUSE" == "lock" ]]
    [[ "$_RETRY_CULPRITS" == "77" ]]
    [[ "$_RETRY_EVIDENCE" != *$'\e'* ]]
}

@test "a name the package manager blamed is validated before it is kept" {
    retry_valid_name "libfoo-dev"
    retry_valid_name "app/org.x.Y/x86_64/stable"
    run ! retry_valid_name 'evil;rm -rf'
    run ! retry_valid_name '-dash-first'
    run ! retry_valid_name ''
    retry_diagnose system apt 100 "$(_captured a 'dpkg: error processing package $(touch pwned) (--configure):' "E: Sub-process /usr/bin/dpkg returned an error code (1)")"
    [[ "$_RETRY_CAUSE" == "package-script" ]]
    [[ -z "$_RETRY_CULPRITS" ]]
}

# --- The ledger ---

@test "a failed attempt makes a private row per name; another one counts it up and keeps the first date" {
    printf 'vim\nopenssl\n' | retry_ledger_bump system lock
    [[ "$(stat -c %a "$RETRY_LEDGER_FILE")" == "600" ]]
    [[ "$(grep -c . "$RETRY_LEDGER_FILE")" -eq 2 ]]
    local first
    first=$(awk -F'\t' '$2 == "vim" {print $4}' "$RETRY_LEDGER_FILE")
    printf 'vim\n' | retry_ledger_bump system dpkg-interrupted
    [[ "$(awk -F'\t' '$2 == "vim" {print $3, $4, $6}' "$RETRY_LEDGER_FILE")" == "2 $first dpkg-interrupted" ]]
    [[ "$(awk -F'\t' '$2 == "openssl" {print $3}' "$RETRY_LEDGER_FILE")" == "1" ]]
    read -r max since <<< "$(printf 'vim\nopenssl\n' | retry_ledger_max system)"
    [[ "$max" -eq 2 && "$since" == "$first" ]]
}

@test "an update that goes through is forgiven; one no longer pending is pruned; a list with nothing pending is left alone" {
    printf 'vim\nopenssl\n' | retry_ledger_bump system lock
    printf 'org.x.Y\n' | retry_ledger_bump flatpak network
    printf 'openssl\n' | retry_ledger_forgive system
    run ! grep -q 'openssl' "$RETRY_LEDGER_FILE"
    grep -q 'vim' "$RETRY_LEDGER_FILE"
    printf 'curl\n' | retry_ledger_prune system
    run ! grep -q 'vim' "$RETRY_LEDGER_FILE"
    grep -q 'org.x.Y' "$RETRY_LEDGER_FILE"
    printf '' | retry_ledger_prune flatpak
    grep -q 'org.x.Y' "$RETRY_LEDGER_FILE"
}

@test "rows that are not rows are ignored, and the ledger is never written through a symlink" {
    printf 'system\tvim\t3\t2026-10-23T09:00:00+08:00\t2026-10-25T19:00:00+08:00\tlock\nbogus line\nsystem\tevil;rm\t1\tx\ty\tz\nsystem\tok\tNaN\t2026-10-23\t2026-10-23\tlock\n' > "$RETRY_LEDGER_FILE"
    [[ "$(retry_ledger_rows | grep -c .)" -eq 1 ]]
    [[ "$(retry_ledger_rows | cut -f2)" == "vim" ]]
    rm -f "$RETRY_LEDGER_FILE"
    ln -s "$TMPDIR_TEST/elsewhere" "$RETRY_LEDGER_FILE"
    run ! bash -c 'printf "vim\n" | retry_ledger_bump system lock'
    [[ ! -e "$TMPDIR_TEST/elsewhere" ]]
}

@test "the most-failed rows come first" {
    printf 'a\n' | retry_ledger_bump system lock
    printf 'b\n' | retry_ledger_bump system lock
    printf 'b\n' | retry_ledger_bump system lock
    [[ "$(retry_ledger_rows | head -1 | cut -f2)" == "b" ]]
}

# --- The session's record ---

@test "a failure is recorded against the blamed name alone when there is one, against every selected name otherwise" {
    retry_record_failure system apt 100 "$(_captured a "dpkg: error processing package libfoo-dev (--configure):" "E: Sub-process /usr/bin/dpkg returned an error code (1)")" 1 vim openssl libfoo-dev
    [[ "$(retry_ledger_rows | grep -c .)" -eq 1 ]]
    [[ "$(retry_ledger_rows | cut -f2)" == "libfoo-dev" ]]
    [[ "${_RETRY_F_CAUSE[system]}" == "package-script" ]]
    [[ "${_RETRY_F_CULPRITS[system]}" == "libfoo-dev" ]]
    [[ "${_RETRY_F_COUNT[system]}" -eq 3 ]]
    [[ "${_RETRY_F_STREAK[system]}" -eq 1 ]]
    retry_record_failure flatpak apt 1 "$(_captured b "error: Unable to load summary from remote flathub: no")" 1 app/org.x.Y/x86_64/stable
    [[ "$(retry_ledger_rows | grep -c 'app/org.x.Y')" -eq 1 ]]
    [[ "${_RETRY_F_CULPRITS[flatpak]}" == "flathub" ]]
    [[ "$(retry_failed_lists)" == $'system\nflatpak' ]]
}

@test "a lock holder's pid and an interrupt are not updates: the pid is not counted, the interrupt counts nothing" {
    retry_record_failure system apt 100 "$(_captured a "E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 4321 (apt-get)")" 1 vim openssl
    [[ "$(retry_ledger_rows | cut -f2 | sort | tr '\n' ' ')" == "openssl vim " ]]
    [[ "${_RETRY_F_CULPRITS[system]}" == "4321" ]]
    retry_ledger_clear
    retry_record_failure system apt 130 "$(_captured b "^C")" 1 vim
    [[ ! -f "$RETRY_LEDGER_FILE" ]]
    [[ "${_RETRY_F_CAUSE[system]}" == "interrupted" ]]
}

@test "success forgives the names and drops the entry; the report is due once a name has failed RETRY_REPORT_AFTER times" {
    retry_record_failure system apt 100 "$(_captured a "E: Could not get lock x")" 1 vim
    run ! retry_report_due
    RETRY_REPORT_AFTER=1 retry_report_due
    retry_record_failure system apt 100 "$(_captured a "E: Could not get lock x")" 2 vim
    [[ "${_RETRY_F_STREAK[system]}" -eq 2 ]]
    retry_report_due
    retry_record_success system vim
    [[ -z "${_RETRY_F_CAUSE[system]:-}" ]]
    [[ -z "$(retry_ledger_rows)" ]]
    run ! retry_report_due
}

@test "apt: the downloads it could not fetch are named with their architecture; an index is not a download" {
    local esc=$'\033'
    retry_diagnose system apt 100 "$(_captured a \
        "${esc}[1;31mE: ${esc}[0mFailed to fetch https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn-gui/nordvpn-gui_6.0.1_amd64.deb  Certificate verification failed: The certificate is NOT trusted. The certificate issuer is unknown. The name in the certificate does not match the expected.  Could not handshake: Error in the certificate verification. [IP: 208.91.112.55 443]${esc}[0m" \
        "${esc}[1;31mE: ${esc}[0mFailed to fetch https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_6.0.1_amd64.deb  Certificate verification failed: The certificate is NOT trusted. The certificate issuer is unknown. The name in the certificate does not match the expected.  Could not handshake: Error in the certificate verification. [IP: 208.91.112.55 443]${esc}[0m" \
        "${esc}[1;31mE: ${esc}[0mUnable to fetch some archives, maybe run apt-get update or try with --fix-missing?${esc}[0m")"
    [[ "$_RETRY_CAUSE" == "repo-tls" ]]
    [[ "$_RETRY_CULPRITS" == "repo.nordvpn.com" ]]
    [[ "$_RETRY_UNFETCHED" == $'nordvpn-gui:amd64\nnordvpn:amd64' ]]
    retry_diagnose system apt 100 "$(_captured b \
        "W: Failed to fetch https://repo.example.org/dists/stable/InRelease  Could not resolve 'repo.example.org'" \
        "E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/v/vim/vim_2%3a9.1.0016-1ubuntu7.9_amd64.deb  404  Not Found [IP: 185.125.190.36 80]" \
        "E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/m/mesa/libgbm1_25.2.8-0ubuntu0.24.04.4_i386.deb  404  Not Found [IP: 185.125.190.36 80]" \
        "E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/f/fonts-x/fonts-x_1.0-1_all.deb  404  Not Found [IP: 185.125.190.36 80]")"
    [[ "$_RETRY_UNFETCHED" == $'vim:amd64\nlibgbm1:i386\nfonts-x:all' ]]
    # the other managers keep the plain diagnosis
    retry_diagnose system dnf 1 "$(_captured c "E: Failed to fetch http://x/pool/v/vim/vim_1_amd64.deb  404  Not Found")"
    [[ -z "$_RETRY_UNFETCHED" ]]
}

@test "a failure that names its downloads counts against those alone, matched to the selected targets" {
    local log
    log=$(_captured a \
        "E: Failed to fetch https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn-gui/nordvpn-gui_6.0.1_amd64.deb  Certificate verification failed: The certificate is NOT trusted." \
        "E: Failed to fetch https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_6.0.1_amd64.deb  Certificate verification failed: The certificate is NOT trusted." \
        "E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?")
    retry_record_failure system apt 100 "$log" 1 alsa-ucm-conf nordvpn nordvpn-gui openssl
    [[ "${_RETRY_F_CAUSE[system]}" == "repo-tls" ]]
    [[ "${_RETRY_F_UNFETCHED[system]}" == "nordvpn-gui nordvpn" ]]
    [[ "${_RETRY_F_CULPRITS[system]}" == "repo.nordvpn.com" ]]
    [[ "${_RETRY_F_COUNT[system]}" -eq 4 ]]
    [[ "$(retry_ledger_rows | cut -f2 | sort | tr '\n' ' ')" == "nordvpn nordvpn-gui " ]]
    # an architecture is matched exactly; arch:all and the native one are the plain name
    retry_ledger_clear
    log=$(_captured b \
        "E: Failed to fetch http://x/pool/main/m/mesa/libgbm1_25.2.8-0ubuntu0.24.04.4_i386.deb  404  Not Found" \
        "E: Failed to fetch http://x/pool/main/f/fonts-x/fonts-x_1.0-1_all.deb  404  Not Found" \
        "E: Failed to fetch http://x/pool/main/n/not-selected/not-selected_1_amd64.deb  404  Not Found")
    retry_record_failure system apt 100 "$log" 1 libgbm1 libgbm1:i386 fonts-x vim
    [[ "${_RETRY_F_UNFETCHED[system]}" == "libgbm1:i386 fonts-x" ]]
    [[ "$(retry_ledger_rows | cut -f2 | sort | tr '\n' ' ')" == "fonts-x libgbm1:i386 " ]]
    # the report says which downloads failed; success forgets them
    [[ "$(retry_report_text apt all 1)" == *"download: failed for libgbm1:i386, fonts-x"* ]]
    retry_record_success system libgbm1 libgbm1:i386 fonts-x vim
    [[ -z "${_RETRY_F_UNFETCHED[system]:-}" ]]
}

# --- The report ---

@test "the report names what failed, how often, the cause, the evidence, the steps and the log" {
    retry_record_failure system apt 100 "$(_captured a "E: dpkg was interrupted, you must manually run 'sudo dpkg --configure -a' to correct the problem.")" 2 vim openssl
    retry_record_failure system apt 100 "$TMPDIR_TEST/a.log" 2 vim openssl
    local text
    text=$(retry_report_text apt all 2)
    [[ "$text" == *"nudge · failure report"* ]]
    [[ "$text" == *"── System packages (apt) ──"* ]]
    [[ "$text" == *"exit 100 · 2 attempts this session"* ]]
    [[ "$text" == *"has failed 2 times"* ]]
    [[ "$text" == *"cause:    a previous package operation was cut short"* ]]
    [[ "$text" == *"| E: dpkg was interrupted"* ]]
    [[ "$text" == *"1. \$ sudo dpkg --configure -a"* ]]
    [[ "$text" == *"log:      "*"a.log"* ]]
    [[ "$text" == *"nudge does not run these commands for you"* ]]
    [[ "$text" != *"── Flatpak ──"* ]]
    [[ "$text" != *"named:"* ]]
}

@test "the report is saved privately in the reports directory, the newest is found, old ones are rotated" {
    retry_record_failure snap apt 1 "$(_captured a 'error: cannot refresh "firefox": snap "firefox" has running apps (firefox), pids: 1')" 1 firefox
    RETRY_REPORT_MAX=2
    local f1 f2 f3
    f1=$(retry_report_save apt all 1); sleep 1
    f2=$(retry_report_save apt all 1); sleep 1
    f3=$(retry_report_save apt all 1)
    [[ "$f3" == "$RETRY_REPORT_DIR"/failure-*.txt ]]
    [[ "$(stat -c %a "$f3")" == "600" ]]
    [[ ! -e "$f1" && -e "$f2" && -e "$f3" ]]
    [[ "$(retry_report_latest)" == "$f3" ]]
    grep -q 'firefox is still running' "$f3"
    grep -q '^this report: ' "$f3"
}

@test "only a report nudge wrote is trusted: not a symlink, not a world-readable one, not a file elsewhere" {
    retry_record_failure snap apt 1 "$(_captured a 'error: x')" 1 firefox
    local f
    f=$(retry_report_save apt all 1)
    retry_report_trusted "$f"
    chmod 644 "$f"
    run ! retry_report_trusted "$f"
    chmod 600 "$f"
    ln -s "$f" "$TMPDIR_TEST/link.txt"
    run ! retry_report_trusted "$TMPDIR_TEST/link.txt"
    cp "$f" "$TMPDIR_TEST/failure-elsewhere.txt"; chmod 600 "$TMPDIR_TEST/failure-elsewhere.txt"
    run ! retry_report_trusted "$TMPDIR_TEST/failure-elsewhere.txt"
    run ! retry_report_trusted ""
}

@test "a capture file is private and in the logs directory" {
    local f
    f=$(retry_log_path system 1)
    [[ "$f" == "$RETRY_LOG_DIR"/upgrade-*-system-1.*.log ]]
    [[ -f "$f" && "$(stat -c %a "$f")" == "600" ]]
}

# --- nudge --failures ---

@test "the failures view: nothing, a table with the latest report, JSON, and clear" {
    run retry_failures_show table
    [[ "$output" == "Nothing is failing"* ]]
    run retry_failures_show json
    [[ "$output" == '{"failing":[],"latest_report":null}' ]]
    printf 'system\tvim\t3\t2026-10-23T09:00:00+08:00\t2026-10-25T19:00:00+08:00\tdpkg-interrupted\n' > "$RETRY_LEDGER_FILE"
    retry_record_failure system apt 100 "$(_captured a "E: dpkg was interrupted")" 1 vim
    local f
    f=$(retry_report_save apt all 1)
    run retry_failures_show table
    [[ "$output" == *"system    vim"*"4"*"2026-10-23 09:00"*"dpkg-interrupted"* ]]
    [[ "$output" == *"nudge · failure report"* ]]
    run retry_failures_show json
    [[ "$output" == *'"target":"vim","attempts":4'* ]]
    [[ "$output" == *"\"latest_report\":\"$f\""* ]]
    run retry_failures_clear
    [[ "$output" == "Forgot 1 failing update(s)"* ]]
    [[ ! -f "$RETRY_LEDGER_FILE" && ! -e "$f" ]]
}

# --- What to do ---

@test "every cause has a headline, an explanation and at least one step, for every manager" {
    local cause mgr list
    for cause in interrupted declined repo-tls config snapd-down sudo-denied sudo-password sudo-no-tty lock dpkg-interrupted disk-full repo-key index-corrupt mirror-stale repo-unreachable network package-script deps-broken file-conflict snap-running snap-busy snap-held snap-denied snap-app flatpak-old flatpak-auth flatpak-app unknown; do
        for mgr in apt dnf pacman zypper; do
            for list in system flatpak snap; do
                [[ -n "$(retry_cause_headline "$cause" "$mgr" "$list")" ]]
                [[ -n "$(retry_cause_explain "$cause" "$mgr" "$list")" ]]
                [[ -n "$(retry_cause_remedy "$cause" "$mgr" "$list")" ]]
            done
        done
    done
}
