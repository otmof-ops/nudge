#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/retry.sh
# When an update does not go through. The runner captures what the package
# manager wrote to stderr; this module reads it (the diagnosis: a cause, the
# names it blamed, the lines that said so), keeps the ledger of updates that
# keep failing (one row per package, how many attempts, since when), and
# writes the failure report that says what might resolve it. nudge never
# runs a remedy itself: the commands are written down for the user.

set -euo pipefail

# --- Where things live (all private to the user, 0600 under the state dir) ---
RETRY_LEDGER_FILE="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}/failures.tsv"
RETRY_REPORT_DIR="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}/reports"
RETRY_LOG_DIR="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}/logs"
RETRY_REPORT_MAX=20
RETRY_LOG_MAX=30

# --- The diagnosis of one failed step (set by retry_diagnose) ---
_RETRY_CAUSE=""       # a short id: lock, dpkg-interrupted, disk-full, ... unknown
_RETRY_CULPRITS=""    # the names the output blamed, one per line (validated)
_RETRY_EVIDENCE=""    # the lines that decided it, one per line (sanitised, cut)
_RETRY_TEXT=""        # the sanitised log, for the matchers
_RETRY_UNFETCHED=""   # the downloads apt could not fetch, as name:arch, one per line

# --- What this session recorded, per list (system, flatpak, snap) ---
declare -gA _RETRY_F_CAUSE=()      # cause id
declare -gA _RETRY_F_RC=()         # exit code of the last attempt
declare -gA _RETRY_F_LOG=()        # the captured stderr of the last attempt
declare -gA _RETRY_F_CULPRITS=()   # space-separated names (the blamed ones, else what was selected)
declare -gA _RETRY_F_EVIDENCE=()   # newline-separated lines
declare -gA _RETRY_F_ATTEMPTS=()   # attempts this session
declare -gA _RETRY_F_STREAK=()     # most attempts any of the names has failed (the ledger, across sessions)
declare -gA _RETRY_F_SINCE=()      # the earliest first-failure timestamp among the names
declare -gA _RETRY_F_COUNT=()      # how many names were selected in the list
declare -gA _RETRY_F_UNFETCHED=()  # space-separated selected names whose download failed

# Human titles, the same as the selection menu's
declare -gA _RETRY_LIST_TITLE=([system]="System packages" [flatpak]="Flatpak" [snap]="Snap")

_retry_now() { date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'; }

_retry_mkdir() {
    local d="$1"
    [[ -d "$d" ]] && return 0
    ( umask 077; mkdir -p "$d" ) 2>/dev/null
}

# A name as the ledger, the status file and the dialogs accept it: a package,
# a snap, a Flatpak ref, a key id or a pid, never a shell word
retry_valid_name() {
    # in the C locale: elsewhere a bracket range is a collation range, and
    # letters that only look like these would pass
    local LC_ALL=C
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9+._:/@-]{0,127}$ ]]
}

# What never belongs in a line that is shown or kept: escape sequences, C0
# and C1 controls, the invisible and direction-changing characters, and a
# user:password or a token in a URL (the raw capture keeps what the package
# manager wrote; these lines are the ones quoted and shown)
_retry_scrub() {
    LC_ALL=C sed -E \
        -e 's|\x1b\[[0-9;?]*[ -/]*[@-~]||g; s|\x1b[@-Z\\-_]||g' \
        -e 's|\xc2[\x80-\x9f]||g; s|\xe2\x80[\x8b-\x8f\xaa-\xae]||g; s|\xe2\x81[\xa0-\xa9]||g; s|\xef\xbb\xbf||g' \
        -e 's|://[^/@[:space:]]+@|://[redacted]@|g' \
        -e 's#([?&;](access_)?(token|key|sig|signature|password|passwd|secret|X-Amz-[A-Za-z-]+)=)[^&[:space:]]*#\1[redacted]#gI' \
        2>/dev/null
}

# Escape codes and control characters out, one line in
_retry_clean_line() {
    local s="${1:-}"
    s=$(printf '%s' "$s" | _retry_scrub || printf '%s' "$s")
    s="${s//[[:cntrl:]]/}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# --- Reading a captured log ---
# Usage: _retry_load_text <logfile> -> _RETRY_TEXT (the last 400 lines, cleaned)
_retry_load_text() {
    local f="${1:-}"
    _RETRY_TEXT=""
    [[ -n "$f" && -f "$f" && ! -L "$f" ]] || return 0
    _RETRY_TEXT=$(tail -n 400 "$f" 2>/dev/null \
        | _retry_scrub \
        | tr -d '\000-\010\013-\037\177' 2>/dev/null || true)
}

# 0 when the log matches the pattern (extended regex, case-insensitive)
_retry_has() {
    [[ -n "$_RETRY_TEXT" ]] || return 1
    grep -qiE -- "$1" <<< "$_RETRY_TEXT"
}

# The lines that matched, cleaned and cut, at most <n>. They are the package
# manager's own words, exactly as the terminal already showed them (apt strips
# a user:password from a URI itself); they stay in a 0600 file and are never
# sent anywhere. attacker: assumes the manager's stderr is as safe to keep as
# it was to display; the names pulled out of it are validated separately.
_retry_lines() {
    local pat="$1" n="${2:-3}" line out="" count=0
    [[ -n "$_RETRY_TEXT" ]] || return 0
    while IFS= read -r line; do
        line=$(_retry_clean_line "$line")
        [[ -z "$line" ]] && continue
        [[ "${#line}" -gt 160 ]] && line="${line:0:159}…"
        out+="${line}"$'\n'
        count=$((count + 1))
        [[ "$count" -ge "$n" ]] && break
    done < <(grep -iE -- "$pat" <<< "$_RETRY_TEXT" || true)
    printf '%s' "${out%$'\n'}"
}

# Names captured by a pattern's group (the first unless told), validated, unique, one per line
# Usage: _retry_names <ERE with a group> [group number]
_retry_names() {
    local pat="$1" group="${2:-1}" line name out=""
    [[ -n "$_RETRY_TEXT" ]] || return 0
    [[ "$group" =~ ^[1-9]$ ]] || group=1
    while IFS= read -r line; do
        name=$(sed -E -n "s#.*${pat}.*#\\${group}#p" <<< "$line" | head -1)
        name=$(_retry_clean_line "$name")
        retry_valid_name "$name" || continue
        [[ $'\n'"$out" == *$'\n'"$name"$'\n'* ]] && continue
        out+="${name}"$'\n'
    done < <(grep -iE -- "$pat" <<< "$_RETRY_TEXT" | head -20 || true)
    # one name per line, the last one terminated too, so a while-read loop sees it
    printf '%s' "$out"
}

# A package name out of a file name: foo-1.2-3.fc40.x86_64 or foo_1.2_amd64.deb or foo-1.0-1-x86_64.pkg.tar.zst
_retry_name_from_file() {
    local f="${1:-}" n
    f="${f##*/}"
    case "$f" in
        *.deb)             n="${f%%_*}" ;;
        *.pkg.tar.*)       n="${f%.pkg.tar.*}"; n="${n%-*}"; n="${n%-*}"; n="${n%-*}" ;;
        *.rpm)             n="${f%.rpm}"; n="${n%.*}"; n="${n%-*}"; n="${n%-*}" ;;
        *)                 n="$f" ;;
    esac
    printf '%s' "$n"
}

# The downloads apt could not fetch: "name:arch" for each "Failed to fetch
# …/name_version_arch.deb", unique, in apt's order, one per line. An index
# that failed (InRelease, Packages) is not the download of an update.
_retry_unfetched_apt() {
    local file name arch out=""
    [[ -n "$_RETRY_TEXT" ]] || return 0
    while IFS= read -r file; do
        file="${file##*/}"
        file="${file%.deb}"
        [[ "$file" == *_*_* ]] || continue
        name="${file%%_*}"
        arch="${file##*_}"
        [[ "$arch" =~ ^[a-z0-9]+$ ]] || continue
        retry_valid_name "$name" || continue
        [[ $'\n'"$out" == *$'\n'"${name}:${arch}"$'\n'* ]] && continue
        out+="${name}:${arch}"$'\n'
    done < <(grep -oE 'Failed to fetch [^ ]+\.deb' <<< "$_RETRY_TEXT" | head -n 500 || true)
    printf '%s' "$out"
}

