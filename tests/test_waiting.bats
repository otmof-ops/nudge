#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# Tests for lib/waiting.sh: the waiting list

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)
    MOCK_BIN="$TMPDIR_TEST/bin"
    mkdir -p "$MOCK_BIN"
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { echo "WARN: $*" >&2; }
    log_error() { :; }
    export NUDGE_STATE_DIR="$TMPDIR_TEST/state"
    mkdir -p "$NUDGE_STATE_DIR"
    source "$PROJECT_DIR/lib/output.sh"
    source "$PROJECT_DIR/lib/pkgmgr.sh"
    source "$PROJECT_DIR/lib/retry.sh"
    source "$PROJECT_DIR/lib/waiting.sh"
    DETECTED_PKGMGR="apt"
    _PKG_NATIVE_ARCH="amd64"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

_note() {
    # Usage: _note <cause> <target|severity|version|host>...
    local cause="$1"
    shift
    printf '%s\n' "$@" | waiting_note system "$cause"
}

@test "the list lives in the state directory, private, and starts empty" {
    [[ "$WAITING_FILE" == "$NUDGE_STATE_DIR/waiting.tsv" ]]
    run waiting_any
    [[ "$status" -ne 0 ]]
    _note repo-tls "nordvpn|standard|6.0.1|repo.nordvpn.com"
    waiting_any
    [[ "$(stat -c %a "$WAITING_FILE")" == "600" ]]
}

@test "a note adds a row; the next note of the same update is another try on it" {
    _note repo-tls "nordvpn|standard|6.0.1|repo.nordvpn.com" "libssl3|security||"
    [[ "$(waiting_rows | cut -f2,3,4,5,6,9)" == $'libssl3\tsecurity\t-\trepo-tls\t-\t1\nnordvpn\tstandard\t6.0.1\trepo-tls\trepo.nordvpn.com\t1' ]]
    local first
    first=$(waiting_rows | awk -F'\t' '$2=="nordvpn"{print $7}')
    _note network "nordvpn|standard|6.0.2|"
    [[ "$(waiting_rows | awk -F'\t' '$2=="nordvpn"{print $4, $5, $6, $9}')" == "6.0.2 network repo.nordvpn.com 2" ]]
    [[ "$(waiting_rows | awk -F'\t' '$2=="nordvpn"{print $7}')" == "$first" ]]
}

@test "rows come critical first, then security, then standard" {
    _note repo-tls "zz-std|standard||" "aa-std|standard||" "mm-sec|security||" "qq-crit|critical||"
    [[ "$(waiting_rows | cut -f2 | tr '\n' ' ')" == "qq-crit mm-sec aa-std zz-std " ]]
}

@test "what nudge would not keep never reaches the list" {
    _note 'Bad Cause' "good|weird||" "bad;name|standard||" "ok2|standard|1.0 rm -rf|evil host"
    [[ "$(waiting_rows | cut -f2,3,4,5,6 | LC_ALL=C sort)" == $'good\tstandard\t-\tunknown\t-\nok2\tstandard\t-\tunknown\t-' ]]
    # a row planted in the file by hand is read only when it passes every rule
    printf 'system\tx;y\tstandard\t-\trepo-tls\t-\t2026-01-01T00:00:00+00:00\t2026-01-01T00:00:00+00:00\t1\n' >> "$WAITING_FILE"
    printf 'system\tz\tstandard\t-\trepo-tls\t-\t2026-01-01T00:00:00+00:00\t2026-01-01T00:00:00+00:00\t0\n' >> "$WAITING_FILE"
    [[ "$(waiting_rows | wc -l)" -eq 2 ]]
}

@test "the list is never written through a symlink" {
    ln -s "$TMPDIR_TEST/elsewhere" "$WAITING_FILE"
    run _note repo-tls "nordvpn|standard||"
    [[ "$status" -ne 0 ]]
    [[ -L "$WAITING_FILE" ]]
    [[ ! -e "$TMPDIR_TEST/elsewhere" ]]
}

@test "forget takes the rows that went in; keep_pending drops what is no longer pending" {
    _note repo-tls "a|standard||" "b|standard||" "c|security||"
    printf 'a\n' | waiting_forget system
    [[ "$(waiting_rows | cut -f2 | tr '\n' ' ')" == "c b " ]]
    printf 'c\n' | waiting_keep_pending system
    [[ "$(waiting_rows | cut -f2)" == "c" ]]
    # another list is left alone
    printf 'snapx|standard||\n' | waiting_note snap repo-tls
    waiting_keep_pending system < /dev/null
    [[ "$(waiting_rows | cut -f1,2)" == $'snap\tsnapx' ]]
    printf 'snapx\n' | waiting_forget snap
    [[ ! -e "$WAITING_FILE" ]]
}

