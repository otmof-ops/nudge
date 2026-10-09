#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/dialog.sh
# What the dialogs show, and the pickers. kdialog gets Qt rich text with the
# Nudge Bunny drawn in (share/mascot, installed beside the modules), zenity
# gets Pango markup, the passive backends plain text. The scope picker asks
# what to install (everything, the important ones, one source, or one by one
# in the terminal) and the deferral picker asks when to come back.

set -euo pipefail

# Where the mascot SVGs live; nudge.sh resolves it, tests set it
NUDGE_MASCOT_DIR="${NUDGE_MASCOT_DIR:-}"

# Set by nudge.sh once the package lists are loaded; until then the dialogs
# show the plain message they are handed
_DIALOG_READY="${_DIALOG_READY:-false}"

# Temporary files the dialogs make (the full-list box); nudge.sh's cleanup removes them
_NUDGE_TMPFILES=()

# The palette, shared with lib/tui.sh and docs/assets/make-mascot.sh
DIALOG_C_CRIT="#d93b3b"
DIALOG_C_SEC="#e0a21d"
DIALOG_C_SNAP="#3b7dd8"
DIALOG_C_FLATPAK="#2a9d8f"
DIALOG_C_DIM="#8a8f98"

# --- Escaping: HTML and Pango share the same entities ---
dialog_escape() {
    local s="${1:-}"
    # the replacements are quoted: bash 5.2 would otherwise read & as the match
    s="${s//&/"&amp;"}"
    s="${s//</"&lt;"}"
    s="${s//>/"&gt;"}"
    s="${s//\"/"&quot;"}"
    printf '%s' "$s"
}

# Usage: _dialog_trim <text> <max> -> the text, cut with an ellipsis when longer
_dialog_trim() {
    local s="${1:-}" max="${2:-40}"
    if [[ "${#s}" -gt "$max" ]]; then
        printf '%s…' "${s:0:$((max - 1))}"
    else
        printf '%s' "$s"
    fi
}

# Plain text (with \n escapes) as a rich-text body: the fallback when the
# package lists are not loaded
dialog_plain_html() {
    local s
    s=$(dialog_escape "$(printf '%b' "${1:-}")")
    s="${s//$'\n'/<br>}"
    printf '<html><body>%s</body></html>' "$s"
}

# --- The mascot ---
# Usage: dialog_mascot_file <mood> -> the SVG path; 1 when not installed
dialog_mascot_file() {
    local mood="${1:-normal}" dir="${NUDGE_MASCOT_DIR:-}" f
    [[ -n "$dir" && -d "$dir" ]] || return 1
    case "$mood" in
        happy|wide|worried|sleepy|teary|crying|wave) f="$dir/bunny-${mood}.svg" ;;
        *) f="$dir/bunny.svg" ;;
    esac
    [[ -f "$f" && ! -L "$f" ]] || f="$dir/bunny.svg"
    [[ -f "$f" && ! -L "$f" ]] || return 1
    # a regular file of a sane size: the dialog process renders it
    local size
    size=$(stat -c %s "$f" 2>/dev/null) || return 1
    [[ "$size" =~ ^[0-9]+$ && "$size" -le 65536 ]] || return 1
    printf '%s' "$f"
}

# The <img> for a mood; width in px, the height keeps the character's 240:290
_dialog_img() {
    local mood="${1:-normal}" w="${2:-104}" f
    f=$(dialog_mascot_file "$mood") || return 0
    printf '<img src="%s" width="%d" height="%d">' "$(dialog_escape "$f")" "$w" $(( w * 290 / 240 ))
}

_dialog_icon() {
    if declare -F _notify_icon >/dev/null 2>&1; then _notify_icon name; else printf 'nudge'; fi
}

