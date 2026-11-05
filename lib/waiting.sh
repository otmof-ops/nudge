#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/waiting.sh
# The waiting list: updates nudge knows it cannot install right now, because
# their download cannot be fetched (the repository does not answer from this
# network, its certificate does not verify, the mirror has not caught up).
# That is not the update failing, and nudge does not treat it as one.
#
# A standard update waits quietly: the session sets it aside and installs the
# rest, and nudge offers it again only once its download answers. Critical
# and security updates are listed here too, by severity, but they keep the
# loud path: offered every run, retried, counted in the failure ledger and
# reported (lib/retry.sh).

set -euo pipefail

WAITING_FILE="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}/waiting.tsv"
WAITING_RECHECK_DAYS=7   # after this long since its last try, apt has the last word again
WAITING_PROBE_MAX=24     # downloads probed per run, at most
WAITING_PROBE_TIMEOUT=6  # seconds per probe
WAITING_PROBE_BUDGET=20  # seconds all the probes of one run may take

# What the check found (set by waiting_hold_back)
PKG_WAITING_LIST=""      # the rows held back, in PKG_UPDATE_LIST's format
PKG_UPDATES_WAITING=0    # how many
PKG_WAITING_SNAP_LIST="" # the snaps held back while their app runs, in PKG_SNAP_LIST's format
PKG_SNAPS_WAITING=0      # how many
_WAITING_LAST_CODE=""    # the HTTP status of the last probe ("000": no answer at all)

declare -gA _WAITING_SEV_TITLE=([critical]="Critical" [security]="Security" [standard]="Standard")