# The selected targets whose download failed, in the order apt named them. A
# download name:arch is the target name:arch when that is selected (another
# architecture), else the target name (the native architecture, or all).
# Usage: retry_unfetched_targets <downloads, one per line> <targets...>
retry_unfetched_targets() {
    local downloads="$1" key t
    shift
    local -A selected=() seen=()
    for t in "$@"; do
        [[ -n "$t" ]] && selected["$t"]=1
    done
    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        if [[ -n "${selected[$key]:-}" ]]; then t="$key"
        elif [[ -n "${selected[${key%%:*}]:-}" ]]; then t="${key%%:*}"
        else continue; fi
        [[ -n "${seen[$t]:-}" ]] && continue
        seen["$t"]=1
        printf '%s\n' "$t"
    done <<< "$downloads"
    return 0
}

_retry_set() {
    # Usage: _retry_set <cause> <evidence pattern> [culprit pattern]
    _RETRY_CAUSE="$1"
    _RETRY_EVIDENCE=$(_retry_lines "$2" 3)
    [[ -n "${3:-}" ]] && _RETRY_CULPRITS=$(_retry_names "$3")
    return 0
}

# ============================================================
# The diagnosis
# ============================================================

# Usage: retry_diagnose <list> <pkgmgr> <rc> <logfile>
# Sets _RETRY_CAUSE, _RETRY_CULPRITS, _RETRY_EVIDENCE and _RETRY_UNFETCHED.
# Always succeeds: an output nobody recognises is the cause "unknown".
retry_diagnose() {
    _retry_diagnose_cause "$@"
    # apt names every archive it could not download; a full upgrade is all or
    # nothing when one fails, so these are what held the rest back
    _RETRY_UNFETCHED=""
    if [[ "${2:-}" == "apt" ]]; then
        _RETRY_UNFETCHED=$(_retry_unfetched_apt) || _RETRY_UNFETCHED=""
    fi
    return 0
}