# --- The numbers behind every dialog ---
_DLG_SYSTEM=0 _DLG_FLATPAK=0 _DLG_SNAP=0 _DLG_TOTAL=0 _DLG_CRIT=0 _DLG_SEC=0 _DLG_IMPORTANT=0
_dialog_tally() {
    _DLG_SYSTEM="${PKG_UPDATES_TOTAL:-0}"
    _DLG_FLATPAK="${PKG_UPDATES_FLATPAK:-0}"
    _DLG_SNAP="${PKG_UPDATES_SNAP:-0}"
    _DLG_TOTAL=$((_DLG_SYSTEM + _DLG_FLATPAK + _DLG_SNAP))
    _DLG_CRIT=0; _DLG_SEC=0
    if [[ -n "${PKG_UPDATE_LIST:-}" ]]; then
        _DLG_CRIT=$(printf '%s\n' "$PKG_UPDATE_LIST" | awk -F'|' '$4 == "CRITICAL" {n++} END {print n+0}')
        _DLG_SEC=$(printf '%s\n' "$PKG_UPDATE_LIST" | awk -F'|' '$4 == "SECURITY" {n++} END {print n+0}')
    fi
    _DLG_IMPORTANT=$((_DLG_CRIT + _DLG_SEC))
}

_dialog_headline() {
    if [[ "$_DLG_TOTAL" -eq 1 ]]; then printf '1 update is ready'; else printf '%d updates are ready' "$_DLG_TOTAL"; fi
}

# "apt 32 · flatpak 1 · snap 2"
_dialog_sources() {
    local out="" mgr="${DETECTED_PKGMGR:-system}"
    [[ "$_DLG_SYSTEM" -gt 0 ]] && out+="${mgr} ${_DLG_SYSTEM}"
    [[ "$_DLG_FLATPAK" -gt 0 ]] && out+="${out:+ · }flatpak ${_DLG_FLATPAK}"
    [[ "$_DLG_SNAP" -gt 0 ]] && out+="${out:+ · }snap ${_DLG_SNAP}"
    printf '%s' "$out"
}

# "34 updates · 2 critical · 1 security"
_dialog_sources_long() {
    local out
    out="${_DLG_TOTAL} update"
    [[ "$_DLG_TOTAL" -ne 1 ]] && out+="s"
    [[ "$_DLG_CRIT" -gt 0 ]] && out+=" · ${_DLG_CRIT} critical"
    [[ "$_DLG_SEC" -gt 0 ]] && out+=" · ${_DLG_SEC} security"
    printf '%s' "$out"
}

# Every update as one row, kind|sub|label|from|to: system packages first
# (critical, then security, then the rest, each by name), then Flatpak
# (applications, then runtimes), then Snap.
# Control characters are stripped here, once, for every dialog; the arch
# suffix (libxml2:i386) is apt's alone (dnf and zypper say noarch); the order
# does not depend on the user's locale.
_dialog_rows() {
    local native="" apt=""
    if declare -F pkgmgr_native_arch >/dev/null 2>&1; then native=$(pkgmgr_native_arch 2>/dev/null || true); fi
    [[ "${DETECTED_PKGMGR:-}" == "apt" ]] && apt=1
    if [[ -n "${PKG_UPDATE_LIST:-}" ]]; then
        printf '%s\n' "$PKG_UPDATE_LIST" | awk -F'|' -v native="$native" -v apt="$apt" '
            NF >= 4 && $1 != "" {
                rank = ($4 == "CRITICAL") ? 0 : ($4 == "SECURITY") ? 1 : 2
                kind = ($4 == "CRITICAL") ? "critical" : ($4 == "SECURITY") ? "security" : "standard"
                label = $1; from = $2; to = $3
                if (apt == "1" && $5 != "" && native != "" && $5 != native && $5 != "all") label = label ":" $5
                gsub(/[[:cntrl:]]/, "", label); gsub(/[[:cntrl:]]/, "", from); gsub(/[[:cntrl:]]/, "", to)
                printf "%d|%s|system|%s|%s|%s|%s\n", rank, label, kind, label, from, to
            }' | LC_ALL=C sort -t'|' -k1,1n -k2,2 | cut -d'|' -f3-
    fi
    if [[ -n "${PKG_FLATPAK_LIST:-}" ]]; then
        printf '%s\n' "$PKG_FLATPAK_LIST" | awk -F'|' '
            NF >= 2 && $2 != "" {
                kind = ($1 == "runtime") ? "runtime" : "app"
                label = ($4 != "") ? $4 : $3; to = $5
                gsub(/[[:cntrl:]]/, "", label); gsub(/[[:cntrl:]]/, "", to)
                printf "flatpak|%s|%s||%s\n", kind, label, to
            }'
    fi
    if [[ -n "${PKG_SNAP_LIST:-}" ]]; then
        printf '%s\n' "$PKG_SNAP_LIST" | awk -F'|' '
            NF >= 1 && $1 != "" {
                label = $1; to = $2
                gsub(/[[:cntrl:]]/, "", label); gsub(/[[:cntrl:]]/, "", to)
                printf "snap|snap|%s||%s\n", label, to
            }'
    fi
}

