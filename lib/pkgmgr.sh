#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/pkgmgr.sh
# Package manager abstraction — apt/dnf/pacman/zypper + flatpak + snap, and
# the upgrade session: the selection menu and the upgrades themselves run in
# a terminal window the user can read, with sudo able to ask for a password.

set -euo pipefail

# Detected package manager
DETECTED_PKGMGR=""

# Update counts
PKG_UPDATES_TOTAL=0
PKG_UPDATES_SECURITY=0
PKG_UPDATES_CRITICAL=0
PKG_UPDATES_FLATPAK=0
PKG_UPDATES_SNAP=0

# System package list, one per line: name|from|to|priority|arch|security(0/1)
PKG_UPDATE_LIST=""
# Flatpak list, one per line: kind|ref|application|name|version
PKG_FLATPAK_LIST=""
# Snap list, one per line: name|version|rev|size|publisher
PKG_SNAP_LIST=""

# Critical package patterns
readonly CRITICAL_PACKAGES="^(linux-image|linux-headers|kernel|openssl|libssl|glibc|libc6|openssh|sudo|pam|libpam|systemd|polkit|cups|xz|curl|wget|gnupg|gpg|dbus|grub|shim|mokutil|fwupd)(-|$)"

# Results of the last upgrade session (read by nudge.sh after pkgmgr_upgrade)
_UPG_CANCELLED=0
_UPG_SYSTEM="skipped"
_UPG_FLATPAK="skipped"
_UPG_SNAP="skipped"
_UPG_SELECTED_SYSTEM=0
_UPG_SELECTED_FLATPAK=0
_UPG_SELECTED_SNAP=0
_UPG_TOTAL_SYSTEM=0
_UPG_TOTAL_FLATPAK=0
_UPG_TOTAL_SNAP=0
_UPG_SNAPSHOT_ID=""
# What the retry loop recorded (lib/retry.sh): attempts made, whether the user
# declined another try, the report written when a step keeps failing, and per
# list the cause, how many times it has failed and the names it blamed
_UPG_ATTEMPTS=1
_UPG_RETRY_DECLINED=0
_UPG_REPORT=""
declare -gA _UPG_CAUSE=()
declare -gA _UPG_FAILS=()
declare -gA _UPG_CULPRITS=()
declare -gA _UPG_LEFT=()        # per list: the updates the session left out because they could not be downloaded
declare -gA _UPG_LEFT_CAUSE=()  # per list: the cause of the failure that left them out
declare -gA _UPG_WAITING=()     # per list: standard updates set aside, waiting for their download
declare -gA _UPG_WAITING_CAUSE=()

_PKG_NATIVE_ARCH=""

# --- Detect system package manager ---
pkgmgr_detect() {
    if [[ -n "${PKGMGR_OVERRIDE:-}" ]]; then
        DETECTED_PKGMGR="$PKGMGR_OVERRIDE"
        log_info "Package manager override: $DETECTED_PKGMGR"
        return 0
    fi

    if command -v apt &>/dev/null && [[ -d /var/lib/dpkg ]]; then
        DETECTED_PKGMGR="apt"
    elif command -v dnf &>/dev/null; then
        DETECTED_PKGMGR="dnf"
    elif command -v pacman &>/dev/null; then
        DETECTED_PKGMGR="pacman"
    elif command -v zypper &>/dev/null; then
        DETECTED_PKGMGR="zypper"
    else
        log_error "No supported package manager found"
        return 1
    fi

    log_info "Detected package manager: $DETECTED_PKGMGR"
    return 0
}

# --- Lock check ---
pkgmgr_lock_check() {
    case "$DETECTED_PKGMGR" in
        apt)
            # fuser cannot see root-held locks from a user account, so the usual
            # holders are looked for by name too (the unattended-upgrade shutdown
            # waiter that is always running on Ubuntu is not one of them)
            if fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1 \
               || pgrep -x 'apt-get|dpkg|aptitude|synaptic' &>/dev/null \
               || pgrep -f '/usr/bin/unattended-upgrade( |$)' &>/dev/null; then
                log_warn "APT lock held by another process"
                return 1
            fi
            ;;
        dnf)
            if [[ -f /var/run/dnf.pid ]] && kill -0 "$(cat /var/run/dnf.pid 2>/dev/null)" 2>/dev/null; then
                log_warn "DNF lock held by another process"
                return 1
            fi
            ;;
        pacman)
            if [[ -f /var/lib/pacman/db.lck ]]; then
                if command -v fuser &>/dev/null && ! fuser /var/lib/pacman/db.lck &>/dev/null 2>&1; then
                    log_warn "Stale pacman lock file found (no process holds it) — consider: sudo rm /var/lib/pacman/db.lck"
                else
                    log_warn "Pacman database locked by active process"
                    return 1
                fi
            fi
            ;;
        zypper)
            if [[ -f /var/run/zypp.pid ]] && kill -0 "$(cat /var/run/zypp.pid 2>/dev/null)" 2>/dev/null; then
                log_warn "Zypper lock held"
                return 1
            fi
            ;;
    esac
    return 0
}

# --- Native architecture (for apt's name:arch targets) ---
pkgmgr_native_arch() {
    if [[ -z "$_PKG_NATIVE_ARCH" ]]; then
        _PKG_NATIVE_ARCH=$(dpkg --print-architecture 2>/dev/null) || _PKG_NATIVE_ARCH=$(uname -m)
    fi
    printf '%s' "$_PKG_NATIVE_ARCH"
}

# --- Classify package priority ---
_classify_priority() {
    local pkg_name="$1" is_security="${2:-false}"

    # Merge built-in and user-defined critical patterns (CRITICAL_PACKAGES_EXTRA is validated by config_load)
    local pattern="$CRITICAL_PACKAGES"
    if [[ -n "${CRITICAL_PACKAGES_EXTRA:-}" ]]; then
        pattern="${CRITICAL_PACKAGES%)(-|\$)}|${CRITICAL_PACKAGES_EXTRA})(-|\$)"
    fi

    # Arch names its kernel packages linux, linux-lts, linux-zen, linux-hardened
    if [[ "$pkg_name" =~ $pattern ]] || [[ "$pkg_name" =~ ^linux(-lts|-zen|-hardened|-rt)?$ ]]; then
        echo "CRITICAL"
    elif [[ "$is_security" == "true" ]]; then
        echo "SECURITY"
    else
        echo "STANDARD"
    fi
}

# Sort rank: critical first, then security, then the rest
_priority_rank() {
    case "$1" in
        CRITICAL) echo 0 ;;
        SECURITY) echo 1 ;;
        *)        echo 2 ;;
    esac
}

# --- Count updates ---
# apt uses update-notifier's apt-check when present (the count Ubuntu shows at
# login); everything else counts the detailed list.
PKG_COUNT_SOURCE="list"   # what the count came from: apt-check (no phased updates) or the list
pkgmgr_count_updates() {
    PKG_COUNT_SOURCE="list"
    PKG_UPDATES_TOTAL=0
    PKG_UPDATES_SECURITY=0
    PKG_UPDATES_CRITICAL=0

    case "$DETECTED_PKGMGR" in
        apt)
            local apt_check="${NUDGE_APT_CHECK:-/usr/lib/update-notifier/apt-check}"
            local apt_out=""
            if [[ -x "$apt_check" ]]; then
                # apt-check prints "total;security" on stderr by design
                apt_out=$("$apt_check" 2>&1 1>/dev/null || true)
            fi
            if [[ "$apt_out" =~ ^[0-9]+\;[0-9]+$ ]]; then
                PKG_UPDATES_TOTAL="${apt_out%%;*}"
                PKG_UPDATES_SECURITY="${apt_out##*;}"
                # shellcheck disable=SC2034  # read by lib/waiting.sh
                PKG_COUNT_SOURCE="apt-check"
            else
                [[ -x "$apt_check" ]] && log_warn "apt-check returned unexpected output, counting apt list instead"
                pkgmgr_list_updates
                PKG_UPDATES_TOTAL=$(_pkgmgr_list_count)
                PKG_UPDATES_SECURITY=$(_pkgmgr_list_count_security)
            fi
            ;;
        dnf)
            pkgmgr_list_updates
            PKG_UPDATES_TOTAL=$(_pkgmgr_list_count)
            PKG_UPDATES_SECURITY=$(_pkgmgr_list_count_security)
            ;;
        pacman)
            pkgmgr_list_updates
            PKG_UPDATES_TOTAL=$(_pkgmgr_list_count)
            PKG_UPDATES_SECURITY=0
            ;;
        zypper)
            pkgmgr_list_updates
            PKG_UPDATES_TOTAL=$(_pkgmgr_list_count)
            PKG_UPDATES_SECURITY=$(zypper --non-interactive list-patches --category security 2>/dev/null | awk -F'|' 'NF >= 3 && $3 ~ /security/ {n++} END {print n+0}' || true)
            ;;
    esac

    # Ensure numeric
    PKG_UPDATES_TOTAL="${PKG_UPDATES_TOTAL//[!0-9]/}"
    PKG_UPDATES_SECURITY="${PKG_UPDATES_SECURITY//[!0-9]/}"
    [[ -z "$PKG_UPDATES_TOTAL" ]] && PKG_UPDATES_TOTAL=0
    [[ -z "$PKG_UPDATES_SECURITY" ]] && PKG_UPDATES_SECURITY=0

    log_info "Updates available: $PKG_UPDATES_TOTAL (security: $PKG_UPDATES_SECURITY)"
    return 0
}

_pkgmgr_list_count() {
    [[ -z "$PKG_UPDATE_LIST" ]] && { echo 0; return; }
    printf '%s\n' "$PKG_UPDATE_LIST" | grep -c '.' || true
}

_pkgmgr_list_count_security() {
    [[ -z "$PKG_UPDATE_LIST" ]] && { echo 0; return; }
    printf '%s\n' "$PKG_UPDATE_LIST" | awk -F'|' '$6 == "1" {n++} END {print n+0}'
}

_pkg_add_row() {
    # name from to priority arch security
    PKG_UPDATE_LIST+="${1}|${2}|${3}|${4}|${5}|${6}"$'\n'
    [[ "$4" == "CRITICAL" ]] && PKG_UPDATES_CRITICAL=$((PKG_UPDATES_CRITICAL + 1))
    return 0
}

# dnf: names of packages carried by security advisories
declare -gA _DNF_SECURITY_NAMES=()
_dnf_collect_security_names() {
    _DNF_SECURITY_NAMES=()
    local line nevra name
    while IFS= read -r line; do
        # "FEDORA-2026-abc123 Important/Sec. pkg-1.2.3-1.fc40.x86_64"
        nevra="${line##* }"
        [[ -z "$nevra" || "$nevra" == "$line" ]] && continue
        name="${nevra%.*}"        # drop arch
        name="${name%-*}"         # drop release
        name="${name%-*}"         # drop version
        [[ -n "$name" ]] && _DNF_SECURITY_NAMES["$name"]=1
    done < <(dnf updateinfo list --security -q 2>/dev/null || true)
}