_retry_diagnose_cause() {
    local list="${1:-system}" pkgmgr="${2:-}" rc="${3:-1}" log="${4:-}"
    _RETRY_CAUSE="unknown"; _RETRY_CULPRITS=""; _RETRY_EVIDENCE=""
    [[ "$rc" =~ ^[0-9]+$ ]] || rc=1
    _retry_load_text "$log"

    # The user stopped it
    if [[ "$rc" -eq 130 ]] || _retry_has '^\^C$|^Interrupt$|KeyboardInterrupt|Operation interrupted|Received SIGINT|interrupted by (the )?user|^Terminated$'; then
        _retry_set interrupted 'Interrupt|SIGINT|\^C|Terminated'
        return 0
    fi
    # The runner refused the configured command before anything ran
    if _retry_has '^E: nudge: (the update command was rejected|no upgrade command)'; then
        _retry_set config '^E: nudge:'
        return 0
    fi
    # sudo said no before anything ran
    if _retry_has 'is not in the sudoers file|is not allowed to execute|a password is required'; then
        _retry_set sudo-denied 'sudoers|not allowed to execute|a password is required'
        return 0
    fi
    if _retry_has 'incorrect password attempt|Sorry, try again|timed out reading password'; then
        _retry_set sudo-password 'incorrect password|Sorry, try again|timed out reading password'
        return 0
    fi
    if _retry_has 'a terminal is required to read the password|no tty present'; then
        _retry_set sudo-no-tty 'terminal is required|no tty present'
        return 0
    fi
    # Somebody else has the package manager
    case "$pkgmgr:$list" in
        *:flatpak|*:snap) ;;
        apt:*)
            if _retry_has 'Could not get lock|Unable to acquire the dpkg frontend lock|Could not open lock file|Unable to lock (the administration directory|directory)|is held by process'; then
                _retry_set lock 'lock|held by process' 'held by process ([0-9]+)'
                return 0
            fi
            if _retry_has 'dpkg was interrupted'; then
                _retry_set dpkg-interrupted 'dpkg was interrupted'
                return 0
            fi
            ;;
        dnf:*)
            if _retry_has 'Waiting for process with pid|is locked by another application|holding the yum lock|already running'; then
                _retry_set lock 'Waiting for process|locked by another|yum lock|already running' 'Waiting for process with pid ([0-9]+)'
                return 0
            fi
            ;;
        pacman:*)
            if _retry_has 'unable to lock database|db\.lck'; then
                _retry_set lock 'unable to lock database|db\.lck'
                return 0
            fi
            ;;
        zypper:*)
            if _retry_has 'System management is locked'; then
                _retry_set lock 'System management is locked' 'locked by the application with pid ([0-9]+)'
                return 0
            fi
            ;;
    esac
    if [[ "$list" == "snap" ]] && _retry_has 'change in progress|too early for operation|device not yet seeded|snapd is (busy|starting)'; then
        _retry_set snap-busy 'change in progress|too early|not yet seeded|snapd is'
        return 0
    fi
    # No room
    if _retry_has "No space left on device|not enough (free )?space|don't have enough free space|Not enough disk space|[Ii]nsufficient space|needs [0-9.]+ ?[KMGT]i?B( more)?( space)? on the|Disk quota exceeded|At least [0-9.]+ ?[KMGT]i?B more space"; then
        _retry_set disk-full 'space|quota'
        return 0
    fi
    # A repository whose certificate cannot be verified
    if _retry_has 'Certificate verification failed|certificate is NOT trusted|certificate verify failed|SSL certificate problem|server certificate verification failed|TLS handshake|Could not handshake'; then
        _retry_set repo-tls 'ertificate|handshake|SSL|TLS' 'https?://([A-Za-z0-9.-]+)/'
        return 0
    fi
    # Keys and signatures
    if _retry_has 'NO_PUBKEY|EXPKEYSIG|KEYEXPIRED|public key is not available|GPG error|signatures couldn.t be verified|is not signed|GPG check FAILED|Public key for .* is not installed|signature could not be verified|Signature verification failed|is unknown trust|invalid or corrupted package \(PGP signature\)|required key missing from keyring|could not be looked up remotely|marginal trust'; then
        _retry_set repo-key 'PUBKEY|KEYSIG|KEYEXPIRED|public key|GPG|signature|signed|trust|keyring' 'NO_PUBKEY ([0-9A-Fa-f]{8,40})'
        if [[ -z "$_RETRY_CULPRITS" ]]; then
            _RETRY_CULPRITS=$(_retry_names 'error: ([A-Za-z0-9@._+-]+): signature from')
        fi
        return 0
    fi
    # The index or a downloaded file is not what it should be
    if _retry_has 'Hash Sum mismatch|is not valid yet|Release file .* (is expired|has expired)|Clearsigned file isn.t valid|Signed file isn.t valid|Splitting up .* failed|invalid or corrupted package|Checksum mismatch|checksum .* (does not match|failed)|Size mismatch'; then
        _retry_set index-corrupt 'mismatch|not valid yet|expired|isn.t valid|Splitting|corrupted|Checksum'
        return 0
    fi
    # snapd itself is not there to talk to
    if [[ "$list" == "snap" ]] && _retry_has 'dial unix .*snapd\.socket|cannot connect to snapd|snapd\.socket: connect'; then
        _retry_set snapd-down 'snapd|socket'
        return 0
    fi
    # The network itself, before a repository that is "gone" and before the
    # mirror: no DNS is neither a dead repository nor a stale index, and the
    # advice for those is not the advice for this
    if _retry_has 'Temporary failure resolving|Could not resolve|Couldn.t resolve|resolve host name|Could not connect to|Connection failed|Connection timed out|Connection refused|Unable to connect to|Network is unreachable|cannot communicate with server|persistent network error|Failed to connect|Timeout was reached|network timeout|download library error|Couldn.t connect|Could not reach|Curl error \(?(6|7|28)\)?|Name or service not known|No route to host'; then
        _retry_set network 'resolv|connect|Connection|unreachable|communicate|network|download|Timeout|reach|Curl error|No route'
        return 0
    fi
    # A repository that cannot be reached, or is gone
    if _retry_has "Failed to download metadata for repo|Repository '[^']+' is invalid|Problem retrieving|Could not refresh|Valid metadata not found|No remote refs found|Unable to load summary|Error updating remote metadata|Failed to update remote metadata|Timeout exceeded when accessing"; then
        _retry_set repo-unreachable 'metadata|Repository|Problem retrieving|refresh|remote refs|summary|Timeout'
        _RETRY_CULPRITS=$(_retry_names "(for repo|Repository) '([A-Za-z0-9._:-]+)'" 2)
        [[ -z "$_RETRY_CULPRITS" ]] && _RETRY_CULPRITS=$(_retry_names '(for|from) remote ([A-Za-z0-9._-]+)' 2)
        return 0
    fi
    # The mirror no longer has it: an HTTP 404, or apt's "unable to fetch" with the network fine
    if _retry_has '[^A-Za-z0-9]404 +Not Found|returned error: 404|Unable to fetch some archives'; then
        _retry_set mirror-stale '404|Not Found|Unable to fetch|failed retrieving file'
        local files f
        files=$(_retry_names 'Failed to fetch [^ ]*/([^ /]+\.deb)')
        [[ -z "$files" ]] && files=$(_retry_names "failed retrieving file '([^']+\.pkg\.tar[^']*)'")
        if [[ -n "$files" ]]; then
            _RETRY_CULPRITS=""
            while IFS= read -r f; do
                f=$(_retry_name_from_file "$f")
                retry_valid_name "$f" && _RETRY_CULPRITS+="${f}"$'\n'
            done <<< "$files"
            _RETRY_CULPRITS="${_RETRY_CULPRITS%$'\n'}"
        fi
        return 0
    fi
    case "$list" in
        snap)
            if _retry_has 'has running apps'; then
                _retry_set snap-running 'has running apps' 'snap "([a-z0-9-]+)" has running apps'
                return 0
            fi
            if _retry_has 'refresh\.hold|is held|refresh is held|held until'; then
                _retry_set snap-held 'hold|held' 'cannot refresh "([a-z0-9-]+)"'
                return 0
            fi
            if _retry_has 'access denied|cannot connect to snapd|requires root'; then
                _retry_set snap-denied 'access denied|snapd|requires root'
                return 0
            fi
            if _retry_has 'cannot refresh "'; then
                _retry_set snap-app 'cannot refresh|error:' 'cannot refresh "([a-z0-9-]+)"'
                return 0
            fi
            ;;
        flatpak)
            if _retry_has 'needs a later flatpak version'; then
                _retry_set flatpak-old 'later flatpak version' 'Error updating ([A-Za-z0-9._/-]+)'
                return 0
            fi
            if _retry_has 'Not authorized|Permission denied|not allowed|polkit|Authorization'; then
                _retry_set flatpak-auth 'authori|Permission denied|not allowed|polkit'
                return 0
            fi
            if _retry_has 'Error updating|error: Failed to update|Error: Failed to update|Error deploying|Error installing'; then
                _retry_set flatpak-app 'Error updating|Failed to update|Error deploying|Error installing|error:' 'Error updating ([A-Za-z0-9._/-]+)'
                return 0
            fi
            ;;
        system)
            case "$pkgmgr" in
                apt)
                    if _retry_has 'error processing package|error processing archive|Errors were encountered while processing|returned error exit status|Sub-process /usr/bin/dpkg returned|trying to overwrite'; then
                        _retry_set package-script 'error processing|Errors were encountered|error exit status|Sub-process|trying to overwrite|E: ' 'error processing package ([A-Za-z0-9+._:-]+)'
                        [[ -z "$_RETRY_CULPRITS" ]] && _RETRY_CULPRITS=$(_retry_names 'which is also in package ([A-Za-z0-9+._:-]+)')
                        [[ -z "$_RETRY_CULPRITS" ]] && _RETRY_CULPRITS=$(_retry_names 'error processing archive [^ ]*/([^ /]+\.deb)' | while IFS= read -r f; do _retry_name_from_file "$f"; echo; done | grep -E '.' || true)
                        return 0
                    fi
                    if _retry_has 'held broken packages|Unable to correct problems|[Uu]nmet dependencies|not fully installed or removed|dependency problems - leaving unconfigured|but it is not going to be installed|is to be installed|Depends: .* but'; then
                        _retry_set deps-broken 'broken|Unable to correct|dependencies|not fully installed|unconfigured|not going to be installed|Depends:'
                        _RETRY_CULPRITS=$(_retry_names '^ ?([A-Za-z0-9+._:-]+) : Depends:')
                        return 0
                    fi
                    ;;
                dnf)
                    if _retry_has 'scriptlet failed|Error in (PREIN|POSTIN|PREUN|POSTUN) scriptlet|%(pre|post)(un)? scriptlet'; then
                        _retry_set package-script 'scriptlet' 'scriptlet in rpm package ([A-Za-z0-9._+-]+)'
                        return 0
                    fi
                    if _retry_has 'Transaction test error|Transaction failed|Error: Problem|^ ?Problem( [0-9]+)?:|conflicting requests|cannot install both|conflicts with|nothing provides|none of the providers can be installed'; then
                        _retry_set deps-broken 'Problem|conflict|nothing provides|providers|Transaction'
                        _RETRY_CULPRITS=$(_retry_names '(package|installing package) ([A-Za-z0-9._+-]+-[0-9][^ ]*) ' 2 | while IFS= read -r f; do _retry_name_from_file "${f}.rpm"; echo; done | grep -E '.' || true)
                        return 0
                    fi
                    ;;
                pacman)
                    if _retry_has 'conflicting files|exists in filesystem'; then
                        _retry_set file-conflict 'conflicting files|exists in filesystem' '^([A-Za-z0-9@._+-]+): /'
                        return 0
                    fi
                    if _retry_has 'could not satisfy dependencies|unresolvable package conflicts|breaks dependency|dependency cycle|are in conflict'; then
                        _retry_set deps-broken 'dependenc|conflict' 'removing ([A-Za-z0-9@._+-]+) breaks'
                        return 0
                    fi
                    if _retry_has 'command failed to execute correctly|hook failed|error: command failed'; then
                        _retry_set package-script 'command failed|hook'
                        return 0
                    fi
                    ;;
                zypper)
                    if _retry_has 'Subprocess failed\. Error: RPM failed|scriptlet failed|%(pre|post)(un)? scriptlet'; then
                        _retry_set package-script 'RPM failed|scriptlet' 'scriptlet in rpm package ([A-Za-z0-9._+-]+)'
                        return 0
                    fi
                    if _retry_has '^ ?Problem( [0-9]+)?:|nothing provides|cannot install both|conflicts with|cannot be provided|Solution [0-9]+:'; then
                        _retry_set deps-broken 'Problem|provides|conflict|Solution'
                        return 0
                    fi
                    ;;
            esac
            ;;
    esac
    # The user answered no to the package manager's own question. apt's "Abort."
    # goes to stdout, which is not captured, and apt exits 1 where its errors
    # exit 100 with an "E: " line (the prefix is the same in every language);
    # dnf and pacman exit 1 too, with nothing on stderr at all.
    if _retry_has '^Abort\.$|^Operation aborted\.$|^Operation canceled\.$|^Aborting\.?$|Exiting on user command'; then
        _retry_set declined 'Abort|aborted|canceled|Exiting on user command'
        return 0
    fi
    if [[ "$list" == "system" && "$rc" -eq 1 && -n "$log" && -f "$log" ]]; then
        if [[ "$pkgmgr" == "apt" ]] && ! _retry_has '^E: '; then
            _retry_set declined 'Abort|aborted'
            return 0
        fi
        if [[ "$pkgmgr" =~ ^(dnf|pacman)$ && -z "${_RETRY_TEXT//[[:space:]]/}" ]]; then
            _retry_set declined 'Abort|aborted'
            return 0
        fi
    fi
    # Nobody recognised it: keep the first error lines as the evidence
    _retry_set unknown '^(E|W):|^error:|^Error|^fatal|failed|cannot|unable|denied'
    return 0
}

# ============================================================
# What a cause means, and what to do about it
# ============================================================

