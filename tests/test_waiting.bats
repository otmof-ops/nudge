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
    log_warn()  { :; }
    log_error() { :; }
    export NUDGE_STATE_DIR="$TMPDIR_TEST/state"
    mkdir -p "$NUDGE_STATE_DIR"
    source "$PROJECT_DIR/lib/output.sh"
    source "$PROJECT_DIR/lib/pkgmgr.sh"
    source "$PROJECT_DIR/lib/retry.sh"
    source "$PROJECT_DIR/lib/waiting.sh"
    DETECTED_PKGMGR="apt"
    _PKG_NATIVE_ARCH="amd64"
    PKG_COUNT_SOURCE="list"
    PKG_UPDATES_FLATPAK=0
    PKG_UPDATES_SNAP=0
    # apt and the network are stood in for: no test reaches either
    _waiting_apt_unprobeable() { return 1; }
    _waiting_uris() {
        local n
        for n in "$@"; do
            printf '%s:amd64\thttps://%s/pool/%s_1.0_amd64.deb\t1000\n' "${n%%:*}" "${HOST_OF_DOWNLOAD:-repo.example.org}" "${n%%:*}"
        done
    }
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

_note() {
    # Usage: _note <cause> <target|severity|version|host|via>...
    local cause="$1"
    shift
    printf '%s\n' "$@" | waiting_note system "$cause"
}

# A probe that answers from FETCH (0 answers, 1 does not, 2 cannot tell) and writes down what it was asked
_fetch_says() {
    _waiting_fetch() {
        echo "$1" >> "$TMPDIR_TEST/probes"
        _WAITING_LAST_CODE="${FETCH_CODE:-000}"
        return "${FETCH:-1}"
    }
}

_probes() { cat "$TMPDIR_TEST/probes" 2>/dev/null || true; }

_age_rows() {
    # every row last tried this many days ago
    local old
    old=$(date -d "$1 days ago" -Iseconds)
    awk -F'\t' -v OFS='\t' -v t="$old" '{ $8 = t; print }' "$WAITING_FILE" > "$WAITING_FILE.new"
    mv "$WAITING_FILE.new" "$WAITING_FILE"
}

@test "the list lives in the state directory, private, and starts empty" {
    [[ "$WAITING_FILE" == "$NUDGE_STATE_DIR/waiting.tsv" ]]
    run waiting_any
    [[ "$status" -ne 0 ]]
    _note repo-tls "nordvpn|standard|6.0.1|repo.nordvpn.com|"
    waiting_any
    [[ "$(stat -c %a "$WAITING_FILE")" == "600" ]]
}

@test "a note adds a row; the next note of the same update is another try on it" {
    _note repo-tls "nordvpn|standard|6.0.1|repo.nordvpn.com|" "libssl3|security|||"
    [[ "$(waiting_rows | cut -f2,3,4,5,6,9,10)" == $'libssl3\tsecurity\t-\trepo-tls\t-\t1\t-\nnordvpn\tstandard\t6.0.1\trepo-tls\trepo.nordvpn.com\t1\t-' ]]
    local first
    first=$(waiting_rows | awk -F'\t' '$2=="nordvpn"{print $7}')
    _note network "nordvpn|standard|6.0.2||libnord:amd64"
    [[ "$(waiting_rows | awk -F'\t' '$2=="nordvpn"{print $4, $5, $6, $9, $10}')" == "6.0.2 network repo.nordvpn.com 2 libnord:amd64" ]]
    [[ "$(waiting_rows | awk -F'\t' '$2=="nordvpn"{print $7}')" == "$first" ]]
}

@test "rows come critical first, then security, then standard" {
    _note repo-tls "zz-std|standard|||" "aa-std|standard|||" "mm-sec|security|||" "qq-crit|critical|||"
    [[ "$(waiting_rows | cut -f2 | tr '\n' ' ')" == "qq-crit mm-sec aa-std zz-std " ]]
}