# --- List updates with details ---
pkgmgr_list_updates() {
    PKG_UPDATE_LIST=""
    PKG_UPDATES_CRITICAL=0

    case "$DETECTED_PKGMGR" in
        apt)
            local line name suite to_ver arch from_ver sec priority is_sec
            while IFS= read -r line; do
                # name/suite,suite new_version arch [upgradable from: old_version]
                if [[ "$line" =~ ^([^/[:space:]]+)/([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+\[upgradable\ from:\ ([^]]+)\] ]]; then
                    name="${BASH_REMATCH[1]}"
                    suite="${BASH_REMATCH[2]}"
                    to_ver="${BASH_REMATCH[3]}"
                    arch="${BASH_REMATCH[4]}"
                    from_ver="${BASH_REMATCH[5]}"
                    sec=0; is_sec=false
                    if [[ "$suite" == *-security* ]]; then sec=1; is_sec=true; fi
                    priority=$(_classify_priority "$name" "$is_sec")
                    _pkg_add_row "$name" "$from_ver" "$to_ver" "$priority" "$arch" "$sec"
                fi
            done < <(apt list --upgradable 2>/dev/null || true)
            ;;
        dnf)
            _dnf_collect_security_names
            local line na name arch to_ver sec is_sec priority
            while IFS= read -r line; do
                # "name.arch   version-release   repo"
                [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]*[0-9][^[:space:]]*)[[:space:]]+([^[:space:]]+)$ ]] || continue
                na="${BASH_REMATCH[1]}"
                to_ver="${BASH_REMATCH[2]}"
                [[ "$na" == *.* ]] || continue
                arch="${na##*.}"
                name="${na%.*}"
                sec=0; is_sec=false
                if [[ -n "${_DNF_SECURITY_NAMES[$name]:-}" ]]; then sec=1; is_sec=true; fi
                priority=$(_classify_priority "$name" "$is_sec")
                _pkg_add_row "$name" "" "$to_ver" "$priority" "$arch" "$sec"
            done < <(dnf check-update -q 2>/dev/null || true)
            ;;
        pacman)
            local lister="pacman -Qu"
            command -v checkupdates &>/dev/null && lister="checkupdates"
            local line name from_ver to_ver priority
            while IFS= read -r line; do
                if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+-[\>][[:space:]]+([^[:space:]]+) ]]; then
                    name="${BASH_REMATCH[1]}"
                    from_ver="${BASH_REMATCH[2]}"
                    to_ver="${BASH_REMATCH[3]}"
                    priority=$(_classify_priority "$name")
                    _pkg_add_row "$name" "$from_ver" "$to_ver" "$priority" "" 0
                fi
            done < <($lister 2>/dev/null || true)
            ;;
        zypper)
            # S | Repository | Name | Current Version | Available Version | Arch
            local _s _repo name from_ver to_ver arch priority
            while IFS='|' read -r _s _repo name from_ver to_ver arch; do
                name="${name// /}"; from_ver="${from_ver// /}"; to_ver="${to_ver// /}"; arch="${arch// /}"
                [[ -z "$name" || "$name" == "Name" ]] && continue
                priority=$(_classify_priority "$name")
                _pkg_add_row "$name" "$from_ver" "$to_ver" "$priority" "$arch" 0
            done < <(zypper --non-interactive list-updates 2>/dev/null | grep -E '^\s*v?\s*\|' || true)
            ;;
    esac

    # Remove trailing newline
    PKG_UPDATE_LIST="${PKG_UPDATE_LIST%$'\n'}"
}

# --- What an apt upgrade would do, simulated as the user (nothing locked or changed) ---
# Usage: pkgmgr_apt_upgrade_set [full|plain] -> "inst <target>" for each
# package it would install or upgrade, "phased <target>" for each it defers
# while the distribution phases it in; a target is name, or name:arch for
# another architecture. 1 when apt cannot say.
pkgmgr_apt_upgrade_set() {
    local how="full-upgrade" native out line name arch in_phased=false
    [[ "${1:-full}" == "plain" ]] && how="upgrade"
    command -v apt-get >/dev/null 2>&1 || return 1
    native=$(pkgmgr_native_arch)
    out=$(LC_ALL=C timeout 60 apt-get -s -q -o Debug::NoLocking=1 "$how" 2>/dev/null) || return 1
    local LC_ALL=C
    while IFS= read -r line; do
        if [[ "$line" == "The following upgrades have been deferred due to phasing:" ]]; then
            in_phased=true
            continue
        fi
        if [[ "$in_phased" == "true" ]]; then
            if [[ "$line" == " "* ]]; then
                for name in $line; do
                    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9+._-]*(:[A-Za-z0-9_-]+)?$ ]] || continue
                    arch="${name#*:}"
                    [[ "$name" == *:* && ( "$arch" == "$native" || "$arch" == "all" ) ]] && name="${name%%:*}"
                    printf 'phased %s\n' "$name"
                done
                continue
            fi
            in_phased=false
        fi
        [[ "$line" =~ ^Inst\ ([A-Za-z0-9][A-Za-z0-9+._-]*)(:([A-Za-z0-9_-]+))?\  ]] || continue
        name="${BASH_REMATCH[1]}"
        arch="${BASH_REMATCH[3]}"
        [[ -n "$arch" && "$arch" != "$native" && "$arch" != "all" ]] && name+=":${arch}"
        printf 'inst %s\n' "$name"
    done <<< "$out"
    return 0
}

# --- The full-upgrade command (used when every system package is selected) ---
# UPDATE_COMMAND wins on every manager when the user changed it; otherwise
# each manager has its own default.
_pkgmgr_default_cmd() {
    case "${1:-$DETECTED_PKGMGR}" in
        apt)    echo "sudo apt update && sudo apt full-upgrade" ;;
        dnf)    echo "sudo dnf upgrade -y" ;;
        pacman) echo "sudo pacman -Syu --noconfirm" ;;
        zypper) echo "sudo zypper update -y" ;;
        *)      return 1 ;;
    esac
}

_build_upgrade_cmd() {
    local default
    default=$(_pkgmgr_default_cmd "$DETECTED_PKGMGR") || {
        log_error "No upgrade command for package manager: ${DETECTED_PKGMGR:-unset}"
        return 1
    }
    local shipped="sudo apt update && sudo apt full-upgrade"
    if [[ -n "${UPDATE_COMMAND:-}" ]] && [[ "$UPDATE_COMMAND" != "$shipped" ]]; then
        echo "$UPDATE_COMMAND"
    else
        echo "$default"
    fi
}

# 0 when the effective update command is not the shipped default for this manager
pkgmgr_custom_update_command() {
    [[ "$(_build_upgrade_cmd 2>/dev/null)" != "$(_pkgmgr_default_cmd "$DETECTED_PKGMGR" 2>/dev/null)" ]]
}

# --- Terminal emulators nudge knows how to drive ---
readonly _KNOWN_TERMINALS=" konsole gnome-terminal xfce4-terminal alacritty kitty foot wezterm tilix terminator x-terminal-emulator xterm "

# A program the user cannot modify: the file PATH gives, followed to the end,
# is owned by root and not writable (a read-only shim of the user's own would
# otherwise do). This is the rule for everything that touches the window where
# the sudo password is typed: the terminal, and whatever wraps it.
# Usage: _trusted_program_path <name> [resolved] -> prints the path PATH gave,
# or with "resolved" the file it points at (so a link in a user-writable PATH
# directory cannot be re-pointed between this check and the exec)
_trusted_program_path() {
    local name="$1" want="${2:-path}" path real owner
    path=$(type -P "$name" 2>/dev/null) || return 1
    [[ -n "$path" ]] || return 1
    real=$(readlink -f "$path" 2>/dev/null) || return 1
    owner=$(stat -c %u "$real" 2>/dev/null) || return 1
    [[ -n "$real" && -x "$real" && "$owner" == "0" && ! -w "$real" ]] || return 1
    if [[ "$want" == "resolved" ]]; then printf '%s' "$real"; else printf '%s' "$path"; fi
}

# A known terminal name that passes that rule
# Usage: _terminal_path <name> -> prints the path PATH gave
_terminal_path() {
    local name="$1"
    [[ " $_KNOWN_TERMINALS " == *" $name "* ]] || return 1
    _trusted_program_path "$name"
}

# --- Detect terminal emulator (prints the name) ---
_detect_terminal() {
    # Config override (validated to a bare program name by config_load)
    if [[ -n "${TERMINAL_EMULATOR:-}" ]] && [[ "${TERMINAL_EMULATOR:-auto}" != "auto" ]]; then
        if _terminal_path "$TERMINAL_EMULATOR" >/dev/null; then
            echo "$TERMINAL_EMULATOR"
            return
        fi
        log_warn "Configured TERMINAL_EMULATOR=$TERMINAL_EMULATOR is not a known terminal owned by root; auto-detecting"
    fi

    local t
    for t in $_KNOWN_TERMINALS; do
        if _terminal_path "$t" >/dev/null; then
            echo "$t"
            return
        fi
    done
    echo "none"
}

# --- Flatpak support ---
flatpak_available() {
    local mode="${FLATPAK_ENABLED:-auto}"
    case "$mode" in
        true)  return 0 ;;
        false) return 1 ;;
        auto)
            if command -v flatpak &>/dev/null; then
                # Check if at least one remote exists
                if flatpak remotes 2>/dev/null | grep -q '.'; then
                    return 0
                fi
            fi
            return 1
            ;;
    esac
}

# Fills PKG_FLATPAK_LIST: kind|ref|application|name|version
flatpak_list() {
    PKG_FLATPAK_LIST=""
    flatpak_available || return 0
    local kind flag line ref app name version
    for kind in app runtime; do
        flag="--${kind}"
        while IFS=$'\t' read -r ref app name version; do
            [[ -z "$ref" || "$ref" == "Ref" ]] && continue
            PKG_FLATPAK_LIST+="${kind}|${ref}|${app}|${name}|${version}"$'\n'
        done < <(flatpak remote-ls --updates "$flag" --columns=ref,application,name,version 2>/dev/null || true)
    done
    PKG_FLATPAK_LIST="${PKG_FLATPAK_LIST%$'\n'}"
}

flatpak_count() {
    PKG_UPDATES_FLATPAK=0
    if flatpak_available; then
        flatpak_list
        if [[ -n "$PKG_FLATPAK_LIST" ]]; then
            PKG_UPDATES_FLATPAK=$(printf '%s\n' "$PKG_FLATPAK_LIST" | grep -c '.' || true)
        fi
        log_info "Flatpak updates: $PKG_UPDATES_FLATPAK"
    fi
}

# --- Snap support ---
snap_available() {
    local mode="${SNAP_ENABLED:-auto}"
    case "$mode" in
        true)  return 0 ;;
        false) return 1 ;;
        auto)
            command -v snap &>/dev/null && return 0
            return 1
            ;;
    esac
}

# Fills PKG_SNAP_LIST: name|version|rev|size|publisher
snap_list() {
    PKG_SNAP_LIST=""
    snap_available || return 0
    local line name version rev size publisher _rest
    while read -r name version rev size publisher _rest; do
        [[ -z "$name" || "$name" == "Name" ]] && continue
        [[ "$name" == "All" ]] && continue   # "All snaps up to date."
        PKG_SNAP_LIST+="${name}|${version}|${rev}|${size}|${publisher}"$'\n'
    done < <(snap refresh --list 2>/dev/null || true)
    PKG_SNAP_LIST="${PKG_SNAP_LIST%$'\n'}"
}

snap_count() {
    PKG_UPDATES_SNAP=0
    if snap_available; then
        snap_list
        if [[ -n "$PKG_SNAP_LIST" ]]; then
            PKG_UPDATES_SNAP=$(printf '%s\n' "$PKG_SNAP_LIST" | grep -c '.' || true)
        fi
        log_info "Snap updates: $PKG_UPDATES_SNAP"
    fi
}

# --- Build message with priority classification ---
pkgmgr_build_summary() {
    local total=$((PKG_UPDATES_TOTAL + PKG_UPDATES_FLATPAK + PKG_UPDATES_SNAP))
    local msg="${total} update(s) available"

    if [[ "$PKG_UPDATES_CRITICAL" -gt 0 ]]; then
        msg+=": ${PKG_UPDATES_CRITICAL} CRITICAL"
    fi
    if [[ "$PKG_UPDATES_SECURITY" -gt 0 ]]; then
        msg+=", ${PKG_UPDATES_SECURITY} SECURITY"
    fi

    local standard=$((PKG_UPDATES_TOTAL - PKG_UPDATES_CRITICAL - PKG_UPDATES_SECURITY))
    [[ "$standard" -lt 0 ]] && standard=0
    if [[ "$standard" -gt 0 ]]; then
        msg+=", ${standard} STANDARD"
    fi

    if [[ "$PKG_UPDATES_FLATPAK" -gt 0 ]]; then
        msg+=" + ${PKG_UPDATES_FLATPAK} Flatpak"
    fi
    if [[ "$PKG_UPDATES_SNAP" -gt 0 ]]; then
        msg+=" + ${PKG_UPDATES_SNAP} Snap"
    fi

    echo "$msg"
}