# Usage: retry_cause_headline <cause> <pkgmgr> <list> [culprits...] -> one line
retry_cause_headline() {
    local cause="${1:-unknown}" pkgmgr="${2:-}" list="${3:-system}"
    shift 3 2>/dev/null || shift $#
    local who="${*:-}" first="${1:-}"
    case "$cause" in
        interrupted)     printf 'the command was interrupted before it finished' ;;
        declined)        printf 'you answered no when the package manager asked' ;;
        config)          printf 'the update command in nudge.conf was rejected before anything ran' ;;
        snapd-down)      printf 'snapd is not running' ;;
        repo-tls)
            if [[ -n "$first" ]]; then printf 'the certificate of the repository at %s could not be verified' "$first"
            else printf 'a repository'"'"'s certificate could not be verified'; fi ;;
        sudo-denied)     printf 'sudo would not allow it: this account cannot run the package manager as root' ;;
        sudo-password)   printf 'the sudo password was not accepted' ;;
        sudo-no-tty)     printf 'sudo had nowhere to ask for the password' ;;
        lock)
            if [[ -n "$first" ]]; then printf 'another package manager is running (pid %s)' "$first"
            else printf 'another package manager is running'; fi ;;
        dpkg-interrupted) printf 'a previous package operation was cut short' ;;
        disk-full)       printf 'the disk is full' ;;
        repo-key)
            if [[ -n "$first" ]]; then printf 'a repository signing key is missing or expired (%s)' "$first"
            else printf 'a repository signing key is missing or expired'; fi ;;
        index-corrupt)   printf 'the package index or a downloaded file is not what the mirror promised' ;;
        mirror-stale)    printf 'the mirror no longer has the files the index lists' ;;
        repo-unreachable)
            if [[ -n "$first" ]]; then printf 'the repository %s could not be reached' "$first"
            else printf 'a repository could not be reached'; fi ;;
        network)         printf 'the servers could not be reached' ;;
        package-script)
            if [[ -n "$first" ]]; then printf 'the install script of %s failed' "$first"
            else printf 'a package'"'"'s own install script failed'; fi ;;
        deps-broken)     printf 'the packages do not fit together' ;;
        file-conflict)
            if [[ -n "$first" ]]; then printf '%s wants to write a file that is already there' "$first"
            else printf 'a package wants to write a file that is already there'; fi ;;
        snap-running)
            if [[ -n "$who" && "$who" == *" "* ]]; then printf '%s are still running' "${who// /, }"
            elif [[ -n "$who" ]]; then printf '%s is still running' "$who"
            else printf 'the snap is still running'; fi ;;
        snap-busy)       printf 'snapd is busy with another change' ;;
        snap-held)       printf 'the refresh is on hold' ;;
        snap-denied)     printf 'snap needs root for the refresh' ;;
        snap-app)
            if [[ -n "$who" ]]; then printf 'the refresh of %s failed' "${who// /, }"
            else printf 'the refresh failed'; fi ;;
        flatpak-old)     printf 'the update needs a newer Flatpak than this system has' ;;
        flatpak-auth)    printf 'no permission to change the system-wide Flatpak installation' ;;
        flatpak-app)
            if [[ -n "$first" ]]; then printf 'the update of %s failed' "$first"
            else printf 'the Flatpak update failed'; fi ;;
        *)               printf 'the command failed, and nudge did not recognise the message' ;;
    esac
}

# Usage: retry_cause_explain <cause> <pkgmgr> <list> -> one or two sentences
retry_cause_explain() {
    local cause="${1:-unknown}" pkgmgr="${2:-}" list="${3:-system}"
    case "$cause" in
        interrupted)      printf 'It was stopped (Ctrl-C, or the window closed). Nothing else is needed.' ;;
        declined)         printf 'Nothing was changed. The package manager asks before it installs; a no there ends the step.' ;;
        config)           printf 'UPDATE_COMMAND is a plain package-manager command line, nothing more; nudge --validate says what it objects to.' ;;
        snapd-down)       printf 'Every snap refresh goes through the snapd service, and there was nobody at its socket.' ;;
        repo-tls)         printf 'Its certificate is wrong, expired, or for another name, or something between you and it is rewriting TLS. The other repositories are fine.' ;;
        sudo-denied)      printf 'The system updates run as root through sudo, and sudo refused this account. Nothing was changed.' ;;
        sudo-password)    printf 'The step never started; nothing was changed.' ;;
        sudo-no-tty)      printf 'The session ran without a terminal, so the password prompt had nowhere to go.' ;;
        lock)             printf 'Only one package manager may run at a time. Just after login it is often the software centre or unattended-upgrades finishing its own run.' ;;
        dpkg-interrupted) printf 'dpkg will not continue until that operation is finished by hand.' ;;
        disk-full)        printf 'There is no room for the downloaded packages or the installed files.' ;;
        repo-key)         printf 'An index that cannot be verified is refused. A third-party repository whose key changed, or has gone, is the usual reason.' ;;
        index-corrupt)    printf 'What the mirror served does not match what it promised. A refresh usually fixes it; if it says "not valid yet", the clock is wrong.' ;;
        mirror-stale)     printf 'The index is older than the mirror. A refresh fixes it, unless a repository has been removed for good.' ;;
        repo-unreachable) printf 'The other repositories are fine; this one is down, moved, or gone.' ;;
        network)          printf 'The download never got going: the connection, a proxy, a VPN or a captive portal is in the way, or the mirror is down.' ;;
        package-script)   printf 'dpkg or rpm stopped at that package. The rest of the upgrade is on hold until it is fixed.' ;;
        deps-broken)      printf 'Something half-installed, held back, or from a repository that no longer matches the system blocks the rest.' ;;
        file-conflict)    printf 'A file on disk is not owned by any package, or by a different one. Arch never overwrites it on its own.' ;;
        snap-running)     printf 'A snap with open windows or background pieces is not refreshed under them.' ;;
        snap-busy)        printf 'snapd finishes one change at a time.' ;;
        snap-held)        printf 'A hold was set on the refresh, by a schedule or by hand.' ;;
        snap-denied)      printf 'The refresh runs through sudo; see the lines above for why sudo refused.' ;;
        flatpak-old)      printf 'Flatpak itself comes from the system package manager; the app wants a newer one.' ;;
        flatpak-auth)     printf 'A system-wide installation wants an administrator'"'"'s say-so, and no authentication agent answered.' ;;
        flatpak-app)      printf 'The other apps and runtimes went through; this one did not.' ;;
        *)                printf 'The error output is saved; the lines above say what happened in the package manager'"'"'s own words.' ;;
    esac
}