@test "what nudge would not keep never reaches the list" {
    _note 'Bad Cause' "good|weird|||" "bad;name|standard|||" "ok2|standard|1.0 rm -rf|evil host|x;y"
    [[ "$(waiting_rows | cut -f2,3,4,5,6,10 | LC_ALL=C sort)" == $'good\tstandard\t-\tunknown\t-\t-\nok2\tstandard\t-\tunknown\t-\t-' ]]
    # a row planted in the file by hand is read only when it passes every rule
    printf 'system\tx;y\tstandard\t-\trepo-tls\t-\t2026-01-01T00:00:00+00:00\t2026-01-01T00:00:00+00:00\t1\t-\n' >> "$WAITING_FILE"
    printf 'system\tz\tstandard\t-\trepo-tls\t-\t2026-01-01T00:00:00+00:00\t2026-01-01T00:00:00+00:00\t0\t-\n' >> "$WAITING_FILE"
    printf 'system\tw\tstandard\t-\trepo-tls\t-\t2026-01-01T00:00:00+00:00\t2026-01-01T00:00:00+00:00\t1\n' >> "$WAITING_FILE"
    [[ "$(waiting_rows | wc -l)" -eq 2 ]]
}

@test "the list is never written through a symlink" {
    ln -s "$TMPDIR_TEST/elsewhere" "$WAITING_FILE"
    run _note repo-tls "nordvpn|standard|||"
    [[ "$status" -ne 0 ]]
    [[ -L "$WAITING_FILE" ]]
    [[ ! -e "$TMPDIR_TEST/elsewhere" ]]
}

@test "forget takes the rows that went in; keep_pending drops what is no longer pending" {
    _note repo-tls "a|standard|||" "b|standard|||" "c|security|||"
    printf 'a\n' | waiting_forget system
    [[ "$(waiting_rows | cut -f2 | tr '\n' ' ')" == "c b " ]]
    printf 'c\n' | waiting_keep_pending system
    [[ "$(waiting_rows | cut -f2)" == "c" ]]
    # another list is left alone
    printf 'snapx|standard|||\n' | waiting_note snap repo-tls
    waiting_keep_pending system < /dev/null
    [[ "$(waiting_rows | cut -f1,2)" == $'snap\tsnapx' ]]
    printf 'snapx\n' | waiting_forget snap
    [[ ! -e "$WAITING_FILE" ]]
}

@test "the check holds back a standard update whose download still does not answer" {
    _note repo-tls "nordvpn|standard|6.0.1|repo.nordvpn.com|" "openssl|security|||"
    PKG_UPDATE_LIST=$'nordvpn|5.4.0|6.0.1|STANDARD|amd64|0\nvim|1|2|STANDARD|amd64|0\nopenssl|3.0.1|3.0.2|SECURITY|amd64|1'
    PKG_UPDATES_TOTAL=3
    _fetch_says
    FETCH=1 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 1 ]]
    [[ "$PKG_UPDATES_TOTAL" -eq 2 ]]
    [[ "$PKG_WAITING_LIST" == "nordvpn|5.4.0|6.0.1|STANDARD|amd64|0" ]]
    [[ "$PKG_UPDATE_LIST" == $'vim|1|2|STANDARD|amd64|0\nopenssl|3.0.1|3.0.2|SECURITY|amd64|1' ]]
    [[ "$(waiting_held_targets)" == "nordvpn" ]]
    # the security update is never probed, never held back
    [[ "$(_probes)" == "https://repo.example.org/pool/nordvpn_1.0_amd64.deb" ]]
}

@test "the check offers a waiting update again once its download answers" {
    _note repo-tls "nordvpn|standard|||"
    PKG_UPDATE_LIST="nordvpn|5.4.0|6.0.1|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    _fetch_says
    FETCH=0 FETCH_CODE=206 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 0 && "$PKG_UPDATES_TOTAL" -eq 1 ]]
    [[ -z "$PKG_WAITING_LIST" ]]
    # it stays on the list until it goes in
    [[ "$(waiting_rows | cut -f2)" == "nordvpn" ]]
}