@test "the check holds back a standard update whose download still does not answer" {
    _note repo-tls "nordvpn|standard|6.0.1|repo.nordvpn.com" "openssl|security||"
    PKG_UPDATE_LIST=$'nordvpn|5.4.0|6.0.1|STANDARD|amd64|0\nvim|1|2|STANDARD|amd64|0\nopenssl|3.0.1|3.0.2|SECURITY|amd64|1'
    PKG_UPDATES_TOTAL=3
    waiting_probe() { echo "probed $1" >> "$TMPDIR_TEST/probes"; return 1; }
    waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 1 ]]
    [[ "$PKG_UPDATES_TOTAL" -eq 2 ]]
    [[ "$PKG_WAITING_LIST" == "nordvpn|5.4.0|6.0.1|STANDARD|amd64|0" ]]
    [[ "$PKG_UPDATE_LIST" == $'vim|1|2|STANDARD|amd64|0\nopenssl|3.0.1|3.0.2|SECURITY|amd64|1' ]]
    [[ "$(waiting_held_targets)" == "nordvpn" ]]
    # the security update is never probed, never held back
    [[ "$(cat "$TMPDIR_TEST/probes")" == "probed nordvpn" ]]
}

@test "the check offers a waiting update again once its download answers" {
    _note repo-tls "nordvpn|standard||"
    PKG_UPDATE_LIST="nordvpn|5.4.0|6.0.1|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    waiting_probe() { return 0; }
    waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 0 && "$PKG_UPDATES_TOTAL" -eq 1 ]]
    [[ -z "$PKG_WAITING_LIST" ]]
    # it stays on the list until it goes in
    [[ "$(waiting_rows | cut -f2)" == "nordvpn" ]]
}

@test "an update nudge cannot probe stays held back, and rides along again after a week" {
    _note repo-tls "nordvpn|standard||"
    PKG_UPDATE_LIST="nordvpn|5.4.0|6.0.1|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    waiting_probe() { return 2; }
    waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 1 ]]
    # last tried nine days ago
    local old
    old=$(date -d '9 days ago' -Iseconds)
    sed -i "s|\t[0-9T:+-]*\t1\$|\t${old}\t1|" "$WAITING_FILE"
    PKG_UPDATE_LIST="nordvpn|5.4.0|6.0.1|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 0 && "$PKG_UPDATES_TOTAL" -eq 1 ]]
}

@test "what the update is now decides: a standard one that became critical is offered" {
    _note repo-tls "linux-image-generic|standard||"
    PKG_UPDATE_LIST="linux-image-generic|1|2|CRITICAL|amd64|0"
    PKG_UPDATES_TOTAL=1
    waiting_probe() { return 1; }
    waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 0 ]]
}

@test "SET_ASIDE_STANDARD=false holds nothing back" {
    _note repo-tls "nordvpn|standard||"
    PKG_UPDATE_LIST="nordvpn|5.4.0|6.0.1|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    SET_ASIDE_STANDARD=false
    waiting_probe() { return 1; }
    waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 0 && -z "$PKG_WAITING_LIST" ]]
}

@test "a foreign architecture is held back by its own name" {
    _note repo-tls "libgbm1:i386|standard||"
    PKG_UPDATE_LIST=$'libgbm1|1|2|STANDARD|i386|0\nlibgbm1|1|2|STANDARD|amd64|0'
    PKG_UPDATES_TOTAL=2
    waiting_probe() { return 1; }
    waiting_hold_back
    [[ "$(waiting_held_targets)" == "libgbm1:i386" ]]
    [[ "$PKG_UPDATE_LIST" == "libgbm1|1|2|STANDARD|amd64|0" ]]
}

@test "with nothing pending, what waited went in some other way" {
    _note repo-tls "nordvpn|standard||"
    PKG_UPDATE_LIST=""
    PKG_UPDATES_TOTAL=0
    waiting_hold_back
    [[ ! -e "$WAITING_FILE" ]]
}

@test "the probe asks apt for the download's address and fetches one byte of it" {
    cat > "$MOCK_BIN/apt-get" <<'EOT'
#!/bin/bash
[[ "$1 $2 $3" == "download --print-uris --" ]] || exit 9
case "$4" in
    good) echo "'https://repo.example.org/pool/g/good_1.0_amd64.deb' good_1.0_amd64.deb 10 SHA256:00" ;;
    evil) echo "'https://repo.example.org/pool/\$(touch /tmp/x)_1.0.deb' evil.deb 10 SHA256:00" ;;
esac
exit 0
EOT
    cat > "$MOCK_BIN/curl" <<'EOT'
