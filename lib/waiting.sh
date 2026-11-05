#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/waiting.sh
# The waiting list: updates nudge knows it cannot install right now, because
# their download cannot be fetched (the repository does not answer from this
# network, its certificate does not verify, the mirror has not caught up).
# That is not the update failing, and nudge does not treat it as one.
#
# Every such update is kept here with its severity. A standard update waits
# quietly: the session sets it aside and installs the rest, and nudge offers
# it again only once its download answers. A critical or security update is
# listed too, but it keeps the loud path: offered every run, retried, counted
# in the failure ledger and reported (lib/retry.sh).

set -euo pipefail

WAITING_FILE="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}/waiting.tsv"
WAITING_RECHECK_DAYS=7   # an update nudge could not probe rides along again after this long
WAITING_PROBE_MAX=12     # downloads probed per run, at most
WAITING_PROBE_TIMEOUT=6  # seconds per probe

# What the check found (set by waiting_hold_back)
PKG_WAITING_LIST=""      # the rows held back, in PKG_UPDATE_LIST's format
PKG_UPDATES_WAITING=0    # how many

declare -gA _WAITING_SEV_TITLE=([critical]="Critical" [security]="Security" [standard]="Standard")

_waiting_now() { date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'; }

# waiting.tsv: list <TAB> target <TAB> severity <TAB> version <TAB> cause <TAB> host <TAB> first <TAB> last <TAB> tries
# An unknown version or host is "-": read splits on a run of tabs, so an empty
# field would move the ones after it.
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
    return 0
}