_waiting_now() { date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'; }

# waiting.tsv, one row per update:
#   list  target  severity  version  cause  host  first  last  tries  via
# "via" is the download that holds it back when that is not its own (a new
# dependency). An unknown version, host or via is "-": read splits on a run
# of tabs, so an empty field would move the ones after it.
_waiting_valid() {
    local LC_ALL=C
    [[ "${1:-}" =~ ^(system|flatpak|snap)$ ]] || return 1
    [[ "${2:-}" =~ ^[A-Za-z0-9][A-Za-z0-9+._:/@-]{0,127}$ ]] || return 1
    [[ "${3:-}" =~ ^(critical|security|standard)$ ]] || return 1
    [[ "${4:-}" =~ ^[A-Za-z0-9.+:~_-]{1,64}$ ]] || return 1
    [[ "${5:-}" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || return 1
    [[ "${6:-}" =~ ^[A-Za-z0-9.-]{1,253}$ ]] || return 1
    [[ "${7:-}" =~ ^[0-9][0-9T:.+Z-]{0,39}$ ]] || return 1
    [[ "${8:-}" =~ ^[0-9][0-9T:.+Z-]{0,39}$ ]] || return 1
    [[ "${9:-}" =~ ^[1-9][0-9]{0,5}$ ]] || return 1
    [[ "${10:-}" == "-" || "${10:-}" =~ ^[A-Za-z0-9][A-Za-z0-9+._-]{0,127}(:[A-Za-z0-9_-]{1,32})?$ ]] || return 1
    return 0
}

_waiting_row() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}

# Every valid row, as it is in the file
_waiting_read() {
    [[ -f "$WAITING_FILE" && ! -L "$WAITING_FILE" ]] || return 0
    local l t s v c h f la n via
    while IFS=$'\t' read -r l t s v c h f la n via || [[ -n "$l" ]]; do
        _waiting_valid "$l" "$t" "$s" "$v" "$c" "$h" "$f" "$la" "$n" "$via" || continue
        _waiting_row "$l" "$t" "$s" "$v" "$c" "$h" "$f" "$la" "$n" "$via"
    done < "$WAITING_FILE"
}

# Replace the file with stdin, atomically and privately; an empty list removes it
_waiting_replace() {
    local dir tmp
    dir=$(dirname "$WAITING_FILE")
    [[ -d "$dir" ]] || ( umask 077; mkdir -p "$dir" ) 2>/dev/null || return 1
    if [[ -L "$WAITING_FILE" ]]; then
        log_warn "Refusing to write the waiting list through a symlink: $WAITING_FILE"
        return 1
    fi
    tmp=$(umask 077 && mktemp "${WAITING_FILE}.XXXXXX") || return 1
    cat > "$tmp" || { rm -f "$tmp"; return 1; }
    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp" "$WAITING_FILE" 2>/dev/null
        return 0
    fi
    mv -f "$tmp" "$WAITING_FILE" || { rm -f "$tmp"; return 1; }
}

# 0 when the list has any row at all
waiting_any() {
    [[ -n "$(_waiting_read | head -n 1)" ]]
}

# Usage: waiting_note <list> <cause> <<< "target|severity|version|host|via" lines
# These could not be downloaded this time: a new row, or another try on the
# old one. An empty version, host or via is allowed (it is kept as "-").
waiting_note() {
    local list="$1" cause="${2:-unknown}" now
    [[ "$cause" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || cause="unknown"
    now=$(_waiting_now)
    local -A sev=() ver=() host=() by=()
    local -a order=()
    local t s v h w
    while IFS='|' read -r t s v h w || [[ -n "$t" ]]; do
        [[ -n "$t" ]] || continue
        [[ "$s" =~ ^(critical|security|standard)$ ]] || s="standard"
        [[ -n "$v" ]] || v="-"
        [[ -n "$h" ]] || h="-"
        [[ -n "$w" ]] || w="-"
        if ! _waiting_valid "$list" "$t" "$s" "$v" "$cause" "$h" "$now" "$now" 1 "$w"; then
            # a version, host or via nudge would not keep is dropped, the update is not
            v="-"; h="-"; w="-"
            _waiting_valid "$list" "$t" "$s" "$v" "$cause" "$h" "$now" "$now" 1 "$w" || continue
        fi
        [[ -n "${sev[$t]+x}" ]] || order+=("$t")
        sev["$t"]="$s"; ver["$t"]="$v"; host["$t"]="$h"; by["$t"]="$w"
    done
    [[ "${#order[@]}" -gt 0 ]] || return 0
    local out="" l f la n c via
    local -A hit=()
    while IFS=$'\t' read -r l t s v c h f la n via; do
        if [[ "$l" == "$list" && -n "${sev[$t]+x}" ]]; then
            s="${sev[$t]}"; c="$cause"; la="$now"; n=$((n + 1)); via="${by[$t]}"; hit["$t"]=1
            [[ "${ver[$t]}" != "-" ]] && v="${ver[$t]}"
            [[ "${host[$t]}" != "-" ]] && h="${host[$t]}"
        fi
        out+=$(_waiting_row "$l" "$t" "$s" "$v" "$c" "$h" "$f" "$la" "$n" "$via")$'\n'
    done < <(_waiting_read)
    for t in "${order[@]}"; do
        [[ -n "${hit[$t]:-}" ]] && continue
        out+=$(_waiting_row "$list" "$t" "${sev[$t]}" "${ver[$t]}" "$cause" "${host[$t]}" "$now" "$now" 1 "${by[$t]}")$'\n'
    done
    printf '%s' "$out" | _waiting_replace
}

# Usage: _waiting_filter <list> <keep|drop> <<< targets — the rows of the list
# whose target is (drop) or is not (keep) among the given ones go
_waiting_filter() {
    local list="$1" mode="$2" t
    local -A named=()
    while IFS= read -r t || [[ -n "$t" ]]; do
        [[ -n "$t" ]] && named["$t"]=1
    done
    [[ -f "$WAITING_FILE" ]] || return 0
    [[ "$mode" == "drop" && "${#named[@]}" -eq 0 ]] && return 0
    local out="" l s v c h f la n via
    while IFS=$'\t' read -r l t s v c h f la n via; do
        if [[ "$l" == "$list" ]]; then
            if [[ "$mode" == "drop" ]]; then [[ -n "${named[$t]:-}" ]] && continue
            else [[ -z "${named[$t]:-}" ]] && continue; fi
        fi
        out+=$(_waiting_row "$l" "$t" "$s" "$v" "$c" "$h" "$f" "$la" "$n" "$via")$'\n'
    done < <(_waiting_read)
    printf '%s' "$out" | _waiting_replace
}

# Usage: waiting_forget <list> <<< targets — they went in: their rows go
waiting_forget() { _waiting_filter "$1" drop; }

# Usage: waiting_keep_pending <list> <<< pending targets — rows of this list
# for updates no longer pending (installed some other way, or gone) go. An
# empty stdin means nothing in the list is pending: every row of it goes.
waiting_keep_pending() { _waiting_filter "$1" keep; }

# Every row, critical first, then security, then standard, by name
waiting_rows() {
    local l t s v c h f la n via rank
    while IFS=$'\t' read -r l t s v c h f la n via; do
        case "$s" in critical) rank=1 ;; security) rank=2 ;; *) rank=3 ;; esac
        printf '%s\t' "$rank"
        _waiting_row "$l" "$t" "$s" "$v" "$c" "$h" "$f" "$la" "$n" "$via"
    done < <(_waiting_read) | LC_ALL=C sort -t$'\t' -k1,1n -k2,2 -k3,3 | cut -f2-
}

waiting_clear() {
    local n=0
    n=$(_waiting_read | grep -c '.' || true)
    rm -f "$WAITING_FILE" 2>/dev/null || true
    echo "Forgot ${n:-0} waiting update(s). nudge will offer them again."
}

# ============================================================
# Does the download answer now?
# ============================================================

# Usage: _waiting_uris <names...> -> "name:arch<TAB>url<TAB>size" for every
# download apt knows, from one apt-get call. A name apt does not know is left
# out (apt-get still prints the others).
_waiting_uris() {
    [[ $# -gt 0 ]] || return 0
    command -v apt-get >/dev/null 2>&1 || return 1
    local dir out
    dir=$(mktemp -d 2>/dev/null) || return 1
    out=$(cd "$dir" && LC_ALL=C timeout 30 apt-get download --print-uris -- "$@" 2>/dev/null) || true
    rmdir "$dir" 2>/dev/null || true
    local LC_ALL=C line file name arch
    local re="^'(https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?/[A-Za-z0-9._~%+/:@=-]*)' ([A-Za-z0-9._~%+:-]+\\.deb) ([0-9]{1,15}) "
    while IFS= read -r line; do
        [[ "$line" =~ $re ]] || continue
        file="${BASH_REMATCH[3]%.deb}"
        [[ "$file" == *_*_* ]] || continue
        name="${file%%_*}"
        arch="${file##*_}"
        printf '%s:%s\t%s\t%s\n' "$name" "$arch" "${BASH_REMATCH[1]}" "${BASH_REMATCH[4]}"
    done <<< "$out"
}

# 0 when apt fetches in a way a probe of nudge's own would not: through a
# proxy, with a certificate store or client certificate of its own, or
# without verifying the peer. nudge cannot tell then.
_waiting_apt_unprobeable() {
    command -v apt-config >/dev/null 2>&1 || return 1
    local dump
    dump=$(apt-config dump 2>/dev/null) || return 1
    grep -iE '^Acquire::(https?::)?Proxy(::[^ ]+)? "[^"]+"' <<< "$dump" | grep -qviE '"(DIRECT|false)"' && return 0
    grep -qiE '^Acquire::(https?::)?Proxy-Auto-Detect "[^"]+"|^Acquire::https?::ProxyAutoDetect "(true|yes|1)"' <<< "$dump" && return 0
    grep -qiE '^Acquire::https::([^ ]+::)?(CaInfo|CaPath|SslCert|SslKey|CrlFile|IssuerCert) "[^"]+"' <<< "$dump" && return 0
    grep -qiE '^Acquire::https::([^ ]+::)?Verify-(Peer|Host) "(false|no|0)"' <<< "$dump" && return 0
    return 1
}

# Usage: _waiting_fetch <url> [size] -> 0 the file answers, 1 it does not, 2 nudge cannot tell
# One byte of it, the way apt would ask: redirects followed (http and https
# only), the certificate verified, nothing written. A server that answers
# with something else (a captive portal's page, a block page) gives the
# wrong length, and that is not the file. Sets _WAITING_LAST_CODE.
_waiting_fetch() {
    local url="$1" size="${2:-}" out code rest total
    _WAITING_LAST_CODE="000"
    if command -v curl >/dev/null 2>&1; then
        local try began
        for try in 1 2; do
            began=$SECONDS
            out=$(curl -s -o /dev/null -D - -r 0-0 -L --max-redirs 5 --proto '=http,https' --proto-redir '=http,https' \
                --max-filesize 65536 --max-time "$WAITING_PROBE_TIMEOUT" -w '\nnudge-code=%{http_code}\n' -- "$url" 2>/dev/null) || true
            code=$(sed -n 's/^nudge-code=//p' <<< "$out" | tail -n 1)
            [[ "$code" =~ ^[0-9]{3}$ ]] || code="000"
            # no answer at all, and quickly (not a timeout): a hiccup gets one more go
            [[ "$code" == "000" && "$try" -eq 1 && $((SECONDS - began)) -lt 3 ]] || break
        done
        _WAITING_LAST_CODE="$code"
        # the length the last response gives for the whole file
        rest=$(tr -d '\r' <<< "$out" | awk '
            /^HTTP\// { range = ""; size = "" }
            tolower($1) == "content-range:" { range = $3 }
            tolower($1) == "content-length:" { size = $2 }
            END { sub(/^.*\//, "", range); print range "|" size }')
        case "$code" in
            206) total="${rest%%|*}" ;;
            200) total="${rest##*|}" ;;
            401|403|407) return 2 ;;
            *) return 1 ;;
        esac
        [[ -z "$size" || -z "$total" || "$total" == "$size" ]] && return 0
        return 1
    fi
    if command -v wget >/dev/null 2>&1; then
        if wget -q --spider --max-redirect=5 --timeout="$WAITING_PROBE_TIMEOUT" --tries=1 -- "$url" >/dev/null 2>&1; then
            _WAITING_LAST_CODE="200"
            return 0
        fi
        return 1
    fi
    return 2
}

# 0 when an ISO timestamp is more than WAITING_RECHECK_DAYS old (or unreadable)
_waiting_stale() {
    local ts="${1:-}" ts_then now
    ts_then=$(date -d "$ts" +%s 2>/dev/null) || return 0
    now=$(date +%s)
    [[ $((now - ts_then)) -gt $((WAITING_RECHECK_DAYS * 86400)) ]]
}

# The target an update row is called by: name, or name:arch for another architecture
# Usage: _waiting_row_target <row> <native arch>
_waiting_row_target() { pkgmgr_row_target "$@"; }

# ============================================================
# The check: hold back what is still waiting
# ============================================================

# Before the prompt, with PKG_UPDATE_LIST built: the standard updates on the
# waiting list whose download still does not answer come out of
# PKG_UPDATE_LIST and the count, into PKG_WAITING_LIST. Critical and security
# updates are never held back. A week after its last try an update gets its
# turn with apt again: one nudge could not probe goes back in the offer, and
# one whose probe said no rides along when something else is offered anyway
# (it never makes a prompt by itself). Rows for updates no longer pending go.
waiting_hold_back() {
    PKG_WAITING_LIST=""
    PKG_UPDATES_WAITING=0
    PKG_WAITING_SNAP_LIST=""
    PKG_SNAPS_WAITING=0
    waiting_any || return 0
    _waiting_hold_back_snaps
    _waiting_hold_back_system
}

# 0 while a process of the snap's own runs (snap apps run from /snap/<name>/)
_waiting_snap_running() {
    local LC_ALL=C
    [[ "${1:-}" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || return 1
    pgrep -f "^/snap/${1}/" >/dev/null 2>&1
}

# Snaps on the waiting list because snapd refused them while their app ran:
# while it still runs, the snap stays out of the count and the dialog (snapd
# would refuse it again). The evidence is snapd's own refusal, never a guess:
# a snap that never was refused (snapd itself, a base) is never held back.
_waiting_hold_back_snaps() {
    local l t s v c h f la n via line name
    [[ -n "$(_waiting_read | awk -F'\t' '$1 == "snap"' | head -n 1)" ]] || return 0
    # a snap that waited goes once it is no longer pending
    cut -d'|' -f1 <<< "${PKG_SNAP_LIST:-}" | waiting_keep_pending snap \
        || log_warn "The waiting list could not be written: $WAITING_FILE"
    [[ -n "${PKG_SNAP_LIST:-}" && "${SET_ASIDE_STANDARD:-true}" == "true" ]] || return 0
    local -A running=()
    while IFS=$'\t' read -r l t s v c h f la n via; do
        [[ "$l" == "snap" && "$c" == "snap-running" ]] || continue
        _waiting_snap_running "$t" && running["$t"]=1
    done < <(_waiting_read)
    [[ "${#running[@]}" -gt 0 ]] || return 0
    local kept=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        name="${line%%|*}"
        if [[ -n "${running[$name]:-}" ]]; then
            PKG_WAITING_SNAP_LIST+="${line}"$'\n'
            PKG_SNAPS_WAITING=$((PKG_SNAPS_WAITING + 1))
        else
            kept+="${line}"$'\n'
        fi
    done <<< "$PKG_SNAP_LIST"
    PKG_SNAP_LIST="${kept%$'\n'}"
    PKG_WAITING_SNAP_LIST="${PKG_WAITING_SNAP_LIST%$'\n'}"
    PKG_UPDATES_SNAP=$(( ${PKG_UPDATES_SNAP:-0} - PKG_SNAPS_WAITING ))
    [[ "$PKG_UPDATES_SNAP" -lt 0 ]] && PKG_UPDATES_SNAP=0
    log_info "Held back ${PKG_SNAPS_WAITING} snap(s) whose app is still running"
    return 0
}

# The snaps held back, space-separated (the session file's waiting_snap= line)
waiting_held_snaps() {
    [[ -n "${PKG_WAITING_SNAP_LIST:-}" ]] || return 0
    cut -d'|' -f1 <<< "$PKG_WAITING_SNAP_LIST" | tr '\n' ' ' | sed 's/ $//'
}

# The system part of the check (see waiting_hold_back)
_waiting_hold_back_system() {
    PKG_WAITING_LIST=""
    PKG_UPDATES_WAITING=0
    waiting_any || return 0
    local native line t
    native=$(pkgmgr_native_arch 2>/dev/null) || native=""
    local -a pend_targets=()
    local -A row_of=()
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        t=$(_waiting_row_target "$line" "$native")
        pend_targets+=("$t")
        row_of["$t"]="$line"
    done <<< "${PKG_UPDATE_LIST:-}"
    # what the upgrade leaves for later is still pending, and keeps its row
    local -a still=("${pend_targets[@]}")
    while IFS='|' read -r t _; do
        [[ -n "$t" ]] && still+=("$t")
    done <<< "${PKG_LATER_LIST:-}"
    printf '%s\n' "${still[@]}" | waiting_keep_pending system \
        || log_warn "The waiting list could not be written: $WAITING_FILE"
    [[ "${#pend_targets[@]}" -gt 0 ]] || return 0
    [[ "${SET_ASIDE_STANDARD:-true}" == "true" ]] || return 0

    # the standard updates on the list, and the download each one waits for
    local -a cand=() names=()
    local -A probe_of=() last_of=() named=()
    local l s v c h f la n via priority
    while IFS=$'\t' read -r l t s v c h f la n via; do
        [[ "$l" == "system" && -n "${row_of[$t]:-}" ]] || continue
        IFS='|' read -r _ _ _ priority _ _ <<< "${row_of[$t]}"
        # what the update is now decides, not what it was when it was noted
        [[ "$priority" == "CRITICAL" || "$priority" == "SECURITY" ]] && continue
        cand+=("$t")
        last_of["$t"]="$la"
        probe_of["$t"]="$t"
        [[ "$via" != "-" ]] && probe_of["$t"]="$via"
        [[ -n "${named[${probe_of[$t]}]:-}" ]] || { names+=("${probe_of[$t]}"); named["${probe_of[$t]}"]=1; }
    done < <(_waiting_read)
    [[ "${#cand[@]}" -gt 0 ]] || return 0

    # where each of those downloads comes from: one question to apt
    local -A url_of=() size_of=()
    local can_probe=false key url size
    if [[ "${DETECTED_PKGMGR:-}" == "apt" ]] && ! _waiting_apt_unprobeable; then
        can_probe=true
        while IFS=$'\t' read -r key url size; do
            [[ -n "$key" ]] || continue
            url_of["$key"]="$url"; size_of["$key"]="$size"
            # by its name alone too, for this architecture or for all
            if [[ "${key##*:}" == "$native" || "${key##*:}" == "all" || -z "${url_of[${key%%:*}]:-}" ]]; then
                url_of["${key%%:*}"]="$url"; size_of["${key%%:*}"]="$size"
            fi
        done < <(_waiting_uris "${names[@]}" || true)
    fi

    # one probe per download, one failure per host is enough, and a budget
    local -A verdict=() dead=()
    local probes=0 started=$SECONDS rc p host
    for t in "${cand[@]}"; do
        p="${probe_of[$t]}"
        url="${url_of[$p]:-}"
        rc=2
        if [[ "$can_probe" == "true" && -n "$url" ]]; then
            host="${url#*://}"; host="${host%%/*}"
            if [[ -n "${dead[$host]:-}" ]]; then
                rc=1
            elif [[ "$probes" -lt "$WAITING_PROBE_MAX" && $((SECONDS - started)) -lt "$WAITING_PROBE_BUDGET" ]]; then
                probes=$((probes + 1))
                rc=0; _waiting_fetch "$url" "${size_of[$p]:-}" || rc=$?
                [[ "$rc" -eq 1 && "$_WAITING_LAST_CODE" == "000" ]] && dead["$host"]=1
            fi
        fi
        verdict["$t"]="$rc"
    done

    local -A hold=() soft=()
    for t in "${cand[@]}"; do
        case "${verdict[$t]}" in
            0) log_info "Waiting update $t can be downloaded again: offering it" ;;
            1) if _waiting_stale "${last_of[$t]}"; then soft["$t"]=1; else hold["$t"]=1; fi ;;
            *) _waiting_stale "${last_of[$t]}" || hold["$t"]=1 ;;
        esac
    done
    if [[ "${#soft[@]}" -gt 0 ]]; then
        local others=$(( ${#pend_targets[@]} - ${#hold[@]} - ${#soft[@]} + ${PKG_UPDATES_FLATPAK:-0} + ${PKG_UPDATES_SNAP:-0} ))
        for t in "${!soft[@]}"; do
            if [[ "$others" -gt 0 ]]; then
                log_info "Waiting update $t rides along: a week has passed, apt gets to try it again"
            else
                hold["$t"]=1
            fi
        done
    fi
    [[ "${#hold[@]}" -gt 0 ]] || return 0

    local kept=""
    local -a offered=()
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        t=$(_waiting_row_target "$line" "$native")
        if [[ -n "${hold[$t]:-}" ]]; then
            PKG_WAITING_LIST+="${line}"$'\n'
            PKG_UPDATES_WAITING=$((PKG_UPDATES_WAITING + 1))
        else
            kept+="${line}"$'\n'
            offered+=("$t")
        fi
    done <<< "$PKG_UPDATE_LIST"
    PKG_UPDATE_LIST="${kept%$'\n'}"
    PKG_WAITING_LIST="${PKG_WAITING_LIST%$'\n'}"
    _waiting_recount "$native" "${offered[@]}"
    log_info "Held back ${PKG_UPDATES_WAITING} waiting update(s): their download still does not answer"
    return 0
}

# The count without what is held back: every row offered is one the upgrade
# installs now (pkgmgr_list_updates), so what is held back simply comes off
# Usage: _waiting_recount <native arch> [offered targets...]
_waiting_recount() {
    local total=$(( ${PKG_UPDATES_TOTAL:-0} - PKG_UPDATES_WAITING ))
    [[ "$total" -lt 0 ]] && total=0
    PKG_UPDATES_TOTAL="$total"
}

# The targets held back, space-separated (the session file's waiting= line)
waiting_held_targets() {
    local line native out=""
    [[ -n "$PKG_WAITING_LIST" ]] || return 0
    native=$(pkgmgr_native_arch 2>/dev/null) || native=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        out+="${out:+ }$(_waiting_row_target "$line" "$native")"
    done <<< "$PKG_WAITING_LIST"
    printf '%s' "$out"
}

# ============================================================
# nudge --waiting
# ============================================================

# "2026-10-24 19:40" from an ISO timestamp
_waiting_when() {
    local ts="${1:-}"
    ts="${ts:0:16}"
    printf '%s' "${ts/T/ }"
}

# Why, in a few words
_waiting_why() {
    local cause="$1" src="$2" via="${3:--}"
    local where="its source" out
    [[ -n "$src" && "$src" != "-" ]] && where="$src"
    case "$cause" in
        repo-tls)         out="${where}: certificate does not verify from here" ;;
        repo-unreachable) out="${where} does not answer" ;;
        network)          out="${where} could not be reached" ;;
        mirror-stale)     out="${where} has not caught up yet" ;;
        index-corrupt)    out="${where} sent a file that did not match" ;;
        snap-running)     out="waits until it is closed: a running snap is not refreshed" ;;
        *)                out="${where}: the download failed" ;;
    esac
    [[ "$via" != "-" ]] && out+=" (it needs ${via%%:*})"
    printf '%s' "$out"
}