# Usage: retry_cause_remedy <cause> <pkgmgr> <list> [culprits...] -> steps, one per line;
# a line that starts with "$ " is a command to run, the rest is advice.
retry_cause_remedy() {
    local cause="${1:-unknown}" pkgmgr="${2:-}" list="${3:-system}"
    shift 3 2>/dev/null || shift $#
    local -a who=("$@")
    local first="${who[0]:-}" name="${who[0]:-<name>}"
    case "$cause" in
        interrupted)
            echo 'run nudge again when you are ready' ;;
        declined)
            echo 'run nudge again and answer yes when the package manager asks' ;;
        config)
            echo '$ nudge --validate'
            echo 'fix UPDATE_COMMAND in ~/.config/nudge/nudge.conf, or remove the line to get the default back' ;;
        snapd-down)
            echo '$ systemctl status snapd'
            echo '$ sudo systemctl start snapd' ;;
        repo-tls)
            case "$pkgmgr" in
                apt)    echo "find the repository: grep -r \"${first:-<host>}\" /etc/apt/sources.list /etc/apt/sources.list.d/"
                        echo 'if you no longer use it, remove its file; otherwise its own page says how its certificate or URL changed'
                        echo '$ sudo apt update   (continues without it in the meantime)' ;;
                dnf)    echo "find the repository: grep -r \"${first:-<host>}\" /etc/yum.repos.d/"; echo "for this upgrade only: sudo dnf upgrade --disablerepo=<repo>" ;;
                zypper) echo '$ zypper lr -u   (the URL of each repository)'; echo 'disable it: sudo zypper modifyrepo --disable <alias>' ;;
                *)      echo 'find the repository in the package manager'"'"'s configuration and disable or fix it' ;;
            esac
            echo 'a VPN or proxy that inspects TLS can cause this too: try without it' ;;
        sudo-denied)
            echo 'ask the administrator of this machine to add your account to the sudo (or wheel) group, then log out and back in'
            echo 'until then the updates can be run by an account that has sudo' ;;
        sudo-password)
            echo 'try again and type your login password when the window asks' ;;
        sudo-no-tty)
            echo 'run the update from a terminal of your own: nudge'
            echo 'or set TERMINAL_EMULATOR in ~/.config/nudge/nudge.conf to a terminal that is installed' ;;
        lock)
            echo 'wait for it to finish, then try again'
            case "$pkgmgr:$list" in
                apt:system)    echo '$ ps -eo pid,comm,args | grep -E "apt|dpkg|unattended" | grep -v grep' ;;
                dnf:system)    echo '$ ps -eo pid,comm,args | grep -E "dnf|yum|packagekit" | grep -v grep' ;;
                pacman:system) echo 'if no pacman is running, the lock is stale:'; echo '$ sudo rm /var/lib/pacman/db.lck' ;;
                zypper:system) echo '$ ps -eo pid,comm,args | grep -E "zypp|yast|packagekit" | grep -v grep' ;;
            esac
            [[ "$pkgmgr" != "pacman" ]] && echo 'if nothing is running and it still fails, a reboot clears a stale lock' ;;
        dpkg-interrupted)
            echo '$ sudo dpkg --configure -a'
            echo '$ sudo apt-get install -f'
            echo 'then run nudge again' ;;
        disk-full)
            case "$list" in
                flatpak)
                    echo '$ df -h /var/lib/flatpak ~/.local/share/flatpak'
                    echo '$ flatpak uninstall --unused'
                    echo '$ flatpak repair --user' ;;
                snap)
                    echo '$ df -h /'
                    echo 'old revisions take the room; keep fewer of them:'
                    echo '$ sudo snap set system refresh.retain=2'
                    echo '$ snap list --all   (then: sudo snap remove --revision=<rev> <name> for a disabled one)' ;;
                *)
                    echo '$ df -h / /var /boot'
                    case "$pkgmgr" in
                        apt)    echo '$ sudo apt clean'; echo '$ sudo apt autoremove --purge' ;;
                        dnf)    echo '$ sudo dnf clean all'; echo '$ sudo dnf autoremove' ;;
                        pacman) echo '$ sudo pacman -Sc' ;;
                        zypper) echo '$ sudo zypper clean --all' ;;
                    esac
                    echo '$ sudo journalctl --vacuum-time=7d'
                    echo 'then run nudge again' ;;
            esac ;;
        repo-key)
            case "$pkgmgr" in
                apt)
                    echo 'the repository'"'"'s own page says how to install its key (/etc/apt/keyrings/ and signed-by= in its .sources file)'
                    echo 'if you no longer use it, remove its file from /etc/apt/sources.list.d/'
                    echo '$ sudo apt update' ;;
                dnf)
                    echo 'import the key from the repository'"'"'s page, then:'
                    echo '$ sudo rpm --import <key-url>'
                    echo 'or check its file under /etc/yum.repos.d/ and run: sudo dnf clean all' ;;
                pacman)
                    echo '$ sudo pacman -Sy archlinux-keyring'
                    echo '$ sudo pacman -Su'
                    echo 'if the keyring itself is broken: sudo pacman-key --init && sudo pacman-key --populate archlinux' ;;
                zypper)
                    echo '$ sudo zypper refresh   (import the key only for a repository you trust)'
                    echo '$ zypper lr -d          (shows where each repository comes from)' ;;
                *)  echo 'refresh the repository and accept its key only if you trust it' ;;
            esac ;;
        index-corrupt)
            case "$pkgmgr" in
                apt)
                    echo '$ sudo apt clean'
                    echo '$ sudo rm -r /var/lib/apt/lists/*   (the index is downloaded again)'
                    echo '$ sudo apt update'
                    echo 'if it said "not valid yet", set the clock first: timedatectl' ;;
                dnf)    echo '$ sudo dnf clean all'; echo '$ sudo dnf upgrade --refresh' ;;
                pacman) echo '$ sudo pacman -Sc   (the half-downloaded file goes)'; echo '$ sudo pacman -Syyu' ;;
                zypper) echo '$ sudo zypper clean --all'; echo '$ sudo zypper refresh' ;;
                *)      echo 'clear the download cache and refresh the index, then try again' ;;
            esac ;;
        mirror-stale)
            case "$pkgmgr" in
                apt)    echo '$ sudo apt update'; echo 'then run nudge again'; echo 'if one repository keeps failing, its files are gone: remove it from /etc/apt/sources.list.d/' ;;
                dnf)    echo '$ sudo dnf clean all'; echo '$ sudo dnf upgrade --refresh' ;;
                pacman) echo '$ sudo pacman -Syyu   (databases and files from the same mirror)'; echo 'or pick a fresher mirror: https://archlinux.org/mirrorlist/' ;;
                zypper) echo '$ sudo zypper refresh'; echo '$ sudo zypper update' ;;
                *)      echo 'refresh the index, then try again' ;;
            esac ;;
        repo-unreachable)
            case "$list" in
                flatpak)
                    echo '$ flatpak remotes'
                    echo "\$ flatpak remote-ls ${first:-<remote>}   (tests one remote)"
                    echo "a remote that is gone for good: flatpak remote-delete ${first:-<remote>}" ;;
                *)
                    case "$pkgmgr" in
                        dnf)
                            echo '$ sudo dnf clean all'
                            echo "for this upgrade only: sudo dnf upgrade --disablerepo=${first:-<repo>}"
                            echo 'a repository that is gone for good is disabled in its file under /etc/yum.repos.d/; the distribution'"'"'s own repositories never are' ;;
                        zypper)
                            echo '$ sudo zypper refresh'
                            echo "if it is gone: sudo zypper modifyrepo --disable ${first:-<alias>}" ;;
                        apt)
                            echo '$ sudo apt update'
                            echo 'if one repository keeps failing, remove or disable its file in /etc/apt/sources.list.d/' ;;
                        *)  echo 'refresh the repositories; disable the one that is gone' ;;
                    esac ;;
            esac
            echo 'try again in a few minutes: repositories do go down' ;;
        network)
            echo 'check the connection: a VPN, a proxy or a captive portal can block the package servers while the web works'
            echo 'try again in a few minutes: mirrors do go down'
            case "$pkgmgr:$list" in
                apt:system)    echo 'if it stays down, pick another mirror (Software & Updates, or /etc/apt/sources.list.d/)' ;;
                dnf:system)    echo '$ sudo dnf clean all' ;;
                pacman:system) echo 'refresh the mirror list, then: sudo pacman -Syyu' ;;
                zypper:system) echo '$ sudo zypper refresh' ;;
                *:snap)        echo '$ snap changes'; echo '$ systemctl status snapd' ;;
                *:flatpak)     echo '$ flatpak remotes' ;;
            esac ;;
        package-script)
            echo "the lines above \"error processing package ${name}\" say what the script complained about"
            case "$pkgmgr" in
                apt)
                    echo '$ sudo dpkg --configure -a'
                    echo '$ sudo apt-get install -f'
                    echo "if it repeats: sudo apt-get install --reinstall ${name}" ;;
                dnf)    echo "\$ sudo dnf reinstall ${name}" ;;
                zypper) echo "\$ sudo zypper install --force ${name}" ;;
                pacman) echo 'the Arch news or the package'"'"'s page usually names the manual step: https://archlinux.org/news/' ;;
            esac
            echo 'if the package is broken for everyone there is a bug report for it: search its name with the error line' ;;
        deps-broken)
            case "$pkgmgr" in
                apt)
                    echo '$ sudo apt-get install -f'
                    echo '$ sudo dpkg --configure -a'
                    echo '$ apt-mark showhold   (packages held back by hand)'
                    echo "\$ apt policy ${name}   (where a package came from; a third-party repository that no longer matches the system is the usual cause)" ;;
                dnf)
                    echo '$ sudo dnf upgrade --refresh'
                    echo '$ sudo dnf distro-sync'
                    echo 'only if you are happy for the listed packages to go: sudo dnf upgrade --best --allowerasing' ;;
                pacman)
                    echo 'the Arch news usually has the manual step: https://archlinux.org/news/'
                    echo '$ sudo pacman -Syu' ;;
                zypper)
                    echo '$ sudo zypper update   (it offers solutions to pick from)'
                    echo '$ zypper lr -d         (a repository that no longer matches the system)' ;;
                *)  echo 'run the package manager by hand; it names the packages in the way' ;;
            esac ;;
        file-conflict)
            echo "\$ pacman -Qo <file>   (which package owns the file; none means something installed outside pacman left it)"
            echo 'read the Arch news before any --overwrite: https://archlinux.org/news/'
            echo 'only when the news or the wiki says so for that file: sudo pacman -Syu --overwrite <glob>' ;;
        snap-running)
            echo "close ${who[*]:-the snap} (its windows and any background piece), then try again"
            echo 'snapd also refreshes it on its own once it has been closed for a while'
            echo '$ snap changes' ;;
        snap-busy)
            echo 'wait a minute and try again'
            echo '$ snap changes          (what snapd is doing)'
            echo '$ sudo snap abort <id>  (cancels a stuck change)' ;;
        snap-held)
            echo "\$ snap refresh --unhold ${first:-<snap>}" ;;
        snap-denied)
            echo 'the refresh runs as: sudo snap refresh'
            echo 'see the sudo lines above' ;;
        snap-app)
            echo "\$ snap refresh ${first:-<snap>}   (alone, for the full message)"
            echo '$ snap changes'
            echo 'a snap that is already current needs nothing: snap list' ;;
        flatpak-old)
            echo 'update Flatpak itself; it comes from the system package manager'
            echo "or hold that app for now: flatpak mask ${first:-<app>}" ;;
        flatpak-auth)
            echo '$ sudo flatpak update'
            echo 'or keep it per-user: flatpak update --user' ;;
        flatpak-app)
            echo "\$ flatpak update ${first:-<app>}   (alone, for the full message)"
            echo '$ flatpak repair --user   (or: sudo flatpak repair)'
            echo '$ flatpak uninstall --unused' ;;
        *)
            echo 'read the lines above; the full error output is saved (the path is below)'
            case "$list" in
                system)  echo 'run the update command by hand in a terminal to see everything it says' ;;
                flatpak) echo '$ flatpak update' ;;
                snap)    echo '$ sudo snap refresh' ;;
            esac
            echo 'if it keeps failing, the message is the thing to search for' ;;
    esac
}

