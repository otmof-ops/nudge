#!/usr/bin/env bash
# nudge — lib/pkgmgr.sh
# Package manager abstraction — apt/dnf/pacman/zypper + flatpak + snap
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

# Detected package manager
DETECTED_PKGMGR=""

# Update counts
PKG_UPDATES_TOTAL=0
PKG_UPDATES_SECURITY=0
PKG_UPDATES_CRITICAL=0
PKG_UPDATES_FLATPAK=0
PKG_UPDATES_SNAP=0

# Package list (newline-delimited: name|from|to|priority)
PKG_UPDATE_LIST=""

# Critical package patterns
readonly CRITICAL_PACKAGES="^(linux-image|linux-headers|openssl|libssl|glibc|libc6|openssh|sudo|pam|libpam|systemd)(-|$)"

# --- Detect system package manager ---
detect_pkgmgr() {
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
            if fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1; then
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
                log_warn "Pacman database locked"
                return 1
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

# --- Refresh package index ---
pkgmgr_refresh() {
    log_debug "Refreshing package index ($DETECTED_PKGMGR)"
    case "$DETECTED_PKGMGR" in
        apt)    sudo apt update -qq 2>/dev/null || true ;;
        dnf)    sudo dnf check-update -q 2>/dev/null; true ;;
        pacman) sudo pacman -Sy --noconfirm 2>/dev/null || true ;;
        zypper) sudo zypper refresh -q 2>/dev/null || true ;;
    esac
}

# --- Classify package priority ---
_classify_priority() {
    local pkg_name="$1" is_security="${2:-false}"

    if echo "$pkg_name" | grep -qE "$CRITICAL_PACKAGES"; then
        echo "CRITICAL"
    elif [[ "$is_security" == "true" ]]; then
        echo "SECURITY"
    else
        echo "STANDARD"
    fi
}

# --- Count updates ---
pkgmgr_count_updates() {
    PKG_UPDATES_TOTAL=0
    PKG_UPDATES_SECURITY=0
    PKG_UPDATES_CRITICAL=0

    case "$DETECTED_PKGMGR" in
        apt)
            if [[ -x /usr/lib/update-notifier/apt-check ]]; then
                local apt_out
                apt_out=$(/usr/lib/update-notifier/apt-check 2>&1 || true)
                PKG_UPDATES_TOTAL=$(echo "$apt_out" | cut -d';' -f1)
                PKG_UPDATES_SECURITY=$(echo "$apt_out" | cut -d';' -f2)
            else
                PKG_UPDATES_TOTAL=$(apt list --upgradable 2>/dev/null | grep -c 'upgradable' || true)
                PKG_UPDATES_SECURITY=0
            fi
            ;;
        dnf)
            PKG_UPDATES_TOTAL=$(dnf check-update -q 2>/dev/null | grep -cE '^\S+\s+\S+\s+\S+' || true)
            PKG_UPDATES_SECURITY=$(dnf updateinfo list --security -q 2>/dev/null | grep -c '.' || true)
            ;;
        pacman)
            if command -v checkupdates &>/dev/null; then
                PKG_UPDATES_TOTAL=$(checkupdates 2>/dev/null | wc -l || true)
            else
                PKG_UPDATES_TOTAL=$(pacman -Qu 2>/dev/null | wc -l || true)
            fi
            PKG_UPDATES_SECURITY=0
            ;;
        zypper)
            PKG_UPDATES_TOTAL=$(zypper list-updates 2>/dev/null | grep -cE '^\s*v\s*\|' || true)
            PKG_UPDATES_SECURITY=$(zypper list-patches --category security 2>/dev/null | grep -cE '^\s*\|' || true)
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