# The list sorted critical > security > standard, then by name
_pkgmgr_sorted_list() {
    [[ -z "$PKG_UPDATE_LIST" ]] && return 0
    local name from_ver to_ver priority rest
    while IFS='|' read -r name from_ver to_ver priority rest; do
        [[ -z "$name" ]] && continue
        printf '%s|%s|%s|%s|%s|%s\n' "$(_priority_rank "$priority")" "$name" "$from_ver" "$to_ver" "$priority" "$rest"
    done <<< "$PKG_UPDATE_LIST" | sort -t'|' -k1,1n -k2,2 | cut -d'|' -f2-
}

# --- Build preview text (truncated package list) ---
pkgmgr_build_preview() {
    local max_lines="${1:-30}"
    local preview=""
    local count=0
    local total_lines

    if [[ -z "$PKG_UPDATE_LIST" ]]; then
        echo "(no package details available)"
        return
    fi

    total_lines=$(printf '%s\n' "$PKG_UPDATE_LIST" | grep -c '.' || true)
    local native
    native=$(pkgmgr_native_arch)

    local name from_ver to_ver priority arch _sec
    while IFS='|' read -r name from_ver to_ver priority arch _sec; do
        [[ -z "$name" ]] && continue
        count=$((count + 1))
        [[ "$count" -gt "$max_lines" ]] && break

        local line="  ${name}"
        [[ "$DETECTED_PKGMGR" == "apt" && -n "$arch" && "$arch" != "$native" && "$arch" != "all" ]] && line+=":${arch}"
        if [[ -n "$from_ver" ]]; then
            line+=" (${from_ver} → ${to_ver})"
        elif [[ -n "$to_ver" ]]; then
            line+=" (→ ${to_ver})"
        fi
        [[ "$priority" == "CRITICAL" ]] && line+=" ★ CRITICAL"
        [[ "$priority" == "SECURITY" ]] && line+=" ⚠ SECURITY"
        preview+="${line}"$'\n'
    done < <(_pkgmgr_sorted_list)

    local remaining=$((total_lines - max_lines))
    if [[ "$remaining" -gt 0 ]]; then
        preview+="  ...and ${remaining} more"$'\n'
    fi

    echo "$preview"
}

# --- Build JSON package array ---
pkgmgr_build_json_packages() {
    local json="["
    local first=true

    if [[ -n "$PKG_UPDATE_LIST" ]]; then
        local name from_ver to_ver priority arch sec
        while IFS='|' read -r name from_ver to_ver priority arch sec; do
            [[ -z "$name" ]] && continue
            [[ "$first" == "true" ]] && first=false || json+=","
            local sec_json="false"
            [[ "${sec:-0}" == "1" ]] && sec_json="true"
            json+="{\"name\":\"$(json_escape "$name")\",\"from\":\"$(json_escape "$from_ver")\",\"to\":\"$(json_escape "$to_ver")\",\"priority\":\"$(json_escape "$priority")\",\"arch\":\"$(json_escape "${arch:-}")\",\"security\":${sec_json}}"
        done <<< "$PKG_UPDATE_LIST"
    fi

    json+="]"
    echo "$json"
}

# ============================================================
# The upgrade session: GUI side
# ============================================================

# --- Write the session file the terminal runner reads ---
# Usage: pkgmgr_write_session [scope] -> prints the path
# The scope is what the dialog's picker chose: all, important, system,
# flatpak, snap, or pick (the terminal menu).
pkgmgr_write_session() {
    local scope="${1:-all}"
    case "$scope" in
        all|important|system|flatpak|snap|pick) ;;
        *) scope="pick" ;;
    esac
    local dir="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}"
    mkdir -p "$dir" 2>/dev/null || { log_error "Cannot create state directory: $dir"; return 1; }
    local sess
    sess=$(mktemp "${dir}/upgrade-session.XXXXXX") || { log_error "Cannot create session file"; return 1; }
    {
        echo "# nudge upgrade session (temporary, read by: nudge.sh --_run-upgrade)"
        echo "pkgmgr=${DETECTED_PKGMGR}"
        echo "arch=$(pkgmgr_native_arch)"
        echo "scope=${scope}"
        # what the check held back: in the menu, never ticked for the user
        if [[ -n "${PKG_WAITING_LIST:-}" ]] && declare -F waiting_held_targets >/dev/null 2>&1; then
            echo "waiting=$(waiting_held_targets)"
        fi
        echo "[system]"
        [[ -n "$PKG_UPDATE_LIST" ]] && printf '%s\n' "$PKG_UPDATE_LIST"
        [[ -n "${PKG_WAITING_LIST:-}" ]] && printf '%s\n' "$PKG_WAITING_LIST"
        echo "[flatpak]"
        [[ -n "$PKG_FLATPAK_LIST" ]] && printf '%s\n' "$PKG_FLATPAK_LIST"
        echo "[snap]"
        [[ -n "$PKG_SNAP_LIST" ]] && printf '%s\n' "$PKG_SNAP_LIST"
    } > "$sess"
    printf '%s' "$sess"
}

# --- The terminal's own place in the process tree ---
# nudge opens the session's terminal from its own process, and at login that
# process lives in the autostart service's cgroup. Everything the terminal
# then spawns (every tab the user opens in that window, and whatever runs in
# those tabs) would be charged to "Nudge Update Checker" in the system
# monitor and keep the service "running" long after nudge itself is gone. So
# the terminal is started in a transient scope of its own, named the way the
# desktop names an application it launched (app-<desktop id>-<random>.scope,
# the XDG unit-naming convention), when a systemd user manager is there to
# make one. Without one the terminal is simply started.

# The desktop file id of a terminal, for the scope's name
# Usage: _terminal_desktop_id <name> <path>
_terminal_desktop_id() {
    local name="$1" path="${2:-}" real
    case "$name" in
        konsole)         echo "org.kde.konsole" ;;
        gnome-terminal)  echo "org.gnome.Terminal" ;;
        alacritty)       echo "Alacritty" ;;
        wezterm)         echo "org.wezfurlong.wezterm" ;;
        tilix)           echo "com.gexperts.Tilix" ;;
        x-terminal-emulator)
            # the alternatives link: name the program it points at
            real=$(readlink -f "$path" 2>/dev/null) || real=""
            real="${real##*/}"
            if [[ -n "$real" && "$real" != "x-terminal-emulator" && " $_KNOWN_TERMINALS " == *" $real "* ]]; then
                _terminal_desktop_id "$real" "$path"
            else
                echo "${real:-x-terminal-emulator}"
            fi ;;
        *)               echo "$name" ;;
    esac
}

# systemd-run, held to the terminal's rule (the program that wraps the window
# where the sudo password is typed), and taken as the file it resolves to
# Usage: _pkgmgr_systemd_run_path -> prints the path, or fails
_pkgmgr_systemd_run_path() {
    _trusted_program_path systemd-run resolved
}

# 0 when a systemd user manager will make a scope for us (proved by making one;
# a manager that is up but not answering is given ten seconds, not sd-bus's 25)
# Usage: _pkgmgr_scope_available <systemd-run path>
_pkgmgr_scope_available() {
    local run="$1"
    local -a limit=()
    [[ -d /run/systemd/system ]] || return 1
    command -v timeout >/dev/null 2>&1 && limit=(timeout 10)
    "${limit[@]}" "$run" --user --scope --quiet --collect "--unit=nudge-probe-$$-${RANDOM}.scope" -- true >/dev/null 2>&1
}

# The words that put a command into its own scope, or none
# Usage: _pkgmgr_scope_words <array name> <terminal> <path>
_pkgmgr_scope_words() {
    local -n _scope_out="$1"
    local term="$2" path="$3" run id hex
    _scope_out=()
    run=$(_pkgmgr_systemd_run_path) || return 0
    _pkgmgr_scope_available "$run" || return 0
    id=$(_terminal_desktop_id "$term" "$path")
    [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || id="$term"
    id="${id//-/\\x2d}"   # a dash inside the id is written the way systemd writes it (plasma\x2dsystemmonitor)
    hex=$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')
    [[ "$hex" =~ ^[0-9a-f]{32}$ ]] || hex=$(printf '%08x%08x%08x%08x' "$(date +%s)" "$$" "$((RANDOM << 15 | RANDOM))" "$((RANDOM << 15 | RANDOM))")
    _scope_out=("$run" --user --scope --quiet --collect
                "--unit=app-${id}-${hex}.scope"
                "--description=${term} (nudge update session)" --)
}

# --- Launch the runner inside a terminal emulator ---
# Usage: _pkgmgr_launch_terminal <terminal> <self> <session>
# The terminal is started in the background and its pid lands in
# _PKGMGR_TERM_PID. The session's end is read from the status file, not from
# the terminal: a window the user keeps open (another tab), or a terminal
# that hands the command to an instance already running, says nothing about
# the runner. The window outlives nudge, so it must not carry what is
# nudge's: the instance lock's descriptor (a shell opened in that window
# would hold the lock, and the next run would step aside) and the trigger
# variable (a `nudge` typed in that window would exit like a login run).
_PKGMGR_TERM_PID=""
_pkgmgr_launch_terminal() {
    local term="$1" self="$2" sess="$3"
    local path
    _PKGMGR_TERM_PID=""
    path=$(_terminal_path "$term") || return 1
    local -a cmd=(bash "$self" --_run-upgrade "$sess")
    local -a argv=() wrap=()
    local quoted
    case "$term" in
        konsole)         argv=("$path" -e "${cmd[@]}") ;;
        gnome-terminal)  argv=("$path" --wait -- "${cmd[@]}") ;;
        xfce4-terminal)  argv=("$path" --disable-server -x "${cmd[@]}") ;;
        alacritty)       argv=("$path" -e "${cmd[@]}") ;;
        kitty)           argv=("$path" "${cmd[@]}") ;;
        foot)            argv=("$path" "${cmd[@]}") ;;
        wezterm)         argv=("$path" start --always-new-process -- "${cmd[@]}") ;;
        tilix)
            # tilix takes one string and splits it itself; %q survives that parser
            printf -v quoted '%q ' "${cmd[@]}"
            argv=("$path" --new-process -e "${quoted% }")
            ;;
        terminator)      argv=("$path" -x "${cmd[@]}") ;;
        x-terminal-emulator|xterm) argv=("$path" -e "${cmd[@]}") ;;
        *) return 1 ;;
    esac
    _pkgmgr_scope_words wrap "$term" "$path"
    (
        unset _NUDGE_TRIGGER
        [[ "${LOCK_FD:-}" =~ ^[0-9]+$ ]] && { exec {LOCK_FD}>&- 2>/dev/null || true; }
        exec "${wrap[@]}" "${argv[@]}"
    ) <&0 2>/dev/null &
    _PKGMGR_TERM_PID=$!
}

# The names on a status line that pass the name rule, space-separated
_pkgmgr_status_names() {
    local -a names=() kept=()
    local n
    read -ra names <<< "${1:-}"
    for n in "${names[@]}"; do
        if declare -F retry_valid_name >/dev/null 2>&1; then retry_valid_name "$n" || continue
        else LC_ALL=C bash -c '[[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9+._:/@-]{0,127}$ ]]' _ "$n" 2>/dev/null || continue; fi
        kept+=("$n")
    done
    printf '%s' "${kept[*]:-}"
}