@test "an update held back by a new dependency is probed by that dependency's download" {
    _note repo-tls "nordvpn-gui|standard|6.0.1|repo.nordvpn.com|libnord:amd64"
    PKG_UPDATE_LIST="nordvpn-gui|5.4.0|6.0.1|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    _fetch_says
    FETCH=1 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 1 ]]
    [[ "$(_probes)" == "https://repo.example.org/pool/libnord_1.0_amd64.deb" ]]
}

@test "one download that gets no answer at all is enough for its host" {
    _note repo-tls "a|standard|||" "b|standard|||" "c|standard|||"
    PKG_UPDATE_LIST=$'a|1|2|STANDARD|amd64|0\nb|1|2|STANDARD|amd64|0\nc|1|2|STANDARD|amd64|0'
    PKG_UPDATES_TOTAL=3
    _fetch_says
    FETCH=1 FETCH_CODE=000 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 3 ]]
    [[ "$(_probes | wc -l)" -eq 1 ]]
    # a 404 says nothing about the host: each file is asked about
    rm -f "$TMPDIR_TEST/probes"
    PKG_UPDATE_LIST=$'a|1|2|STANDARD|amd64|0\nb|1|2|STANDARD|amd64|0\nc|1|2|STANDARD|amd64|0'
    FETCH=1 FETCH_CODE=404 waiting_hold_back
    [[ "$(_probes | wc -l)" -eq 3 ]]
}

@test "past the probe budget nudge cannot tell, and holds back until a week has passed" {
    _note repo-tls "a|standard|||" "b|standard|||"
    PKG_UPDATE_LIST=$'a|1|2|STANDARD|amd64|0\nb|1|2|STANDARD|amd64|0'
    PKG_UPDATES_TOTAL=2
    _fetch_says
    WAITING_PROBE_BUDGET=0
    FETCH=0 waiting_hold_back
    [[ -z "$(_probes)" ]]
    [[ "$PKG_UPDATES_WAITING" -eq 2 ]]
}

@test "an update nudge cannot probe rides along again after a week, even by itself" {
    _note repo-tls "nordvpn|standard|||"
    PKG_UPDATE_LIST="nordvpn|5.4.0|6.0.1|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    _fetch_says
    FETCH=2 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 1 ]]
    _age_rows 9
    PKG_UPDATE_LIST="nordvpn|5.4.0|6.0.1|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    FETCH=2 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 0 && "$PKG_UPDATES_TOTAL" -eq 1 ]]
}

@test "a week on, an update whose probe says no rides along only when something else is offered" {
    _note repo-tls "nordvpn|standard|||"
    _age_rows 9
    _fetch_says
    # by itself it would make a prompt that installs nothing: it stays held back
    PKG_UPDATE_LIST="nordvpn|5.4.0|6.0.1|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    FETCH=1 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 1 && "$PKG_UPDATES_TOTAL" -eq 0 ]]
    # with company, apt gets to try it again
    PKG_UPDATE_LIST=$'nordvpn|5.4.0|6.0.1|STANDARD|amd64|0\nvim|1|2|STANDARD|amd64|0'
    PKG_UPDATES_TOTAL=2
    FETCH=1 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 0 && "$PKG_UPDATES_TOTAL" -eq 2 ]]
    # a snap counts as company too
    PKG_UPDATE_LIST="nordvpn|5.4.0|6.0.1|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    PKG_UPDATES_SNAP=1
    FETCH=1 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 0 ]]
}