# Every valid row, as it is in the file
_waiting_read() {
    [[ -f "$WAITING_FILE" && ! -L "$WAITING_FILE" ]] || return 0
    local l t s v c h f la n
    while IFS=$'\t' read -r l t s v c h f la n || [[ -n "$l" ]]; do
        _waiting_valid "$l" "$t" "$s" "$v" "$c" "$h" "$f" "$la" "$n" || continue
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$l" "$t" "$s" "$v" "$c" "$h" "$f" "$la" "$n"
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

# Usage: waiting_note <list> <cause> <<< "target|severity|version|host" lines
# These could not be downloaded this time: a new row, or another try on the
# old one. An empty version or host is allowed (it is kept as "-").
waiting_note() {
    local list="$1" cause="${2:-unknown}" now line
    [[ "$cause" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || cause="unknown"
    now=$(_waiting_now)
    local -A sev=() ver=() host=()
    local -a order=()
    local t s v h
    while IFS='|' read -r t s v h || [[ -n "$t" ]]; do
        [[ -n "$t" ]] || continue
        [[ "$s" =~ ^(critical|security|standard)$ ]] || s="standard"
        [[ -n "$v" ]] || v="-"
        [[ -n "$h" ]] || h="-"
        _waiting_valid "$list" "$t" "$s" "$v" "$cause" "$h" "$now" "$now" 1 || {
            # a version or host nudge would not keep is dropped, the update is not
            v="-"; h="-"
            _waiting_valid "$list" "$t" "$s" "$v" "$cause" "$h" "$now" "$now" 1 || continue
        }
        [[ -n "${sev[$t]+x}" ]] || order+=("$t")
        sev["$t"]="$s"; ver["$t"]="$v"; host["$t"]="$h"
    done
    [[ "${#order[@]}" -gt 0 ]] || return 0
    local out="" l f la n c
    local -A hit=()
    while IFS=$'\t' read -r l t s v c h f la n; do
        if [[ "$l" == "$list" && -n "${sev[$t]+x}" ]]; then
            s="${sev[$t]}"; c="$cause"; la="$now"; n=$((n + 1)); hit["$t"]=1
            [[ "${ver[$t]}" != "-" ]] && v="${ver[$t]}"
            [[ "${host[$t]}" != "-" ]] && h="${host[$t]}"
        fi
        out+="${l}"$'\t'"${t}"$'\t'"${s}"$'\t'"${v}"$'\t'"${c}"$'\t'"${h}"$'\t'"${f}"$'\t'"${la}"$'\t'"${n}"$'\n'
    done < <(_waiting_read)
    for t in "${order[@]}"; do
        [[ -n "${hit[$t]:-}" ]] && continue
        out+="${list}"$'\t'"${t}"$'\t'"${sev[$t]}"$'\t'"${ver[$t]}"$'\t'"${cause}"$'\t'"${host[$t]}"$'\t'"${now}"$'\t'"${now}"$'\t'"1"$'\n'
    done
    printf '%s' "$out" | _waiting_replace
}

# Usage: waiting_forget <list> <<< targets — they went in: their rows go
waiting_forget() {
    local list="$1" t
    local -A drop=()
    while IFS= read -r t || [[ -n "$t" ]]; do
        [[ -n "$t" ]] && drop["$t"]=1
    done
    [[ "${#drop[@]}" -gt 0 && -f "$WAITING_FILE" ]] || return 0
    local out="" l s v c h f la n
    while IFS=$'\t' read -r l t s v c h f la n; do
        [[ "$l" == "$list" && -n "${drop[$t]:-}" ]] && continue
        out+="${l}"$'\t'"${t}"$'\t'"${s}"$'\t'"${v}"$'\t'"${c}"$'\t'"${h}"$'\t'"${f}"$'\t'"${la}"$'\t'"${n}"$'\n'
    done < <(_waiting_read)
    printf '%s' "$out" | _waiting_replace
}

# Usage: waiting_keep_pending <list> <<< pending targets — rows of this list
# for updates no longer pending (installed some other way, or gone) go. An
# empty stdin means nothing in the list is pending: every row of it goes.
waiting_keep_pending() {
    local list="$1" t
    local -A pending=()
    while IFS= read -r t || [[ -n "$t" ]]; do
        [[ -n "$t" ]] && pending["$t"]=1
    done
    [[ -f "$WAITING_FILE" ]] || return 0
    local out="" l s v c h f la n
    while IFS=$'\t' read -r l t s v c h f la n; do
        [[ "$l" == "$list" && -z "${pending[$t]:-}" ]] && continue
        out+="${l}"$'\t'"${t}"$'\t'"${s}"$'\t'"${v}"$'\t'"${c}"$'\t'"${h}"$'\t'"${f}"$'\t'"${la}"$'\t'"${n}"$'\n'
    done < <(_waiting_read)
    printf '%s' "$out" | _waiting_replace
}

# Every row, critical first, then security, then standard, by name
waiting_rows() {
    local l t s v c h f la n rank
    while IFS=$'\t' read -r l t s v c h f la n; do
        case "$s" in critical) rank=1 ;; security) rank=2 ;; *) rank=3 ;; esac
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rank" "$l" "$t" "$s" "$v" "$c" "$h" "$f" "$la" "$n"
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

# The URL apt would fetch the candidate of one target from, or 1
_waiting_uri() {
    local target="$1" dir out uri
    command -v apt-get >/dev/null 2>&1 || return 1
    dir=$(mktemp -d 2>/dev/null) || return 1
    out=$(cd "$dir" && LC_ALL=C timeout 20 apt-get download --print-uris -- "$target" 2>/dev/null | head -n 1) || out=""
    rmdir "$dir" 2>/dev/null || true
    uri="${out%%\' *}"
    uri="${uri#\'}"
    local LC_ALL=C
    [[ "$uri" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?/[A-Za-z0-9._~%+/:@=-]*$ ]] || return 1
    printf '%s' "$uri"
}

# 0 when apt is set to go through a proxy: a probe of nudge's own would not take it
_waiting_apt_proxied() {
    command -v apt-config >/dev/null 2>&1 || return 1
    local p
    p=$(apt-config dump 2>/dev/null | grep -iE '^Acquire::(https?::)?Proxy(::[^ ]+)? "[^"]+"' \
        | grep -viE '"(DIRECT|false)"' | head -n 1) || p=""
    [[ -n "$p" ]]
}

# Usage: _waiting_fetch <url> -> 0 it answers, 1 it does not, 2 nudge cannot tell
# One byte of the file, the way apt would ask for it: redirects followed, the
# certificate verified, nothing written anywhere.
_waiting_fetch() {
    local url="$1" code=""
    if command -v curl >/dev/null 2>&1; then
        code=$(curl -s -o /dev/null -r 0-0 -L --max-redirs 5 --proto '=http,https' \
            --max-time "$WAITING_PROBE_TIMEOUT" -w '%{http_code}' -- "$url" 2>/dev/null) || code="000"
        [[ "$code" =~ ^2[0-9][0-9]$ ]] && return 0
        return 1
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q --spider --max-redirect=5 --timeout="$WAITING_PROBE_TIMEOUT" --tries=1 -- "$url" >/dev/null 2>&1 && return 0
        return 1
    fi
    return 2
}

# Usage: waiting_probe <target> -> 0 its download answers now, 1 it still does
# not, 2 nudge cannot tell (no apt, no curl or wget, a proxy only apt knows)
waiting_probe() {
    local target="$1" uri
    [[ "${DETECTED_PKGMGR:-}" == "apt" ]] || return 2
    _waiting_apt_proxied && return 2
    uri=$(_waiting_uri "$target") || return 2
    _waiting_fetch "$uri"
}

# 0 when an ISO timestamp is more than WAITING_RECHECK_DAYS old (or unreadable)
_waiting_stale() {
    local ts="${1:-}" ts_then now
    ts_then=$(date -d "$ts" +%s 2>/dev/null) || return 0
    now=$(date +%s)
    [[ $((now - ts_then)) -gt $((WAITING_RECHECK_DAYS * 86400)) ]]
}

# ============================================================
# The check: hold back what is still waiting
# ============================================================

# Before the prompt: the standard updates on the waiting list whose download
# still does not answer come out of PKG_UPDATE_LIST and the count, into
# PKG_WAITING_LIST. Critical and security updates are never held back. An
# update nudge cannot probe rides along once WAITING_RECHECK_DAYS have passed
# since it was last tried. Rows for updates no longer pending are dropped.
waiting_hold_back() {
    PKG_WAITING_LIST=""
    PKG_UPDATES_WAITING=0
    waiting_any || return 0
    if [[ -z "${PKG_UPDATE_LIST:-}" ]]; then
        # nothing pending in the system list: what waited there went in some other way
        [[ "${PKG_UPDATES_TOTAL:-0}" -eq 0 ]] && waiting_keep_pending system < /dev/null
        return 0
    fi
    local native line name priority arch target
    native=$(pkgmgr_native_arch 2>/dev/null) || native=""
    local -a pend_targets=()
    local -A row_of=()
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r name _ _ _ arch _ <<< "$line"
        target="$name"
        if [[ -n "$arch" && -n "$native" && "$arch" != "$native" && "$arch" != "all" && "${DETECTED_PKGMGR:-}" == "apt" ]]; then
            target="${name}:${arch}"
        fi
        pend_targets+=("$target")
        row_of["$target"]="$line"
    done <<< "$PKG_UPDATE_LIST"
    printf '%s\n' "${pend_targets[@]}" | waiting_keep_pending system \
        || log_warn "The waiting list could not be written: $WAITING_FILE"
    [[ "${SET_ASIDE_STANDARD:-true}" == "true" ]] || return 0

    local -A hold=()
    local probes=0 rc l t s v c h f la n
    while IFS=$'\t' read -r l t s v c h f la n; do
        [[ "$l" == "system" && -n "${row_of[$t]:-}" ]] || continue
        IFS='|' read -r _ _ _ priority _ _ <<< "${row_of[$t]}"
        # what the update is now decides, not what it was when it was noted
        [[ "$priority" == "CRITICAL" || "$priority" == "SECURITY" ]] && continue
        rc=2
        if [[ "$probes" -lt "$WAITING_PROBE_MAX" ]]; then
            probes=$((probes + 1))
            rc=0; waiting_probe "$t" || rc=$?
        fi
        case "$rc" in
            0) log_info "Waiting update $t can be downloaded again: offering it" ;;
            1) hold["$t"]=1 ;;
            *) _waiting_stale "$la" || hold["$t"]=1 ;;
        esac
    done < <(_waiting_read)
    [[ "${#hold[@]}" -gt 0 ]] || return 0

    local kept=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r name _ _ _ arch _ <<< "$line"
        target="$name"
        if [[ -n "$arch" && -n "$native" && "$arch" != "$native" && "$arch" != "all" && "${DETECTED_PKGMGR:-}" == "apt" ]]; then
            target="${name}:${arch}"
        fi
        if [[ -n "${hold[$target]:-}" ]]; then
            PKG_WAITING_LIST+="${line}"$'\n'
            PKG_UPDATES_WAITING=$((PKG_UPDATES_WAITING + 1))
        else
            kept+="${line}"$'\n'
        fi
    done <<< "$PKG_UPDATE_LIST"
    PKG_UPDATE_LIST="${kept%$'\n'}"
    PKG_WAITING_LIST="${PKG_WAITING_LIST%$'\n'}"
    PKG_UPDATES_TOTAL=$(( ${PKG_UPDATES_TOTAL:-0} - PKG_UPDATES_WAITING ))
    [[ "$PKG_UPDATES_TOTAL" -lt 0 ]] && PKG_UPDATES_TOTAL=0
    log_info "Held back ${PKG_UPDATES_WAITING} waiting update(s): their download still does not answer"
    return 0
}

