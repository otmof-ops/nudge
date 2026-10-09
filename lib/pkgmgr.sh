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
pkgmgr_count_updates() {
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

# A known name that resolves to a real program the user cannot modify: the
# file it points at is owned by root and not writable (a read-only shim of
# the user's own would otherwise do, and it is where the sudo password is typed)
# Usage: _terminal_path <name> -> prints the path PATH gave
_terminal_path() {
    local name="$1" path real owner
    [[ " $_KNOWN_TERMINALS " == *" $name "* ]] || return 1
    path=$(type -P "$name" 2>/dev/null) || return 1
    [[ -n "$path" ]] || return 1
    real=$(readlink -f "$path" 2>/dev/null) || return 1
    owner=$(stat -c %u "$real" 2>/dev/null) || return 1
    [[ -n "$real" && -x "$real" && "$owner" == "0" && ! -w "$real" ]] || return 1
    printf '%s' "$path"
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
        echo "[system]"
        [[ -n "$PKG_UPDATE_LIST" ]] && printf '%s\n' "$PKG_UPDATE_LIST"
        echo "[flatpak]"
        [[ -n "$PKG_FLATPAK_LIST" ]] && printf '%s\n' "$PKG_FLATPAK_LIST"
        echo "[snap]"
        [[ -n "$PKG_SNAP_LIST" ]] && printf '%s\n' "$PKG_SNAP_LIST"
    } > "$sess"
    printf '%s' "$sess"
}

# --- Launch the runner inside a terminal emulator ---
# Usage: _pkgmgr_launch_terminal <terminal> <self> <session>
_pkgmgr_launch_terminal() {
    local term="$1" self="$2" sess="$3"
    local path
    path=$(_terminal_path "$term") || return 1
    local -a cmd=(bash "$self" --_run-upgrade "$sess")
    local quoted
    case "$term" in
        konsole)         "$path" -e "${cmd[@]}" ;;
        gnome-terminal)  "$path" --wait -- "${cmd[@]}" ;;
        xfce4-terminal)  "$path" --disable-server -x "${cmd[@]}" ;;
        alacritty)       "$path" -e "${cmd[@]}" ;;
        kitty)           "$path" "${cmd[@]}" ;;
        foot)            "$path" "${cmd[@]}" ;;
        wezterm)         "$path" start --always-new-process -- "${cmd[@]}" ;;
        tilix)
            # tilix takes one string and splits it itself; %q survives that parser
            printf -v quoted '%q ' "${cmd[@]}"
            "$path" --new-process -e "${quoted% }"
            ;;
        terminator)      "$path" -x "${cmd[@]}" ;;
        x-terminal-emulator|xterm) "$path" -e "${cmd[@]}" ;;
        *) return 1 ;;
    esac
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
        esac
    done < "$status_file"
    return 0
}

_pkgmgr_status_value() {
    local status_file="$1" key="$2"
    [[ -f "$status_file" ]] || return 1
    grep -E "^${key}=" "$status_file" 2>/dev/null | tail -1 | cut -d= -f2-
}

# --- Wait for the runner to finish ---
# The terminal may return before the runner does (some emulators hand the
# command to an existing process), so the status file is the real signal.
_pkgmgr_wait_session() {
    local status_file="$1" waited=0 pid=""
    local max_wait="${NUDGE_SESSION_MAX_WAIT:-21600}"   # 6 hours
    while [[ "$waited" -lt "$max_wait" ]]; do
        if [[ -n "$(_pkgmgr_status_value "$status_file" "done" 2>/dev/null || true)" ]]; then
            return 0
        fi
        pid=$(_pkgmgr_status_value "$status_file" pid 2>/dev/null || true)
        if [[ -n "$pid" ]]; then
            # The pid must be a real nudge runner, or the file is lying
            if [[ ! "$pid" =~ ^[1-9][0-9]{0,9}$ ]] \
               || ! grep -qa -- '--_run-upgrade' "/proc/$pid/cmdline" 2>/dev/null; then
                return 1   # runner died without finishing (or the status file is not ours)
            fi
        elif [[ "$waited" -ge 60 ]]; then
            return 1       # terminal never started the runner
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

# --- Run the upgrade session in a terminal and collect the result ---
# Usage: pkgmgr_upgrade [scope]
# Returns 0 when the session completed, 1 when it failed or never ran,
# 2 when the user cancelled at the selection menu. Details land in _UPG_*.
pkgmgr_upgrade() {
    local scope="${1:-all}"
    _UPG_CANCELLED=0
    _UPG_SYSTEM="skipped"; _UPG_FLATPAK="skipped"; _UPG_SNAP="skipped"
    _UPG_SELECTED_SYSTEM=0; _UPG_SELECTED_FLATPAK=0; _UPG_SELECTED_SNAP=0
    _UPG_SNAPSHOT_ID=""

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

    local sess
    sess=$(pkgmgr_write_session "$scope") || return 1
    local status_file="${sess}.status"
    ( umask 077; : > "$status_file" ) || return 1

    log_info "Opening the upgrade session in $term"
    _pkgmgr_launch_terminal "$term" "$self" "$sess" 2>/dev/null || true

    local rc=0
    if ! _pkgmgr_wait_session "$status_file"; then
        log_error "The upgrade session ended without reporting"
        rc=1
    fi
    _pkgmgr_read_status "$status_file" || true
    rm -f "$sess" "$status_file" 2>/dev/null || true

    [[ "$rc" -ne 0 ]] && return 1
    [[ "$_UPG_CANCELLED" == "1" ]] && return 2
    [[ "$_UPG_SYSTEM" == "failed" ]] && return 1
    return 0
}

# ============================================================
# The upgrade session: runner side (inside the terminal)
# ============================================================

_RUNNER_STATUS=""
_RUNNER_PKGMGR=""
_RUNNER_ARCH=""
_RUNNER_SCOPE="pick"   # a session without a scope line means nobody chose yet: the menu

_runner_status_write() {
    [[ -n "$_RUNNER_STATUS" ]] || return 0
    printf '%s=%s\n' "$1" "$2" >> "$_RUNNER_STATUS" 2>/dev/null || true
}

_runner_hold() {
    echo ""
    if [[ -t 0 ]] || [[ -r /dev/tty ]]; then
        read -rp "    Press Enter to close this window." _ 2>/dev/null </dev/tty || true
    fi
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
    local section="" line native
    local name from_ver to_ver priority arch sec kind ref app label info target sub
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        case "$line" in
            pkgmgr=*) _RUNNER_PKGMGR="${line#pkgmgr=}"; continue ;;
            arch=*)   _RUNNER_ARCH="${line#arch=}"; continue ;;
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