# Usage: waiting_show [table|json]
waiting_show() {
    local format="${1:-table}" rows
    rows=$(waiting_rows)
    local l t s v c h f la n via
    if [[ "$format" == "json" ]]; then
        local json='{"waiting":[' first=true
        while IFS=$'\t' read -r l t s v c h f la n via; do
            [[ -n "$l" ]] || continue
            [[ "$first" == "true" ]] && first=false || json+=","
            [[ "$v" == "-" ]] && v=""
            [[ "$h" == "-" ]] && h=""
            [[ "$via" == "-" ]] && via=""
            json+="{\"list\":\"$(json_escape "$l")\",\"target\":\"$(json_escape "$t")\",\"severity\":\"$(json_escape "$s")\""
            json+=",\"version\":\"$(json_escape "$v")\",\"cause\":\"$(json_escape "$c")\",\"host\":\"$(json_escape "$h")\""
            json+=",\"needs\":\"$(json_escape "$via")\",\"first\":\"$(json_escape "$f")\",\"last\":\"$(json_escape "$la")\",\"tries\":${n}"
            if [[ "$s" == "standard" ]]; then json+=',"policy":"waits"'; else json+=',"policy":"retried"'; fi
            json+="}"
        done <<< "$rows"
        json+=']}'
        echo "$json"
        return 0
    fi
    if [[ -z "$rows" ]]; then
        echo "Nothing is waiting: every update nudge offered could be downloaded."
        return 0
    fi
    local current="" note
    while IFS=$'\t' read -r l t s v c h f la n via; do
        [[ -n "$l" ]] || continue
        if [[ "$s" != "$current" ]]; then
            [[ -n "$current" ]] && echo ""
            current="$s"
            if [[ "$s" == "standard" ]]; then
                note="waiting quietly: offered again once the download answers"
            else
                note="important: offered and retried every run (nudge --failures)"
            fi
            printf '%s · %s\n' "${_WAITING_SEV_TITLE[$s]}" "$note"
        fi
        [[ "${#t}" -gt 32 ]] && t="${t:0:31}…"
        [[ "$v" == "-" ]] && v=""
        printf '  %-32s  %-18s  %s · since %s\n' "$t" "$v" "$(_waiting_why "$c" "$h" "$via")" "$(_waiting_when "$f")"
    done <<< "$rows"
    return 0
}