# --- Read the runner's status file into _UPG_* ---
_pkgmgr_read_status() {
    local status_file="$1" line key value
    [[ -f "$status_file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^([a-z_]+)=(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
        case "$key" in
            cancelled)        _UPG_CANCELLED="${value//[!0-9]/}" ;;
            system)           _UPG_SYSTEM="$value" ;;
            flatpak)          _UPG_FLATPAK="$value" ;;
            snap)             _UPG_SNAP="$value" ;;
            selected_system)  _UPG_SELECTED_SYSTEM="${value//[!0-9]/}" ;;
            selected_flatpak) _UPG_SELECTED_FLATPAK="${value//[!0-9]/}" ;;
            selected_snap)    _UPG_SELECTED_SNAP="${value//[!0-9]/}" ;;
            snapshot_id)      _UPG_SNAPSHOT_ID="${value//[[:cntrl:]]/}" ;;
            total_system)     _UPG_TOTAL_SYSTEM="${value//[!0-9]/}" ;;
            total_flatpak)    _UPG_TOTAL_FLATPAK="${value//[!0-9]/}" ;;
            total_snap)       _UPG_TOTAL_SNAP="${value//[!0-9]/}" ;;
            attempts)         _UPG_ATTEMPTS="${value//[!0-9]/}" ;;
            retry_declined)   _UPG_RETRY_DECLINED="${value//[!0-9]/}" ;;
            report)
                # a report the dialogs may open: our own private file in the reports directory
                if declare -F retry_report_trusted >/dev/null 2>&1 && retry_report_trusted "$value"; then
                    _UPG_REPORT="$value"
                fi ;;
            cause_system|cause_flatpak|cause_snap)
                [[ "$value" =~ ^[a-z][a-z0-9-]{0,31}$ ]] && _UPG_CAUSE["${key#cause_}"]="$value" ;;
            fails_system|fails_flatpak|fails_snap)
                _UPG_FAILS["${key#fails_}"]="${value//[!0-9]/}" ;;
            culprits_system|culprits_flatpak|culprits_snap)
                _UPG_CULPRITS["${key#culprits_}"]=$(_pkgmgr_status_names "$value") ;;
            left_system|left_flatpak|left_snap)
                _UPG_LEFT["${key#left_}"]=$(_pkgmgr_status_names "$value") ;;
            left_cause_system|left_cause_flatpak|left_cause_snap)
                [[ "$value" =~ ^[a-z][a-z0-9-]{0,31}$ ]] && _UPG_LEFT_CAUSE["${key#left_cause_}"]="$value" ;;
            waiting_system|waiting_flatpak|waiting_snap)
                _UPG_WAITING["${key#waiting_}"]=$(_pkgmgr_status_names "$value") ;;
            waiting_cause_system|waiting_cause_flatpak|waiting_cause_snap)
                [[ "$value" =~ ^[a-z][a-z0-9-]{0,31}$ ]] && _UPG_WAITING_CAUSE["${key#waiting_cause_}"]="$value" ;;
        esac
    done < "$status_file"
    [[ -z "$_UPG_ATTEMPTS" ]] && _UPG_ATTEMPTS=1
    [[ -z "$_UPG_RETRY_DECLINED" ]] && _UPG_RETRY_DECLINED=0
    return 0
}

# A pid that is a nudge runner, alive (its command line carries --_run-upgrade)
_pkgmgr_runner_alive() {
    local pid="$1"
    local -a words=()
    [[ "$pid" =~ ^[1-9][0-9]{0,9}$ ]] || return 1
    # 2>/dev/null before the open: a pid that has just gone would otherwise print the error
    mapfile -d '' -t words 2>/dev/null < "/proc/$pid/cmdline" || return 1
    [[ " ${words[*]} " == *" --_run-upgrade "* ]]
}

# The last pid= and done= lines of a status file, into _PKGMGR_ST_PID / _PKGMGR_ST_DONE
_PKGMGR_ST_PID=""
_PKGMGR_ST_DONE=""
_pkgmgr_status_progress() {
    local status_file="$1" line
    _PKGMGR_ST_PID=""; _PKGMGR_ST_DONE=""
    [[ -r "$status_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            pid=*)  _PKGMGR_ST_PID="${line#pid=}" ;;
            done=*) _PKGMGR_ST_DONE="${line#done=}" ;;
        esac
    done < "$status_file"
}

# --- Wait for the runner to finish ---
# Usage: _pkgmgr_wait_session <status file> [terminal pid]
# The status file is the signal. The terminal may return before the runner
# does (some emulators hand the command to an instance already running) or
# long after it (a window the user keeps open with other tabs): neither is
# the session's end. Once the runner reports done it still holds its window
# for "Press Enter to close"; the wait follows the runner's process out, for
# a bounded time, so the summary comes after the window rather than over it.
_pkgmgr_wait_session() {
    local status_file="$1" term_pid="${2:-}" waited=0 held=0 term_rc=""
    local max_wait="${NUDGE_SESSION_MAX_WAIT:-21600}"   # 6 hours
    local hold_wait="${NUDGE_SESSION_HOLD_WAIT:-300}"   # 5 minutes after done
    [[ "$max_wait" =~ ^[0-9]+$ ]] && max_wait=$((10#$max_wait)) || max_wait=21600
    [[ "$hold_wait" =~ ^[0-9]+$ ]] && hold_wait=$((10#$hold_wait)) || hold_wait=300
    while [[ "$waited" -lt "$max_wait" ]]; do
        _pkgmgr_status_progress "$status_file"
        if [[ -n "$_PKGMGR_ST_DONE" ]]; then
            while [[ "$held" -lt "$hold_wait" ]] && _pkgmgr_runner_alive "$_PKGMGR_ST_PID"; do
                sleep 1
                held=$((held + 1))
            done
            return 0
        fi
        if [[ -n "$_PKGMGR_ST_PID" ]]; then
            if ! _pkgmgr_runner_alive "$_PKGMGR_ST_PID"; then
                # done= is written before the runner exits: it may have finished between the read above and this check
                _pkgmgr_status_progress "$status_file"
                [[ -n "$_PKGMGR_ST_DONE" ]] && return 0
                return 1   # runner died without finishing (or the file is not ours)
            fi
        elif [[ -z "$term_rc" && -n "$term_pid" ]] && ! kill -0 "$term_pid" 2>/dev/null; then
            # The terminal is gone and no runner has reported. A failure (systemd-run
            # refused, the exec failed, a crash) is final; exit 0 means it handed the
            # command to an instance already running, which may still be opening the
            # window, so the wait goes on to the limit below. The status is read once:
            # bash keeps it for a reaped child, and a second wait would not have it.
            term_rc=0
            wait "$term_pid" 2>/dev/null || term_rc=$?
            [[ "$term_rc" -eq 0 ]] || return 1
        elif [[ "$waited" -ge 60 ]]; then
            return 1       # terminal never started the runner
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

# --- Session files an earlier run left behind ---
# A run that ended while it still waited (a logout, a reboot) leaves its
# session file and status behind. Once their runner is gone and they are an
# hour old they are removed; the instance lock keeps another run from using
# them meanwhile.
_pkgmgr_sweep_sessions() {
    local dir="${NUDGE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nudge}" f base
    [[ -d "$dir" ]] || return 0
    local -a old=()
    mapfile -t old < <(find "$dir" -maxdepth 1 -type f -name 'upgrade-session.??????*' -mmin +60 2>/dev/null)
    for f in "${old[@]}"; do
        base="${f%.status}"
        _pkgmgr_status_progress "${base}.status"
        [[ -n "$_PKGMGR_ST_PID" ]] && _pkgmgr_runner_alive "$_PKGMGR_ST_PID" && continue
        rm -f -- "$base" "${base}.status" 2>/dev/null || true
    done
    return 0
}

# 0 when the only thing that went wrong is the user answering no at the
# package manager's own question: nothing changed, and they said so
_pkgmgr_declined_at_question() {
    [[ "$_UPG_SYSTEM" == "failed" ]] || return 1
    [[ "${_UPG_CAUSE[system]:-}" == "declined" ]] || return 1
    [[ "$_UPG_FLATPAK" != "failed" && "$_UPG_SNAP" != "failed" ]]
}

# --- Run the upgrade session in a terminal and collect the result ---
# Usage: pkgmgr_upgrade [scope]
# Returns 0 when the session completed, 1 when it failed or never ran,
# 2 when the user cancelled at the selection menu, 3 when they answered no
# at the package manager's own question, 4 when nothing failed and nothing
# could go in (all of it waits for its download). Details land in _UPG_*.
pkgmgr_upgrade() {
    local scope="${1:-all}"
    _UPG_CANCELLED=0
    _UPG_SYSTEM="skipped"; _UPG_FLATPAK="skipped"; _UPG_SNAP="skipped"
    _UPG_SELECTED_SYSTEM=0; _UPG_SELECTED_FLATPAK=0; _UPG_SELECTED_SNAP=0
    _UPG_SNAPSHOT_ID=""
    _UPG_ATTEMPTS=1; _UPG_RETRY_DECLINED=0; _UPG_REPORT=""
    _UPG_CAUSE=(); _UPG_FAILS=(); _UPG_CULPRITS=(); _UPG_LEFT=(); _UPG_LEFT_CAUSE=()
    _UPG_WAITING=(); _UPG_WAITING_CAUSE=()

    local self="${NUDGE_SELF:-}"
    if [[ -z "$self" || ! -f "$self" ]]; then
        log_error "Cannot locate nudge.sh to run the upgrade session"
        return 1
    fi

    local term
    term=$(_detect_terminal)
    if [[ "$term" == "none" ]]; then
        log_error "No terminal emulator found (install konsole, gnome-terminal, xfce4-terminal, or xterm)"
        return 1
    fi

    _pkgmgr_sweep_sessions
    local sess
    sess=$(pkgmgr_write_session "$scope") || return 1
    local status_file="${sess}.status"
    ( umask 077; : > "$status_file" ) || return 1

    log_info "Opening the upgrade session in $term"
    if ! _pkgmgr_launch_terminal "$term" "$self" "$sess" 2>/dev/null; then
        log_error "Could not open $term for the upgrade session"
        rm -f "$sess" "$status_file" 2>/dev/null || true
        return 1
    fi

    local rc=0
    if ! _pkgmgr_wait_session "$status_file" "$_PKGMGR_TERM_PID"; then
        log_error "The upgrade session ended without reporting"
        rc=1
    fi
    _pkgmgr_read_status "$status_file" || true
    rm -f "$sess" "$status_file" 2>/dev/null || true

    [[ "$rc" -ne 0 ]] && return 1
    [[ "$_UPG_CANCELLED" == "1" ]] && return 2
    if [[ "$_UPG_SYSTEM" == "failed" ]]; then
        _pkgmgr_declined_at_question && { _UPG_SYSTEM="declined"; return 3; }
        return 1
    fi
    if [[ "$_UPG_SYSTEM" == "waiting" && "$_UPG_FLATPAK" != "ok" && "$_UPG_SNAP" != "ok" \
          && "$_UPG_FLATPAK" != "failed" && "$_UPG_SNAP" != "failed" ]]; then
        return 4
    fi
    return 0
}

# ============================================================
# The upgrade session: runner side (inside the terminal)
# ============================================================

_RUNNER_STATUS=""
_RUNNER_PKGMGR=""
_RUNNER_ARCH=""
_RUNNER_SCOPE="pick"   # a session without a scope line means nobody chose yet: the menu
_RUNNER_STEP_LOG=""    # where the running step's stderr is also written (lib/retry.sh reads it)
_RUNNER_LAST_RC=0      # the exit code of the last command a step ran
declare -gA _RUNNER_LEFT=()        # per list: what this session left out because it could not be downloaded
declare -gA _RUNNER_LEFT_CAUSE=()  # per list: the cause of the failure that left them out
declare -gA _RUNNER_WAITING=()     # per list: standard updates set aside this session, waiting for their download
declare -gA _RUNNER_WAITING_CAUSE=()
declare -gA _RUNNER_AUTO_OFF=()    # per list: rows nudge unticked itself (held back, set aside, left out, deferred)
declare -gA _RUNNER_DEFERRED=()    # per list: what a full upgrade would leave for later (the phased rollout)
_RUNNER_APT_FRESH=false            # apt's package lists were refreshed in this session
_RUNNER_SIMULATED=false            # the full upgrade's share was worked out since the last refresh
_RUNNER_HELD=""                    # what the check held back before the session (the session's waiting= line)

_runner_status_write() {
    [[ -n "$_RUNNER_STATUS" ]] || return 0
    printf '%s=%s\n' "$1" "$2" >> "$_RUNNER_STATUS" 2>/dev/null || true
}

_runner_hold() {
    echo ""
    # only with a terminal that opens; the prompt is printed by itself, because
    # read writes a -p prompt to stderr, which this read has to keep quiet
    { : </dev/tty; } 2>/dev/null || return 0
    printf '    Press Enter to close this window.'
    read -r _ 2>/dev/null </dev/tty || true
}

_runner_finish() {
    _runner_status_write "done" 1
    _runner_hold
}

# Targets are validated before they reach a command line
_runner_valid_target() {
    local kind="$1" target="$2"
    case "$kind" in
        system)  [[ "$target" =~ ^[A-Za-z0-9][A-Za-z0-9+._-]*(:[A-Za-z0-9_-]+)?$ ]] ;;
        flatpak) [[ "$target" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] ;;
        snap)    [[ "$target" =~ ^[a-z0-9][a-z0-9-]*$ ]] ;;
        *) return 1 ;;
    esac
}

# Parse the session file into the selection model
_runner_load_session() {
    local sess="$1"
    if [[ ! -f "$sess" ]]; then
        echo "nudge: session file not found: $sess" >&2
        return 1
    fi
    local owner mode
    owner=$(stat -c %u "$sess" 2>/dev/null) || owner=""
    mode=$(stat -c %a "$sess" 2>/dev/null) || mode=""
    if [[ -L "$sess" || "$owner" != "$UID" || "$mode" != "600" ]]; then
        echo "nudge: session file is not a private file owned by this user, refusing" >&2
        return 1
    fi

    select_reset
    _RUNNER_SCOPE="pick"
    _RUNNER_HELD=""
    local section="" line native
    local name from_ver to_ver priority arch sec kind ref app label info target sub
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        case "$line" in
            pkgmgr=*) _RUNNER_PKGMGR="${line#pkgmgr=}"; continue ;;
            arch=*)   _RUNNER_ARCH="${line#arch=}"; continue ;;
            waiting=*)
                local held_t
                local -a held_words=()
                read -ra held_words <<< "${line#waiting=}"
                for held_t in "${held_words[@]}"; do
                    _runner_valid_target system "$held_t" && _RUNNER_HELD+="${_RUNNER_HELD:+ }${held_t}"
                done
                continue ;;
            scope=*)
                _RUNNER_SCOPE="${line#scope=}"
                case "$_RUNNER_SCOPE" in
                    all|important|system|flatpak|snap|pick) ;;
                    *) _RUNNER_SCOPE="pick" ;;
                esac
                continue ;;
            "[system]"|"[flatpak]"|"[snap]") section="${line//[][]/}"; continue ;;
        esac
        case "$section" in
            system)
                IFS='|' read -r name from_ver to_ver priority arch sec <<< "$line"
                [[ -z "$name" ]] && continue
                target="$name"
                if [[ -n "$arch" && -n "$_RUNNER_ARCH" && "$arch" != "$_RUNNER_ARCH" && "$arch" != "all" && "$_RUNNER_PKGMGR" == "apt" ]]; then
                    target="${name}:${arch}"
                fi
                _runner_valid_target system "$target" || continue
                case "$priority" in
                    CRITICAL) sub="critical" ;;
                    SECURITY) sub="security" ;;
                    *)        sub="standard" ;;
                esac
                label="$target"
                info=""
                if [[ -n "$from_ver" ]]; then info="${from_ver} → ${to_ver}"
                elif [[ -n "$to_ver" ]]; then info="→ ${to_ver}"; fi
                select_add system "$sub" "${label//[[:cntrl:]]/}" "$target" "${info//[[:cntrl:]]/}"
                ;;
            flatpak)
                IFS='|' read -r kind ref app name to_ver <<< "$line"
                [[ -z "$ref" ]] && continue
                _runner_valid_target flatpak "$ref" || continue
                sub="app"; [[ "$kind" == "runtime" ]] && sub="runtime"
                label="${name:-$app}"
                [[ -n "$app" && "$app" != "$name" ]] && label+="  ($app)"
                info=""
                [[ -n "$to_ver" ]] && info="→ ${to_ver}"
                select_add flatpak "$sub" "${label//[[:cntrl:]]/}" "$ref" "${info//[[:cntrl:]]/}"
                ;;
            snap)
                IFS='|' read -r name to_ver _ _ _ <<< "$line"
                [[ -z "$name" ]] && continue
                _runner_valid_target snap "$name" || continue
                label="$name"
                info=""
                [[ -n "$to_ver" ]] && info="→ ${to_ver}"
                select_add snap snap "${label//[[:cntrl:]]/}" "$name" "${info//[[:cntrl:]]/}"
                ;;
        esac
    done < "$sess"

    case "$_RUNNER_PKGMGR" in
        apt|dnf|pacman|zypper) ;;
        *) echo "nudge: unknown package manager in session: ${_RUNNER_PKGMGR:-none}" >&2; return 1 ;;
    esac
    select_set_list_title system "System packages (${_RUNNER_PKGMGR})"
    [[ "$_RUNNER_PKGMGR" == "pacman" ]] && select_mark_atomic system
    DETECTED_PKGMGR="$_RUNNER_PKGMGR"
    return 0
}