@test "what is held back comes off the count, and what the upgrade leaves for later keeps its row" {
    _note repo-tls "nordvpn|standard|||" "sqlite3|standard|||"
    _fetch_says
    # sqlite3 is being phased in: not offered, not probed, but still pending
    PKG_UPDATE_LIST=$'nordvpn|1|2|STANDARD|amd64|0\nlinux-firmware|1|2|STANDARD|all|0'
    PKG_LATER_LIST="sqlite3|phased"
    PKG_UPDATES_TOTAL=2
    FETCH=1 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 1 && "$PKG_UPDATES_TOTAL" -eq 1 ]]
    [[ "$PKG_UPDATE_LIST" == "linux-firmware|1|2|STANDARD|all|0" ]]
    [[ "$(_probes)" == "https://repo.example.org/pool/nordvpn_1.0_amd64.deb" ]]
    [[ "$(waiting_rows | cut -f2 | LC_ALL=C sort | tr '\n' ' ')" == "nordvpn sqlite3 " ]]
}

@test "a snap that waited goes once it is no longer pending" {
    printf 'firefox|standard|159.0.1||\n' | waiting_note snap snap-running
    PKG_UPDATE_LIST="vim|1|2|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    PKG_SNAP_LIST="firefox|159.0.1|9171|299MB|mozilla"
    waiting_hold_back
    [[ "$(waiting_rows | cut -f1,2)" == $'snap\tfirefox' ]]
    PKG_SNAP_LIST=""
    waiting_hold_back
    [[ -z "$(waiting_rows)" ]]
}

@test "what the update is now decides: a standard one that became critical is offered" {
    _note repo-tls "linux-image-generic|standard|||"
    PKG_UPDATE_LIST="linux-image-generic|1|2|CRITICAL|amd64|0"
    PKG_UPDATES_TOTAL=1
    _fetch_says
    FETCH=1 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 0 && -z "$(_probes)" ]]
}

@test "SET_ASIDE_STANDARD=false holds nothing back" {
    _note repo-tls "nordvpn|standard|||"
    PKG_UPDATE_LIST="nordvpn|5.4.0|6.0.1|STANDARD|amd64|0"
    PKG_UPDATES_TOTAL=1
    SET_ASIDE_STANDARD=false
    _fetch_says
    FETCH=1 waiting_hold_back
    [[ "$PKG_UPDATES_WAITING" -eq 0 && -z "$PKG_WAITING_LIST" ]]
}

@test "a foreign architecture is held back by its own name" {
    _note repo-tls "libgbm1:i386|standard|||"
    PKG_UPDATE_LIST=$'libgbm1|1|2|STANDARD|i386|0\nlibgbm1|1|2|STANDARD|amd64|0'
    PKG_UPDATES_TOTAL=2
    _waiting_uris() { printf 'libgbm1:i386\thttps://repo.example.org/pool/libgbm1_1_i386.deb\t10\n'; }
    _fetch_says
    FETCH=1 waiting_hold_back
    [[ "$(waiting_held_targets)" == "libgbm1:i386" ]]
    [[ "$PKG_UPDATE_LIST" == "libgbm1|1|2|STANDARD|amd64|0" ]]
    [[ "$(_probes)" == "https://repo.example.org/pool/libgbm1_1_i386.deb" ]]
}

@test "with nothing pending in the list that was read, what waited went in some other way" {
    _note repo-tls "nordvpn|standard|||"
    PKG_UPDATE_LIST=""
    PKG_UPDATES_TOTAL=0
    waiting_hold_back
    [[ ! -e "$WAITING_FILE" ]]
}

@test "apt says where each download comes from, in one call, and what it does not know is left out" {
    unset -f _waiting_uris
    source "$PROJECT_DIR/lib/waiting.sh"
    cat > "$MOCK_BIN/apt-get" <<'EOT'
#!/bin/bash
[[ "$1 $2 $3" == "download --print-uris --" ]] || exit 9
echo "call" >> "$CALLS"
for n in "${@:4}"; do
    case "$n" in
        good)  echo "'https://repo.example.org/pool/g/good_1.0_amd64.deb' good_1.0_amd64.deb 144010 SHA256:00" ;;
        lib32) echo "'http://mirror.example:8080/pool/l/lib32_2%3a1.0_i386.deb' lib32_2%3a1.0_i386.deb 10 SHA256:00" ;;
        evil)  echo "'https://repo.example.org/pool/\$(touch /tmp/x)_1.0.deb' evil.deb 10 SHA256:00" ;;
        *)     echo "E: Unable to locate package $n" >&2 ;;
    esac