# "from → to", "→ to", or nothing
_dialog_version() {
    local from="${1:-}" to="${2:-}"
    if [[ -n "$from" && -n "$to" ]]; then
        printf '%s → %s' "$(_dialog_trim "$from" 28)" "$(_dialog_trim "$to" 28)"
    elif [[ -n "$to" ]]; then
        printf '→ %s' "$(_dialog_trim "$to" 28)"
    fi
}

# The marker before a name: ★ critical, ⚠ security, ◆ flatpak, ● snap
_dialog_mark_html() {
    case "${1:-}:${2:-}" in
        system:critical) printf '<span style="color:%s">★</span>&nbsp;' "$DIALOG_C_CRIT" ;;
        system:security) printf '<span style="color:%s">⚠</span>&nbsp;' "$DIALOG_C_SEC" ;;
        flatpak:*)       printf '<span style="color:%s">◆</span>&nbsp;' "$DIALOG_C_FLATPAK" ;;
        snap:*)          printf '<span style="color:%s">●</span>&nbsp;' "$DIALOG_C_SNAP" ;;
        *) ;;
    esac
}
_dialog_mark_pango() {
    case "${1:-}:${2:-}" in
        system:critical) printf '<span foreground="%s">★</span> ' "$DIALOG_C_CRIT" ;;
        system:security) printf '<span foreground="%s">⚠</span> ' "$DIALOG_C_SEC" ;;
        flatpak:*)       printf '<span foreground="%s">◆</span> ' "$DIALOG_C_FLATPAK" ;;
        snap:*)          printf '<span foreground="%s">●</span> ' "$DIALOG_C_SNAP" ;;
        *) ;;
    esac
}
_dialog_mark_text() {
    case "${1:-}:${2:-}" in
        system:critical) printf '★ ' ;;
        system:security) printf '⚠ ' ;;
        flatpak:*)       printf '◆ ' ;;
        snap:*)          printf '● ' ;;
        *) printf '  ' ;;
    esac
}

# A coloured chip: _dialog_chip_html <background> <text colour> <text>
_dialog_chip_html() {
    printf '<span style="background-color:%s;color:%s;font-weight:bold">&nbsp;%s&nbsp;</span>' "$1" "$2" "$(dialog_escape "$3")"
}
_dialog_chip_pango() {
    printf '<span background="%s" foreground="%s" weight="bold"> %s </span>' "$1" "$2" "$(dialog_escape "$3")"
}

# The priority chips; nothing when there is nothing to flag. Usage: _dialog_chips html|pango
_dialog_chips() {
    local fmt="${1:-html}" out="" sep="&nbsp;&nbsp;"
    [[ "$fmt" == "pango" ]] && sep="  "
    if [[ "$_DLG_CRIT" -gt 0 ]]; then
        out+=$("_dialog_chip_$fmt" "$DIALOG_C_CRIT" "#ffffff" "★ ${_DLG_CRIT} critical")
    fi
    if [[ "$_DLG_SEC" -gt 0 ]]; then
        out+="${out:+$sep}$("_dialog_chip_$fmt" "$DIALOG_C_SEC" "#1b1b1b" "⚠ ${_DLG_SEC} security")"
    fi
    printf '%s' "$out"
}