# sudo by its real path, so a PATH entry of the user's cannot stand in for it
_runner_sudo() {
    if [[ -x /usr/bin/sudo ]]; then echo /usr/bin/sudo; else echo sudo; fi
}

# A result line, with lib/tui.sh when it is loaded
_runner_result() {
    if declare -F _tui_result >/dev/null 2>&1; then _tui_result "$1" "$2"; else printf '    %s %s\n' "$1" "$2"; fi
}

# Run a command; its stderr is also written to _RUNNER_STEP_LOG when one is
# set, so a failure can be read afterwards. stdout stays on the terminal (apt
# keeps its progress bar, and prints no scripting warning) and sudo keeps its
# prompt, which goes to the tty directly. The exit code is the command's own.
_runner_exec_argv() {
    local rc=0
    if [[ -n "$_RUNNER_STEP_LOG" ]]; then
        # the exit code below is the command's own whatever the caller's
        # options: pipefail is this function's, restored on return
        local -
        set -o pipefail
        # one command's words at a time: what an earlier, successful command
        # warned about must not be read as the reason this one failed
        : > "$_RUNNER_STEP_LOG" 2>/dev/null || true
        # tee -i ignores the Ctrl-C that apt and dpkg defer, so their stderr
        # has somewhere to go until they stop; tee ends when the pipe closes,
        # so a child the command leaves behind holding its stderr would keep
        # the step open until that child exits
        { "$@" 2>&1 1>&3 | tee -ia "$_RUNNER_STEP_LOG" >&2 || rc="${PIPESTATUS[0]}"; } 3>&1
    else
        "$@" || rc=$?
    fi
    _RUNNER_LAST_RC="$rc"
    return "$rc"
}

_runner_run_step() {
    # Usage: _runner_run_step <title> <command...>
    local title="$1"; shift
    local -a argv=("$@")
    [[ "${argv[0]}" == "sudo" ]] && argv[0]=$(_runner_sudo)
    echo ""
    _tui_operation_header "$title"
    printf '    %b$ %s%b\n\n' "${_TUI_SHADOW:-}" "$*" "${_TUI_RESET:-}"
    local rc=0
    _runner_exec_argv "${argv[@]}" || rc=$?
    echo ""
    if [[ "$rc" -eq 0 ]]; then
        _runner_result ok "${title}: done"
        return 0
    fi
    _runner_result fail "${title}: exit ${rc}"
    return 1
}

# Nothing ran: the step failed in nudge, not in the package manager. The
# diagnosis reads the line, and the failure is not held against any update.
_runner_refused() {
    _RUNNER_LAST_RC=1
    [[ -n "$_RUNNER_STEP_LOG" ]] && printf 'E: nudge: %s\n' "$1" >> "$_RUNNER_STEP_LOG" 2>/dev/null
    return 0
}

# Run a command string from the grammar (config_parse_update_command): each
# " && " part becomes its own argument vector; no shell is involved.
# The parts are read into an array first and run from a for loop, so each
# command keeps the runner's own standard input: the terminal, where the
# package manager's "[Y/n]" is answered. Run from inside a `while read`
# over the parsed text, a command would read that text's end instead, and
# apt would print "Abort." and leave before anyone saw the question.
# 0 when a command is apt refreshing its package lists (apt update, sudo apt-get -q update)
_runner_is_apt_refresh() {
    local -a w=("$@")
    [[ "${#w[@]}" -gt 0 && "${w[0]##*/}" == "sudo" ]] && w=("${w[@]:1}")
    [[ "${#w[@]}" -ge 2 ]] || return 1
    case "${w[0]##*/}" in apt|apt-get) ;; *) return 1 ;; esac
    local x seen=false
    for x in "${w[@]:1}"; do
        case "$x" in
            -*) ;;
            update) seen=true ;;
            *) return 1 ;;
        esac
    done
    [[ "$seen" == "true" ]]
}

_runner_exec_command() {
    local cmdline="$1" line
    local parsed
    if ! parsed=$(config_parse_update_command "$cmdline"); then
        printf '    %b[!] The update command was rejected: %s%b\n' "${_TUI_WARNING:-}" "${_UPDATE_COMMAND_ERROR:-invalid}" "${_TUI_RESET:-}"
        _runner_refused "the update command was rejected: ${_UPDATE_COMMAND_ERROR:-invalid}"
        return 1
    fi
    local -a lines=()
    mapfile -t lines <<< "$parsed"
    local rc=0
    for line in "${lines[@]}"; do
        [[ -z "$line" ]] && continue
        local -a argv=()
        read -ra argv <<< "$line"
        [[ "${argv[0]}" == "sudo" ]] && argv[0]=$(_runner_sudo)
        printf '    %b$ %s%b\n' "${_TUI_SHADOW:-}" "$line" "${_TUI_RESET:-}"
        rc=0
        _runner_exec_argv "${argv[@]}" || rc=$?
        if [[ "$rc" -ne 0 ]]; then
            echo ""
            _runner_result fail "${line}: exit ${rc}"
            return 1
        fi
        _runner_is_apt_refresh "${argv[@]}" && { _RUNNER_APT_FRESH=true; _RUNNER_SIMULATED=false; }
    done
    echo ""
    _runner_result ok "done"
    return 0
}

_runner_apply_system() {
    select_has system || { _runner_status_write system skipped; return 0; }
    if ! select_any_on system; then
        _runner_status_write system skipped
        return 0
    fi
    local -a pkgs=()
    local ok=true
    if select_all_on system; then
        local cmd
        cmd=$(_build_upgrade_cmd) || {
            _runner_refused "no upgrade command for ${_RUNNER_PKGMGR:-this package manager}"
            _runner_status_write system failed
            return 1
        }
        echo ""
        _tui_operation_header "System packages: full upgrade"
        _runner_exec_command "$cmd" || ok=false
    else
        mapfile -t pkgs < <(select_targets system)
        case "$_RUNNER_PKGMGR" in
            apt)
                # the lists were refreshed a moment ago when an earlier try did it
                if [[ "$_RUNNER_APT_FRESH" != "true" ]]; then
                    _runner_run_step "System packages: refresh" sudo apt-get update || ok=false
                    [[ "$ok" == "true" ]] && { _RUNNER_APT_FRESH=true; _RUNNER_SIMULATED=false; }
                fi
                if [[ "$ok" == "true" && "$_RUNNER_SIMULATED" != "true" ]] && _runner_auto_partial system; then
                    _runner_as_full_upgrade system
                    mapfile -t pkgs < <(select_targets system)
                    if [[ "${#pkgs[@]}" -eq 0 ]]; then
                        # nothing the full upgrade would install now: nothing failed, nothing went in
                        _runner_status_write system waiting
                        return 0
                    fi
                fi
                if [[ "$ok" == "true" ]]; then
                    _runner_run_step "System packages: ${#pkgs[@]} selected" sudo apt-get install --only-upgrade -- "${pkgs[@]}" || ok=false
                fi
                ;;
            dnf)
                _runner_run_step "System packages: ${#pkgs[@]} selected" sudo dnf upgrade -y "${pkgs[@]}" || ok=false
                ;;
            zypper)
                _runner_run_step "System packages: ${#pkgs[@]} selected" sudo zypper update -y "${pkgs[@]}" || ok=false
                ;;
            pacman)
                # Never a partial upgrade on Arch; the menu does not offer one
                local cmd
                cmd=$(_build_upgrade_cmd)
                _runner_exec_command "$cmd" || ok=false
                ;;
        esac
    fi
    if [[ "$ok" == "true" ]]; then
        _runner_status_write system ok
        return 0
    fi
    _runner_status_write system failed
    return 1
}