done
exit 100
EOT
    chmod +x "$MOCK_BIN/apt-get"
    PATH="$MOCK_BIN:$PATH"
    export CALLS="$TMPDIR_TEST/calls"
    run _waiting_uris good lib32 evil gone
    [[ "$output" == $'good:amd64\thttps://repo.example.org/pool/g/good_1.0_amd64.deb\t144010\nlib32:i386\thttp://mirror.example:8080/pool/l/lib32_2%3a1.0_i386.deb\t10' ]]
    [[ "$(wc -l < "$CALLS")" -eq 1 ]]
}

@test "the probe fetches one byte the way apt would, and only the real file answers" {
    source "$PROJECT_DIR/lib/waiting.sh"
    cat > "$MOCK_BIN/curl" <<'EOT'
#!/bin/bash
printf '%s\n' "$@" > "$CURL_ARGS"
case "$REPLY_KIND" in
    range)   printf 'HTTP/1.1 302 Found\r\nLocation: x\r\n\r\nHTTP/1.1 206 Partial Content\r\nContent-Range: bytes 0-0/144010\r\nContent-Length: 1\r\n\r\n' ;;
    whole)   printf 'HTTP/1.1 200 OK\r\nContent-Length: 144010\r\n\r\n' ;;
    portal)  printf 'HTTP/1.1 200 OK\r\nContent-Length: 2317\r\nContent-Type: text/html\r\n\r\n' ;;
    auth)    printf 'HTTP/1.1 401 Unauthorized\r\n\r\n' ;;
    missing) printf 'HTTP/1.1 404 Not Found\r\n\r\n' ;;
    none)    ;;
esac
code="${REPLY_CODE:-000}"
printf '\nnudge-code=%s\n' "$code"
EOT
    chmod +x "$MOCK_BIN/curl"
    PATH="$MOCK_BIN:$PATH"
    export CURL_ARGS="$TMPDIR_TEST/curl.args"
    local url="https://repo.example.org/pool/g/good_1.0_amd64.deb"
    REPLY_KIND=range REPLY_CODE=206 _waiting_fetch "$url" 144010
    grep -qx -- '-r' "$CURL_ARGS"
    grep -qx -- '0-0' "$CURL_ARGS"
    grep -qx -- '--proto' "$CURL_ARGS"
    grep -qx -- '--proto-redir' "$CURL_ARGS"
    [[ "$(grep -c -x -- '=http,https' "$CURL_ARGS")" -eq 2 ]]
    [[ "$(tail -1 "$CURL_ARGS")" == "$url" ]]
    [[ "$(tail -2 "$CURL_ARGS" | head -1)" == "--" ]]
    REPLY_KIND=whole REPLY_CODE=200 _waiting_fetch "$url" 144010
    REPLY_KIND=portal REPLY_CODE=200 run _waiting_fetch "$url" 144010
    [[ "$status" -eq 1 ]]
    REPLY_KIND=auth REPLY_CODE=401 run _waiting_fetch "$url" 144010
    [[ "$status" -eq 2 ]]
    REPLY_KIND=missing REPLY_CODE=404 run _waiting_fetch "$url" 144010
    [[ "$status" -eq 1 ]]
    REPLY_KIND=none REPLY_CODE=000 _waiting_fetch "$url" 144010 || true
    [[ "$_WAITING_LAST_CODE" == "000" ]]
    # no answer at all gets one more go; a real answer does not
    printf '#!/bin/bash\necho call >> "$CURL_CALLS"\nprintf "\\nnudge-code=%%s\\n" "$REPLY_CODE"\n' > "$MOCK_BIN/curl"
    export CURL_CALLS="$TMPDIR_TEST/curl.calls"
    REPLY_CODE=000 run _waiting_fetch "$url" 144010
    [[ "$status" -eq 1 && "$(wc -l < "$CURL_CALLS")" -eq 2 ]]
    : > "$CURL_CALLS"
    REPLY_CODE=404 run _waiting_fetch "$url" 144010
    [[ "$status" -eq 1 && "$(wc -l < "$CURL_CALLS")" -eq 1 ]]
}