# ============================================================
# The ledger: one row per update that failed, until it goes through
# failures.tsv: list <TAB> target <TAB> count <TAB> first <TAB> last <TAB> cause
# ============================================================

_retry_ledger_valid() {
    # Usage: _retry_ledger_valid <list> <target> <count> <first> <last> <cause>
    local LC_ALL=C
    [[ "${1:-}" =~ ^(system|flatpak|snap)$ ]] || return 1
    retry_valid_name "${2:-}" || return 1
    [[ "${3:-}" =~ ^[1-9][0-9]{0,5}$ ]] || return 1
    [[ "${4:-}" =~ ^[0-9][0-9T:.+Z-]{0,39}$ ]] || return 1
    [[ "${5:-}" =~ ^[0-9][0-9T:.+Z-]{0,39}$ ]] || return 1
    [[ "${6:-}" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || return 1
    return 0
}

# Every valid row, as it is in the file
_retry_ledger_read() {
    [[ -f "$RETRY_LEDGER_FILE" && ! -L "$RETRY_LEDGER_FILE" ]] || return 0
    local list target count first last cause
    while IFS=$'\t' read -r list target count first last cause || [[ -n "$list" ]]; do
        _retry_ledger_valid "$list" "$target" "$count" "$first" "$last" "$cause" || continue
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$list" "$target" "$count" "$first" "$last" "$cause"
    done < "$RETRY_LEDGER_FILE"
}

# Replace the file with stdin, atomically and privately
_retry_ledger_replace() {
    _retry_mkdir "$(dirname "$RETRY_LEDGER_FILE")" || return 1
    if [[ -L "$RETRY_LEDGER_FILE" ]]; then
        log_warn "Refusing to write the failure ledger through a symlink: $RETRY_LEDGER_FILE"
        return 1
    fi
    local tmp
    tmp=$(umask 077 && mktemp "${RETRY_LEDGER_FILE}.XXXXXX") || return 1
    cat > "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$RETRY_LEDGER_FILE" || { rm -f "$tmp"; return 1; }
}

# Read names from stdin into the named array (validated, unique)
_retry_read_names() {
    local -n _out="$1"
    local name
    _out=()
    while IFS= read -r name || [[ -n "$name" ]]; do
        name="${name//[[:cntrl:]]/}"
        retry_valid_name "$name" || continue
        local n
        for n in "${_out[@]}"; do [[ "$n" == "$name" ]] && continue 2; done
        _out+=("$name")
    done
}

# Usage: retry_ledger_bump <list> <cause> <<< names (one per line)
# Another failed attempt for these names: count+1, or a new row.
retry_ledger_bump() {
    local list="$1" cause="${2:-unknown}" now
    now=$(_retry_now)
    [[ "$cause" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || cause="unknown"
    local -a names=()
    _retry_read_names names
    [[ "${#names[@]}" -gt 0 ]] || return 0
    local -A hit=()
    local out="" l t c f la ca n
    while IFS=$'\t' read -r l t c f la ca; do
        [[ -z "$l" ]] && continue
        if [[ "$l" == "$list" ]]; then
            for n in "${names[@]}"; do
                if [[ "$n" == "$t" ]]; then
                    c=$((c + 1)); la="$now"; ca="$cause"; hit["$n"]=1
                    break
                fi
            done
        fi
        out+="${l}"$'\t'"${t}"$'\t'"${c}"$'\t'"${f}"$'\t'"${la}"$'\t'"${ca}"$'\n'
    done < <(_retry_ledger_read)
    for n in "${names[@]}"; do
        [[ -n "${hit[$n]:-}" ]] && continue
        out+="${list}"$'\t'"${n}"$'\t'"1"$'\t'"${now}"$'\t'"${now}"$'\t'"${cause}"$'\n'
    done
    printf '%s' "$out" | _retry_ledger_replace
}

# Usage: retry_ledger_forgive <list> <<< names  — they went through: the rows go
retry_ledger_forgive() {
    local list="$1"
    local -a names=()
    _retry_read_names names
    [[ "${#names[@]}" -gt 0 ]] || return 0
    [[ -f "$RETRY_LEDGER_FILE" ]] || return 0
    local out="" l t c f la ca n keep
    while IFS=$'\t' read -r l t c f la ca; do
        [[ -z "$l" ]] && continue
        keep=true
        if [[ "$l" == "$list" ]]; then
            for n in "${names[@]}"; do [[ "$n" == "$t" ]] && { keep=false; break; }; done
        fi
        [[ "$keep" == "true" ]] && out+="${l}"$'\t'"${t}"$'\t'"${c}"$'\t'"${f}"$'\t'"${la}"$'\t'"${ca}"$'\n'
    done < <(_retry_ledger_read)
    printf '%s' "$out" | _retry_ledger_replace
}

# Usage: retry_ledger_prune <list> <<< pending names — rows of this list for
# updates that are no longer pending (installed some other way, or gone) go.
# With no pending names given the list is left alone.
retry_ledger_prune() {
    local list="$1"
    local -a names=()
    _retry_read_names names
    [[ "${#names[@]}" -gt 0 ]] || return 0
    [[ -f "$RETRY_LEDGER_FILE" ]] || return 0
    local out="" l t c f la ca n keep
    while IFS=$'\t' read -r l t c f la ca; do
        [[ -z "$l" ]] && continue
        keep=true
        if [[ "$l" == "$list" ]]; then
            keep=false
            for n in "${names[@]}"; do [[ "$n" == "$t" ]] && { keep=true; break; }; done
        fi
        [[ "$keep" == "true" ]] && out+="${l}"$'\t'"${t}"$'\t'"${c}"$'\t'"${f}"$'\t'"${la}"$'\t'"${ca}"$'\n'
    done < <(_retry_ledger_read)
    printf '%s' "$out" | _retry_ledger_replace
}

# Usage: retry_ledger_max <list> <<< names -> "<max count> <earliest first>"
retry_ledger_max() {
    local list="$1"
    local -a names=()
    _retry_read_names names
    local max=0 since="" l t c f la ca n
    while IFS=$'\t' read -r l t c f la ca; do
        [[ "$l" == "$list" ]] || continue
        for n in "${names[@]}"; do
            [[ "$n" == "$t" ]] || continue
            [[ "$c" -gt "$max" ]] && max="$c"
            if [[ -z "$since" || "$f" < "$since" ]]; then since="$f"; fi
        done
    done < <(_retry_ledger_read)
    printf '%s %s' "$max" "$since"
}

# Every row, the most-failed first, then the most recent
retry_ledger_rows() {
    _retry_ledger_read | LC_ALL=C sort -t$'\t' -k3,3nr -k5,5r
}

retry_ledger_clear() {
    rm -f "$RETRY_LEDGER_FILE" 2>/dev/null || true
}

# ============================================================
# The session's record: one entry per list, kept in _RETRY_F_*
# ============================================================

# Usage: retry_log_path <list> <attempt> -> a fresh private file for the step's stderr
retry_log_path() {
    local list="${1:-system}" attempt="${2:-1}" ts
    _retry_mkdir "$RETRY_LOG_DIR" || return 1
    ts=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo now)
    local f
    # a name nobody can plant in advance (same user or not): mktemp, never ": >"
    f=$(umask 077 && mktemp --suffix=.log "${RETRY_LOG_DIR}/upgrade-${ts}-${list}-${attempt}.XXXXXX" 2>/dev/null) || return 1
    # the newest RETRY_LOG_MAX stay, this one among them
    _retry_rotate "$RETRY_LOG_DIR" 'upgrade-*.log' "$RETRY_LOG_MAX"
    printf '%s' "$f"
}

# Keep the newest RETRY_LOG_MAX logs and RETRY_REPORT_MAX reports
_retry_rotate() {
    local dir="$1" glob="$2" max="$3" count f
    [[ -d "$dir" ]] || return 0
    count=$(find "$dir" -maxdepth 1 -name "$glob" -type f -print0 2>/dev/null | tr -cd '\0' | wc -c || echo 0)
    [[ "$count" -gt "$max" ]] || return 0
    # NUL-separated end to end: a file name is not a line
    find "$dir" -maxdepth 1 -name "$glob" -type f -print0 2>/dev/null | LC_ALL=C sort -z | head -z -n $((count - max)) \
        | xargs -0 -r rm -f -- 2>/dev/null
    return 0
}

# Usage: retry_record_failure <list> <pkgmgr> <rc> <logfile> <attempt> [selected names...]
# Diagnoses the log, bumps the ledger for the blamed names (or every selected
# one when nobody was blamed), and keeps the entry for the report. The names
# are arguments, not stdin: the entry lives in this shell, never a pipeline's.
retry_record_failure() {
    local list="$1" pkgmgr="${2:-}" rc="${3:-1}" log="${4:-}" attempt="${5:-1}"
    shift 5 2>/dev/null || shift $#
    local -a selected=()
    _retry_read_names selected < <(printf '%s\n' "$@")
    retry_diagnose "$list" "$pkgmgr" "$rc" "$log"
    # the selected updates whose download failed: what held this step back
    local -a unfetched=()
    if [[ -n "$_RETRY_UNFETCHED" && "${#selected[@]}" -gt 0 ]]; then
        mapfile -t unfetched < <(retry_unfetched_targets "$_RETRY_UNFETCHED" "${selected[@]}")
    fi
    local -a blamed=()
    if [[ -n "$_RETRY_CULPRITS" ]]; then
        local n
        while IFS= read -r n; do
            # a pid, a key id or a repository is evidence, not an update
            case "$_RETRY_CAUSE" in lock|repo-key|repo-unreachable|repo-tls) break ;; esac
            [[ -n "$n" ]] && blamed+=("$n")
        done <<< "$_RETRY_CULPRITS"
    fi
    # counted against: what could not be downloaded, else the blamed names, else every selected one
    local -a counted=("${blamed[@]}")
    [[ "${#unfetched[@]}" -gt 0 ]] && counted=("${unfetched[@]}")
    [[ "${#counted[@]}" -eq 0 ]] && counted=("${selected[@]}")
    # Counted against the names only when the update itself failed; a ledger
    # that cannot be written is a warning, never the end of the session
    local max=0 since=""
    if retry_cause_counts "$_RETRY_CAUSE" && [[ "${#counted[@]}" -gt 0 ]]; then
        printf '%s\n' "${counted[@]}" | retry_ledger_bump "$list" "$_RETRY_CAUSE" \
            || log_warn "The failure ledger could not be written: $RETRY_LEDGER_FILE"
        read -r max since <<< "$(printf '%s\n' "${counted[@]}" | retry_ledger_max "$list")"
    fi
    _RETRY_F_CAUSE["$list"]="$_RETRY_CAUSE"
    _RETRY_F_RC["$list"]="$rc"
    _RETRY_F_LOG["$list"]="$log"
    _RETRY_F_EVIDENCE["$list"]="$_RETRY_EVIDENCE"
    _RETRY_F_ATTEMPTS["$list"]="$attempt"
    _RETRY_F_STREAK["$list"]="${max:-0}"
    _RETRY_F_SINCE["$list"]="${since:-}"
    _RETRY_F_COUNT["$list"]="${#selected[@]}"
    _RETRY_F_UNFETCHED["$list"]="${unfetched[*]}"
    # what the report names: the blamed ones, else the evidence names (a pid, a key), else nothing
    if [[ "${#blamed[@]}" -gt 0 ]]; then
        _RETRY_F_CULPRITS["$list"]="${blamed[*]}"
    else
        _RETRY_F_CULPRITS["$list"]="${_RETRY_CULPRITS//$'\n'/ }"
    fi
    return 0
}

# Usage: retry_record_success <list> [selected names...] — the rows go, the entry goes
retry_record_success() {
    local list="$1"
    shift
    retry_ledger_forgive "$list" < <(printf '%s\n' "$@") \
        || log_warn "The failure ledger could not be written: $RETRY_LEDGER_FILE"
    # the capture of the attempt before this one is of no use now
    [[ -n "${_RETRY_F_LOG[$list]:-}" ]] && rm -f "${_RETRY_F_LOG[$list]}" 2>/dev/null
    unset "_RETRY_F_CAUSE[$list]" "_RETRY_F_RC[$list]" "_RETRY_F_LOG[$list]" "_RETRY_F_CULPRITS[$list]" \
          "_RETRY_F_EVIDENCE[$list]" "_RETRY_F_ATTEMPTS[$list]" "_RETRY_F_STREAK[$list]" "_RETRY_F_SINCE[$list]" "_RETRY_F_COUNT[$list]" \
          "_RETRY_F_UNFETCHED[$list]"
    return 0
}

# The lists that failed, in menu order
retry_failed_lists() {
    local list
    for list in system flatpak snap; do
        [[ -n "${_RETRY_F_CAUSE[$list]:-}" ]] && printf '%s\n' "$list"
    done
    return 0
}

# 0 when any failed list has failed at least RETRY_REPORT_AFTER times
retry_report_due() {
    local after="${RETRY_REPORT_AFTER:-2}" list
    [[ "$after" =~ ^[0-9]+$ ]] || after=2
    [[ "$after" -lt 1 ]] && after=1
    for list in system flatpak snap; do
        [[ -n "${_RETRY_F_CAUSE[$list]:-}" ]] || continue
        [[ "${_RETRY_F_STREAK[$list]:-0}" -ge "$after" ]] && return 0
    done
    return 1
}

# 0 when a cause is the update's own failure, counted against it in the ledger;
# the user stopping it or saying no, sudo refusing, or a rejected command are not
retry_cause_counts() {
    case "${1:-}" in
        interrupted|declined|sudo-denied|sudo-password|sudo-no-tty|config) return 1 ;;
        *) return 0 ;;
    esac
}