_runner_apply_flatpak() {
    select_has flatpak || { _runner_status_write flatpak skipped; return 0; }
    select_any_on flatpak || { _runner_status_write flatpak skipped; return 0; }
    local ok=true
    if select_all_on flatpak; then
        _runner_run_step "Flatpak: all updates" flatpak update -y || ok=false
    else
        local -a refs=()
        mapfile -t refs < <(select_targets flatpak)
        _runner_run_step "Flatpak: ${#refs[@]} selected" flatpak update -y "${refs[@]}" || ok=false
    fi
    if [[ "$ok" == "true" ]]; then _runner_status_write flatpak ok; return 0; fi
    _runner_status_write flatpak failed
    return 1
}

_runner_apply_snap() {
    select_has snap || { _runner_status_write snap skipped; return 0; }
    select_any_on snap || { _runner_status_write snap skipped; return 0; }
    local ok=true
    if select_all_on snap; then
        _runner_run_step "Snap: all refreshes" sudo snap refresh || ok=false
    else
        local -a names=()
        mapfile -t names < <(select_targets snap)
        _runner_run_step "Snap: ${#names[@]} selected" sudo snap refresh "${names[@]}" || ok=false
    fi
    if [[ "$ok" == "true" ]]; then _runner_status_write snap ok; return 0; fi
    _runner_status_write snap failed
    return 1
}

_runner_record_counts() {
    local list sel tot
    for list in system flatpak snap; do
        read -r sel tot <<< "$(select_count "$list")"
        _runner_status_write "selected_${list}" "$sel"
        _runner_status_write "total_${list}" "$tot"
    done
}

# What the chosen scope covers, for the greeting
_runner_scope_line() {
    local list sel tot out=""
    for list in system flatpak snap; do
        read -r sel tot <<< "$(select_count "$list")"
        [[ "$tot" -gt 0 ]] || continue
        out+="${out:+ · }${_SEL_LIST_TITLE[$list]}: ${sel} of ${tot}"
    done
    printf '%s' "$out"
}

# The closing lines when everything went through (a failure ends with the
# failures block and, when it keeps happening, the report). What waits is
# said once, quietly; it is not a failure.
_runner_summary() {
    local list sel tot parts="" waiting="" later=""
    local personality="${BUNNY_PERSONALITY:-disney}"
    for list in system flatpak snap; do
        read -r sel tot <<< "$(select_count "$list")"
        [[ -n "${_RUNNER_WAITING[$list]:-}" ]] && waiting+="${waiting:+ }${_RUNNER_WAITING[$list]}"
        [[ -n "${_RUNNER_DEFERRED[$list]:-}" ]] && later+="${later:+ }${_RUNNER_DEFERRED[$list]}"
        [[ "$sel" -gt 0 ]] || continue
        parts+="${parts:+ · }${_SEL_LIST_TITLE[$list]}: ${sel}"
    done
    echo ""
    local -a w=() d=() h=()
    read -ra w <<< "$waiting"
    read -ra d <<< "$later"
    read -ra h <<< "$_RUNNER_HELD"
    if [[ -z "$parts" && $(( ${#w[@]} + ${#d[@]} + ${#h[@]} )) -gt 0 ]]; then
        # nothing could go in this time, and nothing failed
        local msg="nothing to install right now." sub
        [[ "$personality" == "classic" ]] && msg="Nothing to install right now."
        if [[ "${#w[@]}" -gt 0 ]]; then
            sub="$(_runner_names_line "$waiting") will go in once $([[ "${#w[@]}" -eq 1 ]] && echo it || echo they) can be downloaded."
        elif [[ "${#d[@]}" -gt 0 ]]; then
            sub="$(_runner_names_line "$later") will come once the distribution has phased $([[ "${#d[@]}" -eq 1 ]] && echo it || echo them) in."
        else
            sub="$(_runner_names_line "$_RUNNER_HELD") will go in once $([[ "${#h[@]}" -eq 1 ]] && echo it || echo they) can be downloaded."
        fi
        _tui_bunny "$msg" "$sub" "${BUNNY_FACE_NORMAL:-}"
        return 0
    fi
    local done_msg="all done! everything you picked is fresh."
    [[ "$personality" == "classic" ]] && done_msg="Done. Everything selected was updated."
    if [[ -n "${_RUNNER_LEFT[system]:-}${_RUNNER_LEFT[flatpak]:-}${_RUNNER_LEFT[snap]:-}" ]]; then
        done_msg="done! the rest is fresh."
        [[ "$personality" == "classic" ]] && done_msg="Done. The rest was updated."
    elif [[ "${#w[@]}" -gt 0 ]]; then
        done_msg="all done! everything's fresh."
        [[ "$personality" == "classic" ]] && done_msg="Done. Everything available was updated."
    fi
    _tui_bunny "$done_msg" "$parts" "${BUNNY_FACE_HAPPY:-^.^}"
    for list in system flatpak snap; do
        [[ -n "${_RUNNER_LEFT[$list]:-}" ]] || continue
        _runner_result skip "left for later, could not be downloaded: $(_runner_names_line "${_RUNNER_LEFT[$list]}") · nudge tries again next time"
    done
    if [[ "${#w[@]}" -gt 0 ]]; then
        local what="standard updates are"
        [[ "${#w[@]}" -eq 1 ]] && what="standard update is"
        _runner_result skip "${#w[@]} ${what} waiting for a download: $(_runner_names_line "$waiting") (nudge --waiting)"
    fi
    return 0
}

# ============================================================
# When a step does not go through: the retry loop and the report
# ============================================================

_runner_apply_list() {
    case "$1" in
        system)  _runner_apply_system ;;
        flatpak) _runner_apply_flatpak ;;
        snap)    _runner_apply_snap ;;
        *) return 1 ;;
    esac
}

# Open the step's stderr capture (nothing is captured when the directory cannot be made)
_runner_step_begin() {
    local list="$1" attempt="$2"
    _RUNNER_LAST_RC=0
    _RUNNER_STEP_LOG=$(retry_log_path "$list" "$attempt" 2>/dev/null) || _RUNNER_STEP_LOG=""
}

# The step went through: its capture goes, and the ledger and the waiting list forget these names
_runner_step_ok() {
    local list="$1"
    local -a names=()
    mapfile -t names < <(select_targets "$list")
    [[ -n "$_RUNNER_STEP_LOG" ]] && rm -f "$_RUNNER_STEP_LOG" 2>/dev/null
    _RUNNER_STEP_LOG=""
    retry_record_success "$list" "${names[@]}"
    if [[ "${#names[@]}" -gt 0 ]] && declare -F waiting_forget >/dev/null 2>&1; then
        printf '%s\n' "${names[@]}" | waiting_forget "$list" \
            || log_warn "The waiting list could not be written: ${WAITING_FILE:-}"
    fi
    return 0
}

# The step failed: read what it said, count it against the names, keep the
# entry, and put what could not be downloaded on the waiting list
_runner_step_failed() {
    local list="$1" attempt="$2"
    local -a names=()
    mapfile -t names < <(select_targets "$list")
    retry_record_failure "$list" "$_RUNNER_PKGMGR" "$_RUNNER_LAST_RC" "$_RUNNER_STEP_LOG" "$attempt" "${names[@]}"
    _RUNNER_STEP_LOG=""
    _runner_note_waiting "$list"
}

# ============================================================
# The waiting list (lib/waiting.sh): what cannot be downloaded right now
# ============================================================

# The subcategory (and the version it goes to) of each target of a list, in one pass
# Usage: _runner_row_maps <list> <name of the sub map> [name of the version map]
# shellcheck disable=SC2034  # the maps are the caller's, written through namerefs
_runner_row_maps() {
    local list="$1" rm_t rm_sub rm_info
    local -n rm_subs="$2"
    if [[ -n "${3:-}" ]]; then local -n rm_vers="$3"; fi
    while IFS=$'\t' read -r rm_t rm_sub _ rm_info; do
        [[ -n "$rm_t" ]] || continue
        rm_subs["$rm_t"]="$rm_sub"
        [[ -n "${3:-}" ]] || continue
        rm_vers["$rm_t"]=""
        if [[ "$rm_info" == *"→ "* ]]; then
            rm_info="${rm_info##*→ }"
            rm_vers["$rm_t"]="${rm_info%% *}"
        fi
    done < <(select_list_rows "$list")
}

# Put targets of a list on the waiting list, with their severity, the version
# they were to bring, where the download was to come from and the new
# dependency that held them back. Usage: _runner_note_waiting <list> <targets...>
_runner_note_waiting() {
    local list="$1" t sev rows=""
    shift
    [[ $# -gt 0 ]] || return 0
    declare -F waiting_note >/dev/null 2>&1 || return 0
    local -A nw_sub=() nw_ver=()
    _runner_row_maps "$list" nw_sub nw_ver
    for t in "$@"; do
        case "${nw_sub[$t]:-}" in
            critical|security) sev="${nw_sub[$t]}" ;;
            *) sev="standard" ;;
        esac
        rows+="${t}|${sev}|${nw_ver[$t]:-}|$(retry_unfetched_host "$list" "$t")|$(retry_unfetched_via "$list" "$t")"$'\n'
    done
    printf '%s' "$rows" | waiting_note "$list" "${_RETRY_F_CAUSE[$list]:-unknown}" \
        || log_warn "The waiting list could not be written: ${WAITING_FILE:-}"
}

# The important downloads that failed because they are not there to be had
# right now are listed too, by severity. They are not set aside: they keep
# the question, the ledger and the report.
_runner_note_important() {
    local list="$1" t
    local -a imp=()
    [[ -n "${_RETRY_F_UNFETCHED[$list]:-}" ]] || return 0
    retry_cause_waits "${_RETRY_F_CAUSE[$list]:-unknown}" || return 0
    local -A ni_sub=()
    _runner_row_maps "$list" ni_sub
    for t in ${_RETRY_F_UNFETCHED[$list]}; do
        retry_unfetched_auth "$list" "$t" && continue
        case "${ni_sub[$t]:-}" in critical|security) imp+=("$t") ;; esac
    done
    _runner_note_waiting "$list" "${imp[@]}"
}

# Rows nudge unticked itself, as opposed to the user
_runner_auto_off() {
    local list="$1"
    shift
    [[ $# -gt 0 ]] || return 0
    _RUNNER_AUTO_OFF["$list"]="${_RUNNER_AUTO_OFF[$list]:+${_RUNNER_AUTO_OFF[$list]} }$*"
}

# 0 when every unticked row of the list is one nudge unticked itself: the
# user asked for all of it, and a partial install stands in for the full upgrade
_runner_auto_partial() {
    local list="$1" t sub on info any=false
    [[ -n "${_RUNNER_AUTO_OFF[$list]:-}" ]] || return 1
    local -A off=()
    for t in ${_RUNNER_AUTO_OFF[$list]}; do off["$t"]=1; done
    while IFS=$'\t' read -r t sub on info; do
        [[ "$on" == "1" ]] && continue
        [[ -n "${off[$t]:-}" ]] || return 1
        any=true
    done < <(select_list_rows "$list")
    [[ "$any" == "true" ]]
}

# The kind of upgrade the configured command does: full (full-upgrade,
# dist-upgrade, the default) or plain (upgrade)
_runner_upgrade_kind() {
    local cmd
    cmd=$(_build_upgrade_cmd 2>/dev/null) || cmd=""
    case "$cmd" in
        *full-upgrade*|*dist-upgrade*) echo full ;;
        *" upgrade"*) echo plain ;;
        *) echo full ;;
    esac
}

# The line for what a full upgrade would leave for later
# Usage: _runner_deferred_line <names> <true when every one is being phased in>
_runner_deferred_line() {
    if [[ "$2" == "true" ]]; then
        _runner_result skip "still being phased in, so left for later as a full upgrade would: $(_runner_names_line "$1")"
    else
        _runner_result skip "left for later as a full upgrade would: $(_runner_names_line "$1")"
    fi
}

# A partial install that stands in for the full upgrade installs what the
# full upgrade would, and no more: what it leaves for later (an update the
# distribution is still phasing in) is unticked here too. Nothing changes
# when apt cannot say. With "quiet", the line is the caller's to print
# (_RUNNER_LAST_DEFERRED and _RUNNER_LAST_DEFERRED_PHASED say what).
# Usage: _runner_as_full_upgrade <list> [quiet]
_RUNNER_LAST_DEFERRED=""
_RUNNER_LAST_DEFERRED_PHASED=false
_runner_as_full_upgrade() {
    local list="$1" quiet="${2:-}" sim t kind word sel
    _RUNNER_LAST_DEFERRED=""
    _RUNNER_LAST_DEFERRED_PHASED=false
    sim=$(pkgmgr_apt_upgrade_set "$(_runner_upgrade_kind)") || return 0
    _RUNNER_SIMULATED=true
    local -A inst=() phased=()
    while read -r kind word; do
        case "$kind" in
            inst)   inst["$word"]=1 ;;
            phased) phased["$word"]=1 ;;
        esac
    done <<< "$sim"
    local -a later=()
    local all_phased=true
    while IFS= read -r t; do
        [[ -n "$t" && -z "${inst[$t]:-}" ]] || continue
        later+=("$t")
        [[ -n "${phased[$t]:-}" ]] || all_phased=false
    done < <(select_targets "$list")
    [[ "${#later[@]}" -gt 0 ]] || return 0
    select_set_targets "$list" 0 "${later[@]}"
    _runner_auto_off "$list" "${later[@]}"
    _RUNNER_DEFERRED["$list"]="${_RUNNER_DEFERRED[$list]:+${_RUNNER_DEFERRED[$list]} }${later[*]}"
    read -r sel _ <<< "$(select_count "$list")"
    _runner_status_write "selected_${list}" "$sel"
    _RUNNER_LAST_DEFERRED="${later[*]}"
    _RUNNER_LAST_DEFERRED_PHASED="$all_phased"
    [[ "$quiet" == "quiet" ]] || _runner_deferred_line "${later[*]}" "$all_phased"
}