@test "with a proxy, a certificate store of its own or no peer check, apt fetches in a way nudge cannot follow" {
    source "$PROJECT_DIR/lib/waiting.sh"
    PATH="$MOCK_BIN:$PATH"
    local line
    for line in 'Acquire::http::Proxy "http://proxy.lan:3128";' \
                'Acquire::https::Proxy::repo.example.org "http://p:1";' \
                'Acquire::http::Proxy-Auto-Detect "/usr/bin/auto-apt-proxy";' \
                'Acquire::https::CaInfo "/etc/ssl/corp.pem";' \
                'Acquire::https::repo.example.org::Verify-Peer "false";'; do
        printf '#!/bin/bash\necho %q\n' "$line" > "$MOCK_BIN/apt-config"
        chmod +x "$MOCK_BIN/apt-config"
        _waiting_apt_unprobeable
    done
    for line in 'Acquire::http::Proxy "DIRECT";' 'Acquire::http "";' 'Acquire::https::Verify-Peer "true";'; do
        printf '#!/bin/bash\necho %q\n' "$line" > "$MOCK_BIN/apt-config"
        run _waiting_apt_unprobeable
        [[ "$status" -ne 0 ]]
    done
}

@test "nudge --waiting lists by severity and says what each tier does" {
    _note repo-tls "nordvpn|standard|6.0.1|repo.nordvpn.com|"
    _note repo-tls "nordvpn-gui|standard|6.0.1|repo.nordvpn.com|libnord:amd64"
    _note network "openssl|security|||"
    run waiting_show table
    [[ "${lines[0]}" == "Security · important: offered and retried every run (nudge --failures)" ]]
    [[ "${lines[1]}" == *"openssl"*"its source could not be reached · since "* ]]
    [[ "${lines[2]}" == "Standard · waiting quietly: offered again once the download answers" ]]
    [[ "${lines[3]}" == *"nordvpn "*"6.0.1"*"repo.nordvpn.com: certificate does not verify from here · since"* ]]
    [[ "${lines[4]}" == *"nordvpn-gui"*"repo.nordvpn.com: certificate does not verify from here (it needs libnord) · since"* ]]
    run waiting_show json
    [[ "$output" == '{"waiting":[{"list":"system","target":"openssl","severity":"security","version":"","cause":"network","host":"","needs":""'* ]]
    [[ "$output" == *'"tries":1,"policy":"retried"}'* ]]
    [[ "$output" == *'"target":"nordvpn-gui","severity":"standard","version":"6.0.1","cause":"repo-tls","host":"repo.nordvpn.com","needs":"libnord:amd64"'*'"policy":"waits"}]}' ]]
    if command -v jq >/dev/null; then
        echo "$output" | jq -e '.waiting | length == 3' >/dev/null
    fi
    run waiting_clear
    [[ "$output" == "Forgot 3 waiting update(s). nudge will offer them again." ]]
    run waiting_show table
    [[ "$output" == "Nothing is waiting: every update nudge offered could be downloaded." ]]
}