# 0 when another attempt could go through on its own: not after a no, a
# Ctrl-C, sudo refusing the account, or a rejected command (a mistyped
# password is worth another go)
retry_cause_retriable() {
    case "${1:-}" in
        interrupted|declined|sudo-denied|sudo-no-tty|config) return 1 ;;
        *) return 0 ;;
    esac
}

# "2026-10-24 19:40" from an ISO timestamp
_retry_when() {
    local ts="${1:-}"
    ts="${ts:0:16}"
    printf '%s' "${ts/T/ }"
}

# "~/..." for the user's own paths
retry_tilde() {
    local p="${1:-}"
    [[ -n "${HOME:-}" && "$p" == "$HOME"/* ]] && p="~${p#"$HOME"}"
    printf '%s' "$p"
}

# ============================================================
# The report
# ============================================================

# Usage: retry_report_text <pkgmgr> <scope> <attempts this session> -> the report, plain text
retry_report_text() {
    local pkgmgr="${1:-}" scope="${2:-all}" attempts="${3:-1}" list now
    now=$(_retry_now)
    local nl=$'\n' out=""
    out+="nudge · failure report${nl}"
    out+="======================${nl}"
    out+="when:            $(_retry_when "$now")${nl}"
    out+="package manager: ${pkgmgr:-unknown} · scope: ${scope}${nl}"
    out+="this session:    ${attempts} attempt"; [[ "$attempts" -ne 1 ]] && out+="s"; out+="${nl}"
    out+="${nl}"
    out+="Some updates did not go through. What failed, what the package manager said,${nl}"
    out+="and what might resolve it. nudge does not run these commands for you.${nl}"
    for list in system flatpak snap; do
        [[ -n "${_RETRY_F_CAUSE[$list]:-}" ]] || continue
        local cause="${_RETRY_F_CAUSE[$list]}" title="${_RETRY_LIST_TITLE[$list]}"
        [[ "$list" == "system" && -n "$pkgmgr" ]] && title+=" (${pkgmgr})"
        local -a names=()
        read -ra names <<< "${_RETRY_F_CULPRITS[$list]:-}"
        out+="${nl}"
        out+="── ${title} ──${nl}"
        out+="status:   failed · exit ${_RETRY_F_RC[$list]:-?} · ${_RETRY_F_ATTEMPTS[$list]:-1} attempt"
        [[ "${_RETRY_F_ATTEMPTS[$list]:-1}" -ne 1 ]] && out+="s"
        out+=" this session${nl}"
        if [[ "${_RETRY_F_STREAK[$list]:-0}" -gt 1 ]]; then
            out+="history:  the same update has failed ${_RETRY_F_STREAK[$list]} times"
            [[ -n "${_RETRY_F_SINCE[$list]:-}" ]] && out+=", since $(_retry_when "${_RETRY_F_SINCE[$list]}")"
            out+="${nl}"
        fi
        out+="cause:    $(retry_cause_headline "$cause" "$pkgmgr" "$list" "${names[@]}")${nl}"
        out+="meaning:  $(retry_cause_explain "$cause" "$pkgmgr" "$list")${nl}"
        case "$cause" in
            lock|repo-key|repo-unreachable|repo-tls) ;;
            *)
                if [[ "${#names[@]}" -gt 0 ]]; then
                    local shown="${names[*]:0:8}"
                    out+="named:    ${shown// /, }"
                    [[ "${#names[@]}" -gt 8 ]] && out+=", and $(( ${#names[@]} - 8 )) more"
                    out+="${nl}"
                fi ;;
        esac
        if [[ -n "${_RETRY_F_UNFETCHED[$list]:-}" ]]; then
            local -a unf=()
            read -ra unf <<< "${_RETRY_F_UNFETCHED[$list]}"
            local ushown="${unf[*]:0:8}"
            out+="download: failed for ${ushown// /, }"
            [[ "${#unf[@]}" -gt 8 ]] && out+=", and $(( ${#unf[@]} - 8 )) more"
            out+="${nl}"
        fi
        if [[ "${_RETRY_F_COUNT[$list]:-0}" -gt 0 ]]; then
            out+="selected: ${_RETRY_F_COUNT[$list]} update"; [[ "${_RETRY_F_COUNT[$list]}" -ne 1 ]] && out+="s"; out+=" in this list${nl}"
        fi
        if [[ -n "${_RETRY_F_EVIDENCE[$list]:-}" ]]; then
            out+="it said:${nl}"
            local line
            while IFS= read -r line; do
                [[ -n "$line" ]] && out+="    | ${line}${nl}"
            done <<< "${_RETRY_F_EVIDENCE[$list]}"
        fi
        out+="to resolve:${nl}"
        local step i=0
        while IFS= read -r step; do
            [[ -z "$step" ]] && continue
            i=$((i + 1))
            out+="    ${i}. ${step}${nl}"
        done < <(retry_cause_remedy "$cause" "$pkgmgr" "$list" "${names[@]}")
        [[ -n "${_RETRY_F_LOG[$list]:-}" ]] && out+="log:      $(retry_tilde "${_RETRY_F_LOG[$list]}")${nl}"
    done
    out+="${nl}"
    out+="When it goes through, nudge forgets it. Every update that keeps failing: nudge --failures${nl}"
    printf '%s' "$out"
}

# Usage: retry_report_save <pkgmgr> <scope> <attempts> -> the file written, 0600
retry_report_save() {
    _retry_mkdir "$RETRY_REPORT_DIR" || return 1
    local ts f
    ts=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo now)
    f="${RETRY_REPORT_DIR}/failure-${ts}.txt"
    local tmp
    tmp=$(umask 077 && mktemp "${f}.XXXXXX") || return 1
    retry_report_text "$@" > "$tmp" || { rm -f "$tmp"; return 1; }
    { printf '\n'; printf 'this report: %s\n' "$(retry_tilde "$f")"; } >> "$tmp"
    mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
    _retry_rotate "$RETRY_REPORT_DIR" 'failure-*.txt' "$RETRY_REPORT_MAX"
    _retry_rotate "$RETRY_LOG_DIR" 'upgrade-*.log' "$RETRY_LOG_MAX"
    printf '%s' "$f"
}

# The newest report, or 1
retry_report_latest() {
    local f
    f=$(find "$RETRY_REPORT_DIR" -maxdepth 1 -name 'failure-*.txt' -type f 2>/dev/null | LC_ALL=C sort | tail -1)
    [[ -n "$f" ]] || return 1
    printf '%s' "$f"
}

# A report path the dialogs may open: a private regular file of ours, in the reports directory
retry_report_trusted() {
    local f="${1:-}" owner mode real dir
    [[ -n "$f" && -f "$f" && ! -L "$f" ]] || return 1
    real=$(readlink -f "$f" 2>/dev/null) || return 1
    dir=$(readlink -f "$RETRY_REPORT_DIR" 2>/dev/null) || return 1
    [[ "$real" == "$dir"/failure-*.txt ]] || return 1
    owner=$(stat -c %u "$real" 2>/dev/null) || return 1
    mode=$(stat -c %a "$real" 2>/dev/null) || return 1
    [[ "$owner" == "$UID" && "$mode" == "600" ]]
}

# ============================================================
# nudge --failures
# ============================================================

# Usage: retry_failures_show [table|json]
retry_failures_show() {
    local format="${1:-table}" rows latest=""
    rows=$(retry_ledger_rows)
    latest=$(retry_report_latest 2>/dev/null) || latest=""
    if [[ "$format" == "json" ]]; then
        local json='{"failing":[' first=true l t c f la ca
        while IFS=$'\t' read -r l t c f la ca; do
            [[ -z "$l" ]] && continue
            [[ "$first" == "true" ]] && first=false || json+=","
            json+="{\"list\":\"$(json_escape "$l")\",\"target\":\"$(json_escape "$t")\",\"attempts\":${c},\"first\":\"$(json_escape "$f")\",\"last\":\"$(json_escape "$la")\",\"cause\":\"$(json_escape "$ca")\"}"
        done <<< "$rows"
        json+='],"latest_report":'
        if [[ -n "$latest" ]]; then json+="\"$(json_escape "$latest")\""; else json+="null"; fi
        json+='}'
        echo "$json"
        return 0
    fi
    if [[ -z "$rows" ]]; then
        echo "Nothing is failing: every update nudge tried went through, or none has been tried yet."
        [[ -n "$latest" ]] && echo "The last report is still here: $(retry_tilde "$latest")"
        return 0
    fi
    printf '%-8s  %-36s  %-8s  %-16s  %-16s  %s\n' "LIST" "UPDATE" "FAILED" "FIRST" "LAST" "CAUSE"
    printf '%s\n' "$(printf '%.0s─' {1..100})"
    local l t c f la ca
    while IFS=$'\t' read -r l t c f la ca; do
        [[ -z "$l" ]] && continue
        [[ "${#t}" -gt 36 ]] && t="${t:0:35}…"
        printf '%-8s  %-36s  %-8s  %-16s  %-16s  %s\n' "$l" "$t" "$c" "$(_retry_when "$f")" "$(_retry_when "$la")" "$ca"
    done <<< "$rows"
    if [[ -n "$latest" ]]; then
        echo ""
        cat "$latest" 2>/dev/null || true
    fi
    return 0
}

# Forget the ledger, the reports and the captured logs
retry_failures_clear() {
    local n=0
    [[ -f "$RETRY_LEDGER_FILE" ]] && n=$(_retry_ledger_read | grep -c '.' || true)
    retry_ledger_clear
    rm -f "$RETRY_REPORT_DIR"/failure-*.txt "$RETRY_LOG_DIR"/upgrade-*.log 2>/dev/null || true
    echo "Forgot ${n:-0} failing update(s), the reports and the captured logs."
}