# --- List updates with details ---
pkgmgr_list_updates() {
    PKG_UPDATE_LIST=""
    PKG_UPDATES_CRITICAL=0

    case "$DETECTED_PKGMGR" in
        apt)
            local line
            while IFS= read -r line; do
                # Format: package/suite from_ver arch [upgradable from: to_ver]
                if [[ "$line" =~ ^([^/]+)/[[:space:]]*([^[:space:]]+)[[:space:]].*\[upgradable\ from:\ ([^]]+)\] ]]; then
                    local name="${BASH_REMATCH[1]}"
                    local to_ver="${BASH_REMATCH[2]}"
                    local from_ver="${BASH_REMATCH[3]}"
                    local priority
                    priority=$(_classify_priority "$name")
                    [[ "$priority" == "CRITICAL" ]] && PKG_UPDATES_CRITICAL=$((PKG_UPDATES_CRITICAL + 1))
                    PKG_UPDATE_LIST+="${name}|${from_ver}|${to_ver}|${priority}"$'\n'
                fi
            done < <(apt list --upgradable 2>/dev/null | tail -n +2)
            ;;
        dnf)
            while IFS= read -r line; do
                if [[ "$line" =~ ^([^.]+)\.[^[:space:]]+[[:space:]]+([^[:space:]]+) ]]; then
                    local name="${BASH_REMATCH[1]}"
                    local to_ver="${BASH_REMATCH[2]}"
                    local priority
                    priority=$(_classify_priority "$name")
                    [[ "$priority" == "CRITICAL" ]] && PKG_UPDATES_CRITICAL=$((PKG_UPDATES_CRITICAL + 1))
                    PKG_UPDATE_LIST+="${name}||${to_ver}|${priority}"$'\n'
                fi
            done < <(dnf check-update -q 2>/dev/null)
            ;;
        pacman)
            local lister="pacman -Qu"
            command -v checkupdates &>/dev/null && lister="checkupdates"
            while IFS= read -r line; do
                if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+-\>[[:space:]]+([^[:space:]]+) ]]; then
                    local name="${BASH_REMATCH[1]}"
                    local from_ver="${BASH_REMATCH[2]}"
                    local to_ver="${BASH_REMATCH[3]}"
                    local priority
                    priority=$(_classify_priority "$name")
                    [[ "$priority" == "CRITICAL" ]] && PKG_UPDATES_CRITICAL=$((PKG_UPDATES_CRITICAL + 1))
                    PKG_UPDATE_LIST+="${name}|${from_ver}|${to_ver}|${priority}"$'\n'
                fi
            done < <($lister 2>/dev/null)
            ;;
        zypper)
            while IFS='|' read -r _ name _ _ to_ver _; do
                name="${name// /}"
                to_ver="${to_ver// /}"
                [[ -z "$name" ]] && continue
                local priority
                priority=$(_classify_priority "$name")
                [[ "$priority" == "CRITICAL" ]] && PKG_UPDATES_CRITICAL=$((PKG_UPDATES_CRITICAL + 1))
                PKG_UPDATE_LIST+="${name}||${to_ver}|${priority}"$'\n'
            done < <(zypper list-updates 2>/dev/null | grep -E '^\s*v?\s*\|')
            ;;
    esac

    # Remove trailing newline
    PKG_UPDATE_LIST="${PKG_UPDATE_LIST%$'\n'}"
}

# --- Check held/pinned packages ---
pkgmgr_check_held() {
    case "$DETECTED_PKGMGR" in
        apt)
            apt-mark showhold 2>/dev/null
            ;;
        dnf)
            dnf versionlock list 2>/dev/null || true
            ;;
        pacman)
            grep '^IgnorePkg' /etc/pacman.conf 2>/dev/null | cut -d= -f2 || true
            ;;
        zypper)
            zypper locks 2>/dev/null || true
            ;;
    esac
}

# --- Build upgrade command ---
_build_upgrade_cmd() {
    case "$DETECTED_PKGMGR" in
        apt)    echo "${UPDATE_COMMAND:-sudo apt update && sudo apt full-upgrade}" ;;
        dnf)    echo "sudo dnf upgrade -y" ;;
        pacman) echo "sudo pacman -Syu --noconfirm" ;;
        zypper) echo "sudo zypper update -y" ;;
    esac
}

# --- Detect terminal emulator ---
_detect_terminal() {
    if command -v konsole &>/dev/null; then
        echo "konsole"
    elif command -v gnome-terminal &>/dev/null; then
        echo "gnome-terminal"
    elif command -v xfce4-terminal &>/dev/null; then
        echo "xfce4-terminal"
    elif command -v x-terminal-emulator &>/dev/null; then
        echo "x-terminal-emulator"
    else
        echo "xterm"
    fi
}