# The first names, critical and security first. Usage: _dialog_names html|pango|text [max]
_dialog_names() {
    local fmt="${1:-html}" max="${2:-8}" n=0 total=0 out="" kind sub label _from _to mark name
    while IFS='|' read -r kind sub label _from _to; do
        [[ -z "$label" ]] && continue
        total=$((total + 1))
        [[ "$n" -ge "$max" ]] && continue
        n=$((n + 1))
        mark=$("_dialog_mark_$fmt" "$kind" "$sub")
        case "$fmt" in
            html)
                # Qt ignores white-space on a span and breaks at hyphens and spaces, so
                # the display copy gets non-breaking ones (U+2011, &nbsp;); a name
                # pasted from the dialog carries them, the terminal menu does not
                name=$(dialog_escape "$(_dialog_trim "$label" 40)")
                name="${name//-/‑}"
                name="${name// /&nbsp;}"
                out+="${out:+, }${mark}${name}" ;;
            pango)
                name=$(dialog_escape "$(_dialog_trim "$label" 40)")
                out+="${out:+, }${mark}${name}" ;;
            *)
                out+="${out:+, }${mark}$(_dialog_trim "$label" 40)" ;;
        esac
    done < <(_dialog_rows)
    [[ -z "$out" ]] && return 0
    local more=$((total - n))
    if [[ "$more" -gt 0 ]]; then
        case "$fmt" in
            html)  out+="<span style=\"color:${DIALOG_C_DIM}\">, and&nbsp;${more}&nbsp;more</span>" ;;
            pango) out+="<span foreground=\"${DIALOG_C_DIM}\">, and&#160;${more}&#160;more</span>" ;;
            *)     out+=", and ${more} more" ;;
        esac
    fi
    printf '%s' "$out"
}

# --- The prompt ---
# Usage: dialog_prompt_html <quote> <mood> <hint> <note>
dialog_prompt_html() {
    local quote="${1:-}" mood="${2:-normal}" hint="${3:-}" note="${4:-}"
    _dialog_tally
    local img chips names
    img=$(_dialog_img "$mood" 104)
    chips=$(_dialog_chips html)
    names=""
    [[ "${PREVIEW_UPDATES:-true}" == "true" ]] && names=$(_dialog_names html 8)
    local out='<html><body><table cellspacing="0" cellpadding="4"><tr>'
    [[ -n "$img" ]] && out+="<td valign=\"top\" style=\"padding-right:14px\">${img}</td>"
    out+='<td valign="top">'
    out+="<span style=\"font-size:13pt;font-weight:bold\">$(dialog_escape "$(_dialog_headline)")</span><br>"
    out+="<span style=\"color:${DIALOG_C_DIM}\">$(dialog_escape "$(_dialog_sources)")</span>"
    [[ -n "$chips" ]] && out+="<br><br>${chips}"
    [[ -n "$quote" ]] && out+="<br><br><i>&#8220;$(dialog_escape "$quote")&#8221;</i>"
    [[ -n "$names" ]] && out+="<br><br>${names}"
    [[ -n "$hint" ]] && out+="<br><span style=\"color:${DIALOG_C_DIM}\">$(dialog_escape "$hint")</span>"
    [[ -n "$note" ]] && out+="<br><br><span style=\"color:${DIALOG_C_DIM}\">$(dialog_escape "$note")</span>"
    out+='</td></tr></table></body></html>'
    printf '%s' "$out"
}