#!/bin/bash
printf '%s\n' "$@" > "$CURL_ARGS"
printf '%s' "$CODE"
EOT
    printf '#!/bin/bash\nexit 0\n' > "$MOCK_BIN/apt-config"
    chmod +x "$MOCK_BIN/"*
    PATH="$MOCK_BIN:$PATH"
    export CURL_ARGS="$TMPDIR_TEST/curl.args"
    [[ "$(_waiting_uri good)" == "https://repo.example.org/pool/g/good_1.0_amd64.deb" ]]
    run _waiting_uri evil
    [[ "$status" -ne 0 ]]
    CODE=206 waiting_probe good
    grep -qx -- '-r' "$CURL_ARGS"
    grep -qx -- '0-0' "$CURL_ARGS"
    grep -qx -- '--proto' "$CURL_ARGS"
    grep -qx -- '=http,https' "$CURL_ARGS"
    [[ "$(tail -1 "$CURL_ARGS")" == "https://repo.example.org/pool/g/good_1.0_amd64.deb" ]]
    CODE=000 run waiting_probe good
    [[ "$status" -eq 1 ]]
    CODE=404 run waiting_probe good
    [[ "$status" -eq 1 ]]
    run waiting_probe evil
    [[ "$status" -eq 2 ]]
    DETECTED_PKGMGR=dnf run waiting_probe good
    [[ "$status" -eq 2 ]]
}

@test "with a proxy only apt knows, nudge cannot tell" {
    printf '#!/bin/bash\necho %s\n' "'Acquire::http::Proxy \"http://proxy.lan:3128\";'" > "$MOCK_BIN/apt-config"
    chmod +x "$MOCK_BIN/apt-config"
    PATH="$MOCK_BIN:$PATH"
    _waiting_apt_proxied
    run waiting_probe anything
    [[ "$status" -eq 2 ]]
    printf '#!/bin/bash\necho %s\n' "'Acquire::http::Proxy \"DIRECT\";'" > "$MOCK_BIN/apt-config"
    run _waiting_apt_proxied
    [[ "$status" -ne 0 ]]
}

@test "nudge --waiting lists by severity and says what each tier does" {
    _note repo-tls "nordvpn|standard|6.0.1|repo.nordvpn.com"
    _note network "openssl|security||"
    run waiting_show table
    [[ "${lines[0]}" == "Security · important: offered and retried every run (nudge --failures)" ]]
    [[ "${lines[1]}" == *"openssl"*"its source could not be reached · since "* ]]
    [[ "${lines[2]}" == "Standard · waiting quietly: offered again once the download answers" ]]
    [[ "${lines[3]}" == *"nordvpn"*"6.0.1"*"repo.nordvpn.com: certificate does not verify from here"* ]]
    run waiting_show json
    [[ "$output" == '{"waiting":[{"list":"system","target":"openssl","severity":"security","version":"","cause":"network","host":""'* ]]
    [[ "$output" == *'"tries":1,"policy":"retried"}'* ]]
    [[ "$output" == *'"target":"nordvpn","severity":"standard","version":"6.0.1"'*'"policy":"waits"}]}' ]]
    if command -v jq >/dev/null; then
        echo "$output" | jq -e '.waiting | length == 2' >/dev/null
    fi
    run waiting_clear
    [[ "$output" == "Forgot 2 waiting update(s). nudge will offer them again." ]]
    run waiting_show table
    [[ "$output" == "Nothing is waiting: every update nudge offered could be downloaded." ]]
}

@test "the diagnosis knows where each download was to come from" {
    _RETRY_TEXT=$'E: Failed to fetch https://user:pw@repo.nordvpn.com:443/deb/pool/main/n/nordvpn/nordvpn_6.0.1_amd64.deb  Certificate verification failed\nE: Failed to fetch http://mirror.example/pool/libgbm1_24.0_i386.deb  404'
    _RETRY_UNFETCHED_HOST=()
    _retry_unfetched_hosts_apt
    [[ "$(retry_unfetched_host nordvpn)" == "repo.nordvpn.com" ]]
    [[ "$(retry_unfetched_host libgbm1:i386)" == "mirror.example" ]]
    [[ -z "$(retry_unfetched_host nothing)" ]]
}

@test "setting aside takes the names off the ledger, and says when nothing else explains the failure" {
    printf 'nordvpn\nopenssl\n' | retry_ledger_bump system repo-tls
    _RETRY_F_CAUSE["system"]="repo-tls"
    _RETRY_F_UNFETCHED["system"]="nordvpn openssl"
    run retry_set_aside system nordvpn
    retry_set_aside system nordvpn || true
    [[ "${_RETRY_F_UNFETCHED[system]}" == "openssl" ]]
    [[ "$(retry_ledger_rows | cut -f2)" == "openssl" ]]
    [[ "${_RETRY_F_STREAK[system]}" == "1" ]]
    retry_set_aside system openssl
    [[ -z "${_RETRY_F_CAUSE[system]:-}" ]]
    [[ -z "$(retry_failed_lists)" ]]
}