# What the check held back is not ticked, whatever the scope; the menu says why
_runner_hold_waiting() {
    local -a held=()
    [[ -n "$_RUNNER_HELD" ]] || return 0
    read -ra held <<< "$_RUNNER_HELD"
    select_set_targets system 0 "${held[@]}"
    select_note_targets system "waiting for its download" "${held[@]}"
    _runner_auto_off system "${held[@]}"
}

# What this failure sets aside: the standard updates among the downloads that
# failed, when the cause means the download is not there to be had right now
# (the network, the repository, the mirror: not a full disk, a lock or sudo)
# and the server did not want credentials. Critical and security updates are
# never set aside, nor is anything on a list that only updates as a whole.
# Space-separated.
_runner_aside_plan() {
    local list="$1" t
    local -a out=()
    [[ "${SET_ASIDE_STANDARD:-true}" == "true" ]] || return 0
    [[ -n "${_RETRY_F_UNFETCHED[$list]:-}" ]] || return 0
    select_is_atomic "$list" && return 0
    retry_cause_waits "${_RETRY_F_CAUSE[$list]:-unknown}" || return 0
    local -A ap_sub=()
    _runner_row_maps "$list" ap_sub
    for t in ${_RETRY_F_UNFETCHED[$list]}; do
        retry_unfetched_auth "$list" "$t" && continue
        case "${ap_sub[$t]:-standard}" in
            critical|security) ;;
            *) out+=("$t") ;;
        esac
    done
    printf '%s' "${out[*]:-}"
}

# Set these aside: unticked, on the waiting list, off the failure ledger,
# kept for the summary and the launcher. 0 when that explains the whole
# failure of the list. Usage: _runner_set_aside <list> <targets...>
_runner_set_aside() {
    local list="$1" sel cause="${_RETRY_F_CAUSE[$1]:-unknown}" rc=1
    shift
    select_set_targets "$list" 0 "$@"
    _runner_auto_off "$list" "$@"
    _RUNNER_WAITING["$list"]="${_RUNNER_WAITING[$list]:+${_RUNNER_WAITING[$list]} }$*"
    _RUNNER_WAITING_CAUSE["$list"]="$cause"
    # noted while the failure's details are still there
    _runner_note_waiting "$list" "$@"
    retry_set_aside "$list" "$@" && rc=0
    read -r sel _ <<< "$(select_count "$list")"
    _runner_status_write "selected_${list}" "$sel"
    _runner_status_write "waiting_${list}" "${_RUNNER_WAITING[$list]}"
    _runner_status_write "waiting_cause_${list}" "$cause"
    return "$rc"
}

# The calm lines for what was set aside: what, why, and that nothing is needed
# Usage: _runner_aside_lines <list> <others still to install, or -1> <names>
_runner_aside_lines() {
    local list="$1" others="$2" personality="${BUNNY_PERSONALITY:-disney}"
    local -a names=()
    read -ra names <<< "$3"
    local host="" t v vias=""
    for t in "${names[@]}"; do
        [[ -z "$host" ]] && host=$(retry_unfetched_host "$list" "$t")
        v=$(retry_unfetched_via "$list" "$t")
        v="${v%%:*}"
        [[ -n "$v" && " $vias " != *" $v "* ]] && vias+="${vias:+ }${v}"
    done
    local where="their source"
    [[ "${#names[@]}" -eq 1 ]] && where="its source"
    [[ -n "$host" ]] && where="$host"
    local verb="are"
    [[ "${#names[@]}" -eq 1 ]] && verb="is"
    echo ""
    printf '    %b↷%b %s %s waiting%s: %s cannot be reached from here right now.\n' \
        "${_TUI_INFO:-}" "${_TUI_RESET:-}" "$(_runner_names_line "${names[*]}")" "$verb" \
        "${vias:+ for $(_runner_names_line "$vias")}" "$where"
    local next=""
    if [[ "$others" -gt 1 ]]; then next="installing the other ${others} now."
    elif [[ "$others" -eq 1 ]]; then next="installing the other one now."
    elif [[ "$others" -eq 0 ]]; then next="nothing else to install."
    fi
    if [[ "$personality" == "classic" ]]; then
        printf '      %bStandard updates wait on the waiting list and go in once they can be downloaded.%s%b\n' \
            "${_TUI_SHADOW:-}" "${next:+ ${next^}}" "${_TUI_RESET:-}"
    else
        printf '      %bstandard updates wait their turn: they go in once they can be downloaded.%s%b\n' \
            "${_TUI_SHADOW:-}" "${next:+ $next}" "${_TUI_RESET:-}"
    fi
}

# What failed and why, after an attempt
# Usage: _runner_failures_block <attempt> <max> [lists, default: every failed one]
_runner_failures_block() {
    local attempt="$1" max="$2" lists="${3:-$(retry_failed_lists)}" list personality="${BUNNY_PERSONALITY:-disney}"
    local msg="some of that didn't go through."
    [[ "$personality" == "classic" ]] && msg="Some steps failed."
    local sub=""
    if [[ "$attempt" -lt "$max" && "${RETRY_ASK:-true}" == "true" ]]; then
        sub="sometimes it just needs a second go."
        if [[ "$personality" == "classic" ]]; then sub="A second attempt often succeeds."
        elif declare -F bunny_message >/dev/null 2>&1; then sub=$(bunny_message failed 2>/dev/null) || sub="sometimes it just needs a second go."
        fi
    fi
    _tui_bunny "$msg" "$sub" "${BUNNY_FACE_WORRIED:-o.o}"
    local -a names=()
    for list in $lists; do
        read -ra names <<< "${_RETRY_F_CULPRITS[$list]:-}"
        _runner_result fail "${_SEL_LIST_TITLE[$list]} · exit ${_RETRY_F_RC[$list]:-?} · $(retry_cause_headline "${_RETRY_F_CAUSE[$list]}" "$_RUNNER_PKGMGR" "$list" "${names[@]}")"
        printf '      %b%s%b\n' "${_TUI_SHADOW:-}" "$(retry_cause_explain "${_RETRY_F_CAUSE[$list]}" "$_RUNNER_PKGMGR" "$list")" "${_TUI_RESET:-}"
        if [[ -n "${_RETRY_F_UNFETCHED[$list]:-}" ]]; then
            printf '      %bcould not download: %s%b\n' "${_TUI_WARNING:-}" "$(_runner_names_line "${_RETRY_F_UNFETCHED[$list]}")" "${_TUI_RESET:-}"
        fi
        if [[ "${_RETRY_F_STREAK[$list]:-0}" -gt 1 ]]; then
            printf '      %bthe same update has failed %s times now%b\n' "${_TUI_WARNING:-}" "${_RETRY_F_STREAK[$list]}" "${_TUI_RESET:-}"
        fi
    done
}