# Usage: dialog_prompt_pango <quote> <hint> <note>
dialog_prompt_pango() {
    local quote="${1:-}" hint="${2:-}" note="${3:-}"
    _dialog_tally
    local chips names nl=$'\n' out
    chips=$(_dialog_chips pango)
    names=""
    [[ "${PREVIEW_UPDATES:-true}" == "true" ]] && names=$(_dialog_names pango 8)
    out="<span size=\"large\" weight=\"bold\">$(dialog_escape "$(_dialog_headline)")</span>${nl}"
    out+="<span foreground=\"${DIALOG_C_DIM}\">$(dialog_escape "$(_dialog_sources)")</span>"
    [[ -n "$chips" ]] && out+="${nl}${nl}${chips}"
    [[ -n "$quote" ]] && out+="${nl}${nl}<i>&#8220;$(dialog_escape "$quote")&#8221;</i>"
    [[ -n "$names" ]] && out+="${nl}${nl}${names}"
    [[ -n "$hint" ]] && out+="${nl}<span foreground=\"${DIALOG_C_DIM}\">$(dialog_escape "$hint")</span>"
    [[ -n "$note" ]] && out+="${nl}${nl}<span foreground=\"${DIALOG_C_DIM}\">$(dialog_escape "$note")</span>"
    printf '%s' "$out"
}

# --- The full list ---
_dialog_group_title() {
    case "${1:-}" in
        system)  printf 'System packages (%s) · %d' "${DETECTED_PKGMGR:-system}" "$_DLG_SYSTEM" ;;
        flatpak) printf 'Flatpak · %d' "$_DLG_FLATPAK" ;;
        snap)    printf 'Snaps · %d' "$_DLG_SNAP" ;;
    esac
}
_dialog_badge_html() {
    case "${1:-}:${2:-}" in
        system:critical) _dialog_chip_html "$DIALOG_C_CRIT" "#ffffff" "critical" ;;
        system:security) _dialog_chip_html "$DIALOG_C_SEC" "#1b1b1b" "security" ;;
        flatpak:runtime) _dialog_chip_html "$DIALOG_C_FLATPAK" "#ffffff" "runtime" ;;
        flatpak:*)       _dialog_chip_html "$DIALOG_C_FLATPAK" "#ffffff" "flatpak" ;;
        snap:*)          _dialog_chip_html "$DIALOG_C_SNAP" "#ffffff" "snap" ;;
        *) ;;
    esac
}

# Every update, grouped, as rich text for kdialog's text box
dialog_fulllist_html() {
    _dialog_tally
    local out='<html><body><table cellspacing="0" cellpadding="3">' kind sub label from to cur="" first=true
    while IFS='|' read -r kind sub label from to; do
        [[ -z "$label" ]] && continue
        if [[ "$kind" != "$cur" ]]; then
            cur="$kind"
            [[ "$first" == "true" ]] || out+='<tr><td colspan="3">&nbsp;</td></tr>'
            first=false
            out+="<tr><td colspan=\"3\"><span style=\"font-size:12pt;font-weight:bold\">$(dialog_escape "$(_dialog_group_title "$kind")")</span></td></tr>"
        fi
        out+="<tr><td>$(_dialog_badge_html "$kind" "$sub")</td><td>$(dialog_escape "$label")</td>"
        out+="<td style=\"color:${DIALOG_C_DIM}\">$(dialog_escape "$(_dialog_version "$from" "$to")")</td></tr>"
    done < <(_dialog_rows)
    out+='</table></body></html>'
    printf '%s' "$out"
}

# The same list as plain text (zenity's text box, the passive backends)
dialog_fulllist_text() {
    _dialog_tally
    local kind sub label from to cur="" first=true
    while IFS='|' read -r kind sub label from to; do
        [[ -z "$label" ]] && continue
        if [[ "$kind" != "$cur" ]]; then
            cur="$kind"
            [[ "$first" == "true" ]] || printf '\n'
            first=false
            printf '%s\n' "$(_dialog_group_title "$kind")"
        fi
        printf '  %s%s  %s\n' "$(_dialog_mark_text "$kind" "$sub")" "$label" "$(_dialog_version "$from" "$to")"
    done < <(_dialog_rows)
}