# --- Run upgrade in terminal ---
pkgmgr_upgrade() {
    local cmd
    cmd=$(_build_upgrade_cmd)
    local term
    term=$(_detect_terminal)

    log_info "Running upgrade: $cmd (terminal: $term)"

    case "$term" in
        konsole)
            konsole --hold -e bash -c "$cmd"
            ;;
        gnome-terminal)
            gnome-terminal -- bash -c "$cmd; echo; echo 'Press Enter to close.'; read -r"
            ;;
        xfce4-terminal)
            xfce4-terminal --hold -e bash -c "$cmd"
            ;;
        *)
            $term -e bash -c "$cmd; echo; echo 'Press Enter to close.'; read -r"
            ;;
    esac
    return $?
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

flatpak_count() {
    PKG_UPDATES_FLATPAK=0
    if flatpak_available; then
        PKG_UPDATES_FLATPAK=$(flatpak remote-ls --updates 2>/dev/null | wc -l || true)
        PKG_UPDATES_FLATPAK="${PKG_UPDATES_FLATPAK//[!0-9]/}"
        [[ -z "$PKG_UPDATES_FLATPAK" ]] && PKG_UPDATES_FLATPAK=0
        log_info "Flatpak updates: $PKG_UPDATES_FLATPAK"
    fi
}

flatpak_list() {
    if flatpak_available; then
        flatpak remote-ls --updates --columns=application,branch 2>/dev/null || true
    fi
}

flatpak_upgrade() {
    if flatpak_available && [[ "$PKG_UPDATES_FLATPAK" -gt 0 ]]; then
        log_info "Upgrading Flatpak packages"
        flatpak update -y 2>/dev/null || true
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

snap_count() {
    PKG_UPDATES_SNAP=0
    if snap_available; then
        PKG_UPDATES_SNAP=$(snap refresh --list 2>/dev/null | tail -n +2 | wc -l || true)
        PKG_UPDATES_SNAP="${PKG_UPDATES_SNAP//[!0-9]/}"
        [[ -z "$PKG_UPDATES_SNAP" ]] && PKG_UPDATES_SNAP=0
        log_info "Snap updates: $PKG_UPDATES_SNAP"
    fi
}

snap_list() {
    if snap_available; then
        snap refresh --list 2>/dev/null || true
    fi
}

snap_upgrade() {
    if snap_available && [[ "$PKG_UPDATES_SNAP" -gt 0 ]]; then
        log_info "Upgrading Snap packages"
        sudo snap refresh 2>/dev/null || true
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

    total_lines=$(echo "$PKG_UPDATE_LIST" | wc -l)

    # Sort: CRITICAL first, then SECURITY, then STANDARD
    local sorted
    sorted=$(echo "$PKG_UPDATE_LIST" | sort -t'|' -k4 -r)

    while IFS='|' read -r name from_ver to_ver priority; do
        [[ -z "$name" ]] && continue
        count=$((count + 1))
        [[ "$count" -gt "$max_lines" ]] && break

        local line="  ${name}"
        if [[ -n "$from_ver" ]]; then
            line+=" (${from_ver} → ${to_ver})"
        elif [[ -n "$to_ver" ]]; then
            line+=" (→ ${to_ver})"
        fi
        [[ "$priority" == "CRITICAL" ]] && line+=" ★ CRITICAL"
        [[ "$priority" == "SECURITY" ]] && line+=" ⚠ SECURITY"
        preview+="${line}"$'\n'
    done <<< "$sorted"

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
        while IFS='|' read -r name from_ver to_ver priority; do
            [[ -z "$name" ]] && continue
            [[ "$first" == "true" ]] && first=false || json+=","
            json+="{\"name\":\"$name\",\"from\":\"$from_ver\",\"to\":\"$to_ver\",\"priority\":\"$priority\"}"
        done <<< "$PKG_UPDATE_LIST"
    fi

    json+="]"
    echo "$json"
}