# The targets held back, space-separated (the session file's waiting= line)
waiting_held_targets() {
    local line name arch target native out=""
    [[ -n "$PKG_WAITING_LIST" ]] || return 0
    native=$(pkgmgr_native_arch 2>/dev/null) || native=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r name _ _ _ arch _ <<< "$line"
        target="$name"
        if [[ -n "$arch" && -n "$native" && "$arch" != "$native" && "$arch" != "all" && "${DETECTED_PKGMGR:-}" == "apt" ]]; then
            target="${name}:${arch}"
        fi
        out+="${out:+ }${target}"
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
    local cause="$1" src="$2"
    local where="its source"
    [[ -n "$src" && "$src" != "-" ]] && where="$src"
    case "$cause" in
        repo-tls)         printf '%s: certificate does not verify from here' "$where" ;;
        repo-unreachable) printf '%s does not answer' "$where" ;;
        network)          printf '%s could not be reached' "$where" ;;
        mirror-stale)     printf '%s has not caught up yet' "$where" ;;
        index-corrupt)    printf '%s sent a file that did not match' "$where" ;;
        *)                printf '%s: the download failed' "$where" ;;
    esac
}

# Usage: waiting_show [table|json]
waiting_show() {
    local format="${1:-table}" rows
    rows=$(waiting_rows)
    local l t s v c h f la n
    if [[ "$format" == "json" ]]; then
        local json='{"waiting":[' first=true
        while IFS=$'\t' read -r l t s v c h f la n; do
            [[ -n "$l" ]] || continue
            [[ "$first" == "true" ]] && first=false || json+=","
            json+="{\"list\":\"$(json_escape "$l")\",\"target\":\"$(json_escape "$t")\",\"severity\":\"$(json_escape "$s")\""
            [[ "$v" == "-" ]] && v=""
            [[ "$h" == "-" ]] && h=""
            json+=",\"version\":\"$(json_escape "$v")\",\"cause\":\"$(json_escape "$c")\",\"host\":\"$(json_escape "$h")\""
            json+=",\"first\":\"$(json_escape "$f")\",\"last\":\"$(json_escape "$la")\",\"tries\":${n}"
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
    while IFS=$'\t' read -r l t s v c h f la n; do
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
        printf '  %-32s  %-18s  %s · since %s\n' "$t" "$v" "$(_waiting_why "$c" "$h")" "$(_waiting_when "$f")"
    done <<< "$rows"
    return 0
}