# --- The pickers ---

# Which tool draws them: the backend in use, else what is installed
_dialog_tool() {
    case "${NOTIFY_BACKEND:-}" in
        kdialog|zenity) printf '%s' "$NOTIFY_BACKEND"; return 0 ;;
    esac
    if command -v kdialog &>/dev/null && [[ -n "${KDE_SESSION_VERSION:-}" ]]; then printf 'kdialog'; return 0; fi
    if command -v zenity &>/dev/null; then printf 'zenity'; return 0; fi
    if command -v kdialog &>/dev/null; then printf 'kdialog'; return 0; fi
    return 1
}

# Show every update in a scrollable box; AUTO_DISMISS closes it too
dialog_show_fulllist() {
    local tool
    tool=$(_dialog_tool) || return 0
    _dialog_tally
    local dismiss="${AUTO_DISMISS:-0}"
    local -a wrap=()
    [[ "$dismiss" =~ ^[0-9]+$ && "$dismiss" -gt 0 ]] && wrap=(timeout "$dismiss")
    local title="nudge · all ${_DLG_TOTAL} updates"
    case "$tool" in
        kdialog)
            # kdialog wants a real file for --textbox: a private one under the
            # runtime dir (cleared at logout), removed after, and by the
            # dispatcher's cleanup on a signal
            local tmp
            tmp=$(umask 077 && mktemp "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/nudge-list.XXXXXX") || return 0
            _NUDGE_TMPFILES+=("$tmp")
            if ! dialog_fulllist_html > "$tmp"; then
                rm -f "$tmp"
                return 0
            fi
            "${wrap[@]}" kdialog --icon "$(_dialog_icon)" --title "$title" --textbox "$tmp" 640 480 >/dev/null 2>&1 || true
            rm -f "$tmp"
            ;;
        zenity)
            dialog_fulllist_text | "${wrap[@]}" zenity --text-info --title="$title" --width=560 --height=480 >/dev/null 2>&1 || true
            ;;
    esac
    return 0
}

# The header above a picker: a small bunny, a title, a dim subtitle
_dialog_picker_head_html() {
    local title="${1:-}" subtitle="${2:-}" mood="${3:-normal}" img
    img=$(_dialog_img "$mood" 56)
    local out='<html><table cellspacing="0" cellpadding="2"><tr>'
    [[ -n "$img" ]] && out+="<td style=\"padding-right:10px\">${img}</td>"
    out+="<td valign=\"middle\"><span style=\"font-size:12pt;font-weight:bold\">$(dialog_escape "$title")</span>"
    [[ -n "$subtitle" ]] && out+="<br><span style=\"color:${DIALOG_C_DIM}\">$(dialog_escape "$subtitle")</span>"
    out+='</td></tr></table></html>'
    printf '%s' "$out"
}
_dialog_picker_head_pango() {
    local title="${1:-}" subtitle="${2:-}" out
    out="<span size=\"large\" weight=\"bold\">$(dialog_escape "$title")</span>"
    [[ -n "$subtitle" ]] && out+=$'\n'"<span foreground=\"${DIALOG_C_DIM}\">$(dialog_escape "$subtitle")</span>"
    printf '%s' "$out"
}