@test "the diagnosis knows where each download was to come from, and which wanted credentials" {
    _RETRY_TEXT=$'E: Failed to fetch https://user:pw@repo.nordvpn.com:443/deb/pool/main/n/nordvpn/nordvpn_6.0.1_amd64.deb  Certificate verification failed\nE: Failed to fetch http://mirror.example/pool/libgbm1_24.0_i386.deb  404  Not Found\nE: Failed to fetch https://esm.example/pool/proapp_1.0_amd64.deb  401  Unauthorized [IP: 1.2.3.4 443]'
    _RETRY_UNFETCHED_HOST=()
    _RETRY_UNFETCHED_AUTH=()
    _retry_unfetched_details_apt
    [[ "${_RETRY_UNFETCHED_HOST[nordvpn]}" == "repo.nordvpn.com" ]]
    [[ "${_RETRY_UNFETCHED_HOST[libgbm1:i386]}" == "mirror.example" ]]
    [[ -n "${_RETRY_UNFETCHED_AUTH[proapp]:-}" ]]
    [[ -z "${_RETRY_UNFETCHED_AUTH[libgbm1]:-}${_RETRY_UNFETCHED_AUTH[nordvpn]:-}" ]]
}

@test "a new dependency that cannot be downloaded holds back the selected updates that need it" {
    local log="$TMPDIR_TEST/step.log"
    printf '%s\n' "E: Failed to fetch https://repo.example.org/pool/libnord_2.0_amd64.deb  Could not resolve 'repo.example.org'" \
        "E: Failed to fetch https://repo.example.org/pool/nordvpn_6.0.1_amd64.deb  Could not resolve 'repo.example.org'" \
        "E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?" > "$log"
    _retry_rdepends() { [[ "$1" == "libnord" ]] && printf 'nordvpn-gui\nsomething-not-selected\n'; return 0; }
    retry_record_failure system apt 100 "$log" 1 nordvpn nordvpn-gui vim
    [[ "${_RETRY_F_CAUSE[system]}" == "network" ]]
    [[ "${_RETRY_F_UNFETCHED[system]}" == "nordvpn nordvpn-gui" ]]
    [[ "$(retry_unfetched_via system nordvpn-gui)" == "libnord:amd64" ]]
    [[ -z "$(retry_unfetched_via system nordvpn)" ]]
    [[ "$(retry_unfetched_host system nordvpn-gui)" == "repo.example.org" ]]
    # only those two are counted as failing, not every selected one
    [[ "$(retry_ledger_rows | cut -f2 | LC_ALL=C sort | tr '\n' ' ')" == "nordvpn nordvpn-gui " ]]
    # another list failing afterwards does not take this list's details
    retry_record_failure flatpak flatpak 1 "$log" 1 app/x
    [[ "$(retry_unfetched_host system nordvpn-gui)" == "repo.example.org" ]]
}

@test "only causes that mean the download is not there right now are waiting" {
    local c
    for c in network repo-tls repo-unreachable mirror-stale index-corrupt; do retry_cause_waits "$c"; done
    for c in disk-full lock dpkg-interrupted repo-key sudo-denied declined interrupted unknown package-script; do
        run retry_cause_waits "$c"
        [[ "$status" -ne 0 ]]
    done
}

@test "setting aside takes the names off the ledger and out of the culprits, and says when nothing else explains the failure" {
    printf 'nordvpn\nopenssl\n' | retry_ledger_bump system repo-tls
    _RETRY_F_CAUSE["system"]="mirror-stale"
    _RETRY_F_UNFETCHED["system"]="nordvpn openssl"
    _RETRY_F_CULPRITS["system"]="nordvpn openssl"
    retry_set_aside system nordvpn || true
    [[ "${_RETRY_F_UNFETCHED[system]}" == "openssl" ]]
    [[ "${_RETRY_F_CULPRITS[system]}" == "openssl" ]]
    [[ "$(retry_ledger_rows | cut -f2)" == "openssl" ]]
    [[ "${_RETRY_F_STREAK[system]}" == "1" ]]
    retry_set_aside system openssl
    [[ -z "${_RETRY_F_CAUSE[system]:-}" ]]
    [[ -z "$(retry_failed_lists)" ]]
}