_runner_run_step() {
    # Usage: _runner_run_step <title> <command...>
    local title="$1"; shift
    local -a argv=("$@")
    [[ "${argv[0]}" == "sudo" ]] && argv[0]=$(_runner_sudo)
    echo ""
    _tui_operation_header "$title"
    printf '    %b$ %s%b\n\n' "${_TUI_SHADOW:-}" "$*" "${_TUI_RESET:-}"
    local rc=0
    "${argv[@]}" || rc=$?
    echo ""
    if [[ "$rc" -eq 0 ]]; then
        _runner_result ok "${title}: done"
        return 0
    fi
    _runner_result fail "${title}: exit ${rc}"
    return 1
}

# Run a command string from the grammar (config_parse_update_command): each
# " && " part becomes its own argument vector; no shell is involved.
_runner_exec_command() {
    local cmdline="$1" line
    local parsed
    if ! parsed=$(config_parse_update_command "$cmdline"); then
        printf '    %b[!] The update command was rejected: %s%b\n' "${_TUI_WARNING:-}" "${_UPDATE_COMMAND_ERROR:-invalid}" "${_TUI_RESET:-}"
        return 1
    fi
    local rc=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local -a argv=()
        read -ra argv <<< "$line"
        [[ "${argv[0]}" == "sudo" ]] && argv[0]=$(_runner_sudo)
        printf '    %b$ %s%b\n' "${_TUI_SHADOW:-}" "$line" "${_TUI_RESET:-}"
        rc=0
        "${argv[@]}" || rc=$?
        if [[ "$rc" -ne 0 ]]; then
            echo ""
            _runner_result fail "${line}: exit ${rc}"
            return 1
        fi
    done <<< "$parsed"
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
        cmd=$(_build_upgrade_cmd) || { _runner_status_write system failed; return 1; }
        echo ""
        _tui_operation_header "System packages: full upgrade"
        _runner_exec_command "$cmd" || ok=false
    else
        mapfile -t pkgs < <(select_targets system)
        case "$_RUNNER_PKGMGR" in
            apt)
                _runner_run_step "System packages: refresh" sudo apt-get update || ok=false
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

# The closing lines
_runner_summary() {
    local failures="$1" list sel tot parts=""
    local personality="${BUNNY_PERSONALITY:-disney}"
    for list in system flatpak snap; do
        read -r sel tot <<< "$(select_count "$list")"
        [[ "$sel" -gt 0 ]] || continue
        parts+="${parts:+ · }${_SEL_LIST_TITLE[$list]}: ${sel}"
    done
    echo ""
    if [[ "$failures" -eq 0 ]]; then
        local done_msg="all done! everything you picked is fresh."
        [[ "$personality" == "classic" ]] && done_msg="Done. Everything selected was updated."
        _tui_bunny "$done_msg" "$parts" "${BUNNY_FACE_HAPPY:-^.^}"
    else
        local fail_msg="some of that didn't go through."
        [[ "$personality" == "classic" ]] && fail_msg="Some steps failed."
        _tui_bunny "$fail_msg" "read the output above; nothing else was changed." "${BUNNY_FACE_WORRIED:-o.o}"
    fi
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

    local failures=0
    _runner_apply_system || failures=$((failures + 1))
    _runner_apply_flatpak || failures=$((failures + 1))
    _runner_apply_snap || failures=$((failures + 1))

    _runner_summary "$failures"
    return 0
}