# One list picker for both tools. Items on stdin, one per line: tag|label|on/off.
# Usage: _dialog_pick <title> <subtitle> <mood> -> the chosen tag; 1 on cancel
_dialog_pick() {
    local title="${1:-}" subtitle="${2:-}" mood="${3:-normal}" tool tag label def choice="" rc=0
    tool=$(_dialog_tool) || return 1
    local -a args=() wrap=() zen_timeout=()
    local dismiss="${AUTO_DISMISS:-0}"
    if [[ "$dismiss" =~ ^[0-9]+$ && "$dismiss" -gt 0 ]]; then
        wrap=(timeout "$dismiss")
        zen_timeout=("--timeout=$dismiss")
    fi
    case "$tool" in
        kdialog)
            while IFS='|' read -r tag label def; do
                [[ -n "$tag" ]] && args+=("$tag" "$label" "${def:-off}")
            done
            [[ "${#args[@]}" -gt 0 ]] || return 1
            choice=$("${wrap[@]}" kdialog --icon "$(_dialog_icon)" --title "nudge" \
                --radiolist "$(_dialog_picker_head_html "$title" "$subtitle" "$mood")" "${args[@]}" 2>/dev/null) || rc=$?
            ;;
        zenity)
            local flag
            while IFS='|' read -r tag label def; do
                [[ -n "$tag" ]] || continue
                flag=FALSE
                [[ "$def" == "on" ]] && flag=TRUE
                args+=("$flag" "$tag" "$label")
            done
            [[ "${#args[@]}" -gt 0 ]] || return 1
            choice=$(zenity --list --radiolist --title="nudge" \
                --text="$(_dialog_picker_head_pango "$title" "$subtitle")" \
                --column="" --column="tag" --column="" --hide-column=2 --print-column=2 --hide-header \
                --width=460 --height=380 "${zen_timeout[@]}" "${args[@]}" 2>/dev/null) || rc=$?
            ;;
        *) return 1 ;;
    esac
    [[ "$rc" -eq 0 ]] || return 1
    choice="${choice//[[:space:]]/}"
    [[ -n "$choice" ]] || return 1
    printf '%s' "$choice"
}

# The scope choices as tag|label|on/off
_dialog_scope_items() {
    _dialog_tally
    local sources=0 atomic=false noun="updates"
    [[ "$_DLG_SYSTEM" -gt 0 ]] && sources=$((sources + 1))
    [[ "$_DLG_FLATPAK" -gt 0 ]] && sources=$((sources + 1))
    [[ "$_DLG_SNAP" -gt 0 ]] && sources=$((sources + 1))
    [[ "${DETECTED_PKGMGR:-}" == "pacman" ]] && atomic=true
    [[ "$_DLG_TOTAL" -eq 1 ]] && noun="update"
    printf 'all|Everything  (%d %s)|on\n' "$_DLG_TOTAL" "$noun"
    if [[ "$_DLG_IMPORTANT" -gt 0 && "$_DLG_IMPORTANT" -lt "$_DLG_TOTAL" && "$atomic" != "true" ]]; then
        printf 'important|Critical and security updates only  (%d)|off\n' "$_DLG_IMPORTANT"
    fi
    if [[ "$sources" -ge 2 ]]; then
        [[ "$_DLG_SYSTEM" -gt 0 ]] && printf 'system|System packages only  (%d, %s)|off\n' "$_DLG_SYSTEM" "${DETECTED_PKGMGR:-system}"
        [[ "$_DLG_FLATPAK" -gt 0 ]] && printf 'flatpak|Flatpak only  (%d)|off\n' "$_DLG_FLATPAK"
        [[ "$_DLG_SNAP" -gt 0 ]] && printf 'snap|Snaps only  (%d)|off\n' "$_DLG_SNAP"
    fi
    printf 'pick|Let me pick one by one…|off\n'
    printf 'list|Show me the full list first|off\n'
}

# Usage: dialog_scope_pick [mood] -> all|important|system|flatpak|snap|pick; 1 when cancelled.
# Without a dialog tool the terminal menu does the picking.
dialog_scope_pick() {
    local mood="${1:-happy}" choice
    if ! _dialog_tool >/dev/null 2>&1; then printf 'pick'; return 0; fi
    _dialog_tally
    while :; do
        choice=$(_dialog_scope_items | _dialog_pick "What should I install?" "$(_dialog_sources_long)" "$mood") || return 1
        case "$choice" in
            list) dialog_show_fulllist ;;
            all|important|system|flatpak|snap|pick) printf '%s' "$choice"; return 0 ;;
            *) return 1 ;;
        esac
    done
}