# Try the failed ones again (or the question given)? Enter or y is yes; n,
# anything else, or no terminal to ask on (EOF) is no, so an unattended
# session never loops. Usage: _runner_ask_retry [question]
_runner_ask_retry() {
    local answer="" tty=false
    { : </dev/tty; } 2>/dev/null && tty=true
    echo ""
    if [[ "$tty" == "true" ]]; then
        # a line typed while the step ran is not the answer: it goes
        while IFS= read -r -t 0 _ 2>/dev/null </dev/tty; do
            IFS= read -r -t 0.2 _ 2>/dev/null </dev/tty || break
        done
    fi
    # the question is printed, not passed to read -p: a prompt from read shows
    # only when stdin is a terminal, and the session may be piped or logged
    printf '    %b▶%b %s [Y/n]: ' "${_TUI_PROMPT:-}" "${_TUI_RESET:-}" "${1:-Try the failed ones again?}"
    if [[ "$tty" == "true" ]]; then
        read -r answer 2>/dev/null </dev/tty || { echo ""; return 1; }
    else
        read -r answer || { echo ""; return 1; }
    fi
    answer="${answer//[[:space:]]/}"
    case "${answer,,}" in
        ""|y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# After the last attempt: the causes go to the status file for the dialogs, and
# once the same update has failed RETRY_REPORT_AFTER times the report is written,
# shown here and handed over
_runner_failure_report() {
    local attempt="$1" list personality="${BUNNY_PERSONALITY:-disney}"
    for list in $(retry_failed_lists); do
        _runner_status_write "cause_${list}" "${_RETRY_F_CAUSE[$list]}"
        _runner_status_write "fails_${list}" "${_RETRY_F_STREAK[$list]:-0}"
        _runner_status_write "culprits_${list}" "${_RETRY_F_CULPRITS[$list]:-}"
    done
    local report=""
    if retry_report_due; then
        if report=$(retry_report_save "$_RUNNER_PKGMGR" "$_RUNNER_SCOPE" "$attempt"); then
            _runner_status_write report "$report"
            local msg="this keeps failing... i wrote down what might help."
            [[ "$personality" == "classic" ]] && msg="The same updates keep failing. The report says what might resolve it."
            _tui_bunny "$msg" "nudge does not run these commands for you." "${BUNNY_FACE_TEARY:-T.T}"
            _tui_operation_header "Failure report"
            retry_report_text "$_RUNNER_PKGMGR" "$_RUNNER_SCOPE" "$attempt" | sed 's/^/    /'
            printf '    %bsaved to %s%b\n' "${_TUI_SHADOW:-}" "$(retry_tilde "$report")" "${_TUI_RESET:-}"
            return 0
        fi
    fi
    local msg="nothing else was changed."
    [[ "$personality" == "classic" ]] && msg="Nothing else was changed."
    _tui_bunny "$msg" "if it fails again i'll write up what might help." "${BUNNY_FACE_WORRIED:-o.o}"
    for list in $(retry_failed_lists); do
        [[ -n "${_RETRY_F_LOG[$list]:-}" ]] && _runner_result skip "${_SEL_LIST_TITLE[$list]}: the error output is at $(retry_tilde "${_RETRY_F_LOG[$list]}")"
    done
    return 0
}

# "a, b, c" for at most eight names, then "and N more"
_runner_names_line() {
    local -a names=()
    read -ra names <<< "${1:-}"
    local shown="${names[*]:0:8}"
    shown="${shown// /, }"
    [[ "${#names[@]}" -gt 8 ]] && shown+=", and $(( ${#names[@]} - 8 )) more"
    printf '%s' "$shown"
}

# What the next try of a failed list leaves out: the selected updates the
# package manager could not download, when that is some but not all of what
# is ticked and another try could go through. Space-separated, or nothing.
_runner_leave_out_plan() {
    local list="$1" sel
    local -a drop=()
    [[ -n "${_RETRY_F_UNFETCHED[$list]:-}" ]] || return 0
    select_is_atomic "$list" && return 0
    retry_cause_retriable "${_RETRY_F_CAUSE[$list]:-unknown}" || return 0
    read -ra drop <<< "${_RETRY_F_UNFETCHED[$list]}"
    read -r sel _ <<< "$(select_count "$list")"
    [[ "${#drop[@]}" -gt 0 && "${#drop[@]}" -lt "$sel" ]] || return 0
    printf '%s' "${drop[*]}"
}

# Untick what could not be downloaded, and keep it for the summary and the launcher
# Usage: _runner_leave_out <list> <targets...>
_runner_leave_out() {
    local list="$1" sel
    shift
    select_set_targets "$list" 0 "$@"
    _runner_auto_off "$list" "$@"
    _RUNNER_LEFT["$list"]="${_RUNNER_LEFT[$list]:+${_RUNNER_LEFT[$list]} }$*"
    _RUNNER_LEFT_CAUSE["$list"]="${_RETRY_F_CAUSE[$list]:-unknown}"
    read -r sel _ <<< "$(select_count "$list")"
    _runner_status_write "selected_${list}" "$sel"
    _runner_status_write "left_${list}" "${_RUNNER_LEFT[$list]}"
    _runner_status_write "left_cause_${list}" "${_RUNNER_LEFT_CAUSE[$list]}"
}

# Every step, then the failed ones again while the user says yes. A standard
# update that cannot be downloaded is set aside without a question, and the
# rest of its list goes in: that is not a failure, and is not shown as one.
_runner_apply_all() {
    local attempt=1 max="${RETRY_MAX_ATTEMPTS:-3}" done_lists=" " given_up=" " failed="" list said_no=false
    [[ "$max" =~ ^[0-9]+$ && "$max" -ge 1 ]] || max=3
    _runner_status_write attempts 1
    while :; do
        failed=""
        for list in system flatpak snap; do
            [[ "$done_lists" == *" $list "* || "$given_up" == *" $list "* ]] && continue
            _runner_step_begin "$list" "$attempt"
            if _runner_apply_list "$list"; then
                done_lists+="$list "
                _runner_step_ok "$list"
            else
                failed+="$list "
                _runner_step_failed "$list" "$attempt"
            fi
        done

        # What only waits comes out first; a list that failed for nothing else
        # goes on with the rest of its updates, or is done when none are left
        local resume="" still="" aside sel tot
        local -a anames=()
        for list in $failed; do
            aside=$(_runner_aside_plan "$list")
            if [[ -n "$aside" ]]; then
                read -ra anames <<< "$aside"
                if _runner_set_aside "$list" "${anames[@]}"; then
                    # what the rest really is: the full upgrade's share of it
                    _RUNNER_LAST_DEFERRED=""
                    if [[ "$list" == "system" && "$_RUNNER_PKGMGR" == "apt" ]] && select_any_on "$list" && _runner_auto_partial "$list"; then
                        _runner_as_full_upgrade "$list" quiet
                    fi
                    read -r sel tot <<< "$(select_count "$list")"
                    _runner_aside_lines "$list" "$sel" "$aside"
                    [[ -n "$_RUNNER_LAST_DEFERRED" ]] && _runner_deferred_line "$_RUNNER_LAST_DEFERRED" "$_RUNNER_LAST_DEFERRED_PHASED"
                    if select_any_on "$list"; then
                        resume+="$list "
                    else
                        _runner_status_write "$list" waiting
                        done_lists+="$list "
                    fi
                    continue
                fi
                _runner_aside_lines "$list" "-1" "$aside"
            fi
            still+="$list "
        done
        failed="$still"
        for list in $failed; do _runner_note_important "$list"; done

        if [[ -z "$failed" ]]; then
            [[ -n "$resume" ]] || break
            # installing the rest is what the user already asked for: no question,
            # and it does not use up an attempt
            attempt=$((attempt + 1))
            max=$((max + 1))
            _runner_status_write attempts "$attempt"
            echo ""
            _tui_operation_header "The rest of the updates"
            continue
        fi

        echo ""
        _runner_failures_block "$attempt" "$max" "$failed"
        local retriable=false ask=false
        local -A plan=()
        for list in $failed; do
            retry_cause_retriable "${_RETRY_F_CAUSE[$list]:-unknown}" && retriable=true
            plan["$list"]=$(_runner_leave_out_plan "$list")
        done
        # once the user has said no, the session does not ask again
        [[ "$attempt" -lt "$max" && "${RETRY_ASK:-true}" == "true" && "$retriable" == "true" && "$said_no" == "false" ]] && ask=true
        if [[ "$ask" == "true" ]]; then
            # An update that cannot be downloaded holds a full upgrade back with
            # it: the next try leaves those out and installs the rest
            local question="Try the failed ones again?" dropped=0 others plural
            local -a drop=()
            for list in $failed; do
                [[ -n "${plan[$list]:-}" ]] || continue
                read -ra drop <<< "${plan[$list]}"
                read -r sel _ <<< "$(select_count "$list")"
                others=$((sel - ${#drop[@]}))
                dropped=$((dropped + ${#drop[@]}))
                plural="s"
                [[ "$others" -eq 1 ]] && plural=""
                echo ""
                if [[ "${#drop[@]}" -eq 1 ]]; then
                    printf '    %b%s other update%s can go in without it; it stays for later.%b\n' \
                        "${_TUI_SHADOW:-}" "$others" "$plural" "${_TUI_RESET:-}"
                else
                    printf '    %b%s other update%s can go in without them; those %s stay for later.%b\n' \
                        "${_TUI_SHADOW:-}" "$others" "$plural" "${#drop[@]}" "${_TUI_RESET:-}"
                fi
            done
            if [[ "$dropped" -eq 1 ]]; then question="Try again without it?"
            elif [[ "$dropped" -gt 1 ]]; then question="Try again without them?"; fi
            if _runner_ask_retry "$question"; then
                for list in $failed; do
                    [[ -n "${plan[$list]:-}" ]] || continue
                    read -ra drop <<< "${plan[$list]}"
                    _runner_leave_out "$list" "${drop[@]}"
                done
            else
                _runner_status_write retry_declined 1
                said_no=true
                ask=false
            fi
        fi
        if [[ "$ask" != "true" ]]; then
            # these stay failed; what was only resuming still goes on
            for list in $failed; do given_up+="$list "; done
            [[ -n "$resume" ]] || break
        fi
        attempt=$((attempt + 1))
        _runner_status_write attempts "$attempt"
        echo ""
        if [[ "$ask" == "true" ]]; then
            _tui_operation_header "Attempt ${attempt} of ${max}"
        else
            _tui_operation_header "The rest of the updates"
        fi
    done
    if [[ -n "$(retry_failed_lists)" ]]; then
        echo ""
        _runner_failure_report "$attempt"
        return 1
    fi
    return 0
}

# --- Entry point: nudge.sh --_run-upgrade <session> ---
pkgmgr_run_upgrade_session() {
    local sess="${1:-}"
    _RUNNER_STATUS="${sess}.status"
    trap '_runner_finish' EXIT

    if ! _runner_load_session "$sess"; then
        _runner_status_write cancelled 1
        return 1
    fi
    _runner_status_write pid "$$"
    _runner_status_write started "$(date -Iseconds 2>/dev/null || date)"
    _runner_status_write scope "$_RUNNER_SCOPE"
    if ! select_apply_scope "$_RUNNER_SCOPE"; then
        _RUNNER_SCOPE="pick"
        select_apply_scope pick
    fi
    _runner_hold_waiting

    local personality="${BUNNY_PERSONALITY:-disney}"
    local face="${BUNNY_FACE_NORMAL:-}"
    _tui_title "nudge · update session"
    _tui_draw_header "nudge · update session"

    if [[ "$_RUNNER_SCOPE" == "pick" ]]; then
        local greeting="pick what to update, then press Enter."
        [[ "$personality" == "classic" ]] && greeting="Choose the updates to apply, then press Enter."
        _tui_bunny "$greeting" "untick anything you want to keep as it is." "$face"
        if ! select_run; then
            _runner_record_counts
            _runner_status_write cancelled 1
            echo ""
            _tui_bunny "okay! nothing touched." "" "$face"
            return 0
        fi
        _tui_clear
        _tui_draw_header "nudge · update session"
        _tui_bunny "here we go! installing what you ticked." "$(_runner_scope_line)" "$face"
    else
        local greeting="here we go! installing what you asked for."
        [[ "$personality" == "classic" ]] && greeting="Applying the selected updates."
        _tui_bunny "$greeting" "$(_runner_scope_line)" "$face"
    fi
    _runner_record_counts

    local any=false
    select_any_on system && any=true
    select_any_on flatpak && any=true
    select_any_on snap && any=true
    if [[ "$any" != "true" ]]; then
        _runner_status_write cancelled 1
        _tui_bunny "nothing ticked, nothing changed." "" "$face"
        return 0
    fi

    # Pre-upgrade snapshot, inside the terminal so sudo can ask
    if [[ "${SNAPSHOT_ENABLED:-false}" == "true" ]] && select_any_on system; then
        echo ""
        _tui_operation_header "Snapshot before the upgrade (${SNAPSHOT_TOOL:-auto})"
        if safety_snapshot; then
            _runner_status_write snapshot_id "${_JSON_DATA[snapshot_id]:-}"
        else
            local go
            go=$(_tui_confirm "The snapshot failed. Continue without one?" "false")
            if [[ "$go" != "true" ]]; then
                _runner_status_write cancelled 1
                _tui_bunny "okay, nothing changed." "" "$face"
                return 0
            fi
        fi
    fi

    # The ledger forgets updates that are no longer pending (installed some other way, or gone)
    local list
    local -a pending=()
    for list in system flatpak snap; do
        mapfile -t pending < <(select_list_targets "$list")
        if [[ "${#pending[@]}" -gt 0 ]]; then
            printf '%s\n' "${pending[@]}" | retry_ledger_prune "$list" \
                || log_warn "The failure ledger could not be written: $RETRY_LEDGER_FILE"
        fi
    done

    if _runner_apply_all; then
        _runner_summary
    fi
    return 0
}