# --- Deferral ---
# Usage: _dialog_defer_label 1h -> "In an hour"
_dialog_defer_label() {
    local d="${1:-}" n unit
    if [[ ! "$d" =~ ^([0-9]+)([hdw])$ ]]; then printf '%s' "$d"; return 0; fi
    n=$((10#${BASH_REMATCH[1]}))
    unit="${BASH_REMATCH[2]}"
    case "$unit" in
        h) if [[ "$n" -eq 1 ]]; then printf 'In an hour'; else printf 'In %d hours' "$n"; fi ;;
        d) if [[ "$n" -eq 1 ]]; then printf 'Tomorrow'; else printf 'In %d days' "$n"; fi ;;
        w) if [[ "$n" -eq 1 ]]; then printf 'Next week'; else printf 'In %d weeks' "$n"; fi ;;
    esac
}

# Usage: dialog_defer_pick [quote] -> the duration (1h, 4h, 1d…); 1 when cancelled
dialog_defer_pick() {
    local quote="${1:-}" options="${DEFERRAL_OPTIONS:-1h,4h,1d}" opt def="on" items=""
    local -a opts
    IFS=',' read -ra opts <<< "$options"
    [[ "${#opts[@]}" -gt 0 ]] || return 1
    if ! _dialog_tool >/dev/null 2>&1; then printf '%s' "${opts[0]}"; return 0; fi
    for opt in "${opts[@]}"; do
        opt="${opt//[[:space:]]/}"
        [[ -n "$opt" ]] || continue
        items+="${opt}|$(_dialog_defer_label "$opt")|${def}"$'\n'
        def="off"
    done
    printf '%s' "$items" | _dialog_pick "When should I ask again?" "$quote" "sleepy"
}

# --- Reboot ---
# Usage: dialog_reboot_ask [quote] -> 0 restart now, 1 later
dialog_reboot_ask() {
    local quote="${1:-}" tool
    tool=$(_dialog_tool) || return 1
    local -a wrap=() zen_timeout=()
    local dismiss="${AUTO_DISMISS:-0}"
    if [[ "$dismiss" =~ ^[0-9]+$ && "$dismiss" -gt 0 ]]; then
        wrap=(timeout "$dismiss")
        zen_timeout=("--timeout=$dismiss")
    fi
    local title="A restart finishes the update"
    local sub="the new kernel or core libraries take over on the next boot"
    local ask="Restart now? Save your work first."
    case "$tool" in
        kdialog)
            local body='<html><body><table cellspacing="0" cellpadding="4"><tr>' img
            img=$(_dialog_img worried 104)
            [[ -n "$img" ]] && body+="<td valign=\"top\" style=\"padding-right:14px\">${img}</td>"
            body+="<td valign=\"top\"><span style=\"font-size:13pt;font-weight:bold\">${title}</span><br>"
            body+="<span style=\"color:${DIALOG_C_DIM}\">${sub}</span>"
            [[ -n "$quote" ]] && body+="<br><br><i>&#8220;$(dialog_escape "$quote")&#8221;</i>"
            body+="<br><br>${ask}</td></tr></table></body></html>"
            if "${wrap[@]}" kdialog --icon "$(_dialog_icon)" --title "nudge" --yes-label "Restart Now" --no-label "Later" --yesno "$body" 2>/dev/null; then
                return 0
            fi
            return 1
            ;;
        zenity)
            local text nl=$'\n'
            text="<span size=\"large\" weight=\"bold\">${title}</span>${nl}<span foreground=\"${DIALOG_C_DIM}\">${sub}</span>"
            [[ -n "$quote" ]] && text+="${nl}${nl}<i>&#8220;$(dialog_escape "$quote")&#8221;</i>"
            text+="${nl}${nl}${ask}"
            if zenity --question --icon-name="$(_dialog_icon)" --title="nudge" --ok-label="Restart Now" --cancel-label="Later" --text="$text" "${zen_timeout[@]}" 2>/dev/null; then
                return 0
            fi
            return 1
            ;;
    esac
    return 1
}
