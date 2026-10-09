#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/safety.sh
# Pre-upgrade snapshot and reboot detection

set -euo pipefail

REBOOT_PENDING_FILE="${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/reboot_pending"

# --- Boot time of the running system (epoch seconds, 0 if unknown) ---
_safety_boot_epoch() {
    local b
    b=$(awk '/^btime /{print $2; exit}' /proc/stat 2>/dev/null) || b=""
    [[ "$b" =~ ^[0-9]+$ ]] && printf '%s' "$b" || printf '0'
}

# --- Newest installed kernel of the running kernel's flavour ---
# Compares only kernels that share the running one's flavour suffix
# (6.17.0-1032-oem looks at *-oem, not at a generic kernel that happened to
# be updated more recently). Prints nothing when it cannot tell.
_safety_newest_same_flavour() {
    local running="${1:-$(uname -r)}" boot_dir="${2:-/boot}"
    local flavour="${running##*-}"
    [[ "$flavour" =~ ^[A-Za-z][A-Za-z0-9]*$ ]] || return 0
    local f best=""
    for f in "$boot_dir"/vmlinuz-*-"$flavour"; do
        [[ -e "$f" ]] || continue
        f="${f##*/vmlinuz-}"
        if [[ -z "$best" ]] || [[ "$(printf '%s\n%s\n' "$best" "$f" | sort -V | tail -1)" == "$f" ]]; then
            best="$f"
        fi
    done
    printf '%s' "$best"
}

# --- Detect if reboot is required ---
safety_reboot_check() {
    [[ "${REBOOT_CHECK:-true}" != "true" ]] && return 1

    local have_signal=false

    # Debian/Ubuntu: reboot-required flag (update-notifier-common)
    if [[ -d /usr/lib/update-notifier ]] || [[ -f /var/run/reboot-required ]]; then
        have_signal=true
        if [[ -f /var/run/reboot-required ]]; then
            log_info "Reboot required (detected via /var/run/reboot-required)"
            return 0
        fi
    fi

    # Debian/Ubuntu: needrestart (if available)
    if command -v needrestart &>/dev/null; then
        have_signal=true
        local nr_output
        nr_output=$(needrestart -b 2>/dev/null) || true
        if echo "$nr_output" | grep -q 'NEEDRESTART-KSTA: 3'; then
            log_info "Reboot required (detected via needrestart)"
            return 0
        fi
    fi

    # Fedora/RHEL: dnf needs-restarting
    if command -v dnf &>/dev/null; then
        have_signal=true
        if ! dnf needs-restarting -r &>/dev/null; then
            log_info "Reboot required (detected via dnf needs-restarting)"
            return 0
        fi
    fi

    # Arch: the running kernel's module tree disappears when the kernel package is replaced
    if command -v pacman &>/dev/null; then
        have_signal=true
        if [[ -d /usr/lib/modules ]] && [[ ! -d "/usr/lib/modules/$(uname -r)" ]]; then
            log_info "Reboot required (modules for the running kernel $(uname -r) are gone)"
            return 0
        fi
    fi

    # Generic fallback, only where nothing better exists: the newest kernel of
    # the running flavour differs from the running one.
    if [[ "$have_signal" != "true" ]] && [[ -d /boot ]]; then
        local running_kernel newest_kernel
        running_kernel=$(uname -r)
        newest_kernel=$(_safety_newest_same_flavour "$running_kernel" /boot)
        if [[ -n "$newest_kernel" ]] && [[ "$newest_kernel" != "$running_kernel" ]]; then
            log_info "Reboot required (kernel mismatch: running=$running_kernel, installed=$newest_kernel)"
            return 0
        fi
    fi

    return 1
}

# --- Handle reboot notification ---
safety_handle_reboot() {
    if safety_reboot_check; then
        mkdir -p "$(dirname "$REBOOT_PENDING_FILE")" 2>/dev/null || true
        local _ts _tmp
        _ts=$(date -Iseconds 2>/dev/null || date)
        _tmp=$(mktemp "${REBOOT_PENDING_FILE}.XXXXXX") && echo "$_ts" > "$_tmp" && mv "$_tmp" "$REBOOT_PENDING_FILE"

        json_set "reboot_required" "true"

        # Show reboot dialog
        if notify_reboot; then
            log_info "User accepted reboot"
            if ! systemctl reboot 2>/dev/null && ! sudo -n reboot 2>/dev/null; then
                log_error "Failed to initiate reboot — insufficient permissions"
            fi
        else
            log_info "User declined reboot — flagged as pending"
        fi
        return 0
    fi

    json_set "reboot_required" "false"
    # Clear pending flag if no reboot needed
    rm -f "$REBOOT_PENDING_FILE" 2>/dev/null || true
    return 1
}

# --- Check for pending reboot from previous run ---
# The flag is only honoured while it is still true: a flag written before the
# current boot means the reboot already happened, and a flag with no remaining
# reboot indicator is stale. Both are cleared instead of nagging forever.
safety_check_pending_reboot() {
    [[ -f "$REBOOT_PENDING_FILE" ]] || return 1

    local flagged boot
    flagged=$(stat -c %Y "$REBOOT_PENDING_FILE" 2>/dev/null) || flagged=0
    boot=$(_safety_boot_epoch)
    if [[ "$boot" -gt 0 ]] && [[ "$flagged" -lt "$boot" ]]; then
        log_info "Reboot flag predates the current boot — clearing it"
        rm -f "$REBOOT_PENDING_FILE" 2>/dev/null || true
        return 1
    fi

    if ! safety_reboot_check; then
        log_info "Reboot flag set but nothing requires a reboot — clearing it"
        rm -f "$REBOOT_PENDING_FILE" 2>/dev/null || true
        return 1
    fi

    log_warn "Reboot pending from previous upgrade"
    return 0
}

# --- Pre-upgrade snapshot ---
safety_snapshot() {
    [[ "${SNAPSHOT_ENABLED:-false}" != "true" ]] && return 0

    local tool="${SNAPSHOT_TOOL:-auto}"
    local snapshot_id=""

    # Auto-detect snapshot tool
    if [[ "$tool" == "auto" ]]; then
        if command -v timeshift &>/dev/null; then
            tool="timeshift"
        elif command -v snapper &>/dev/null; then
            tool="snapper"
        elif command -v btrfs &>/dev/null && [[ "$(findmnt -n -o FSTYPE / 2>/dev/null)" == "btrfs" ]]; then
            tool="btrfs"
        else
            log_error "No snapshot tool available (install timeshift, snapper, or use btrfs)"
            return 1
        fi
    fi

    log_info "Taking pre-upgrade snapshot with $tool"

    case "$tool" in
        timeshift)
            local output
            output=$(sudo timeshift --create --comments "nudge pre-upgrade $(date +%Y-%m-%dT%H:%M:%S)" 2>&1) || {
                log_error "Timeshift snapshot failed"
                return 1
            }
            # "Tagged snapshot '2026-10-09_16-04-00': ondemand"
            snapshot_id=$(echo "$output" | sed -n "s/.*Tagged snapshot '\([^']*\)'.*/\1/p" | head -1)
            snapshot_id="${snapshot_id:-timeshift-$(date +%s)}"
            ;;
        snapper)
            snapshot_id=$(sudo snapper create -d "nudge pre-upgrade" --print-number 2>/dev/null) || {
                log_error "Snapper snapshot failed"
                return 1
            }
            ;;
        btrfs)
            if [[ "$(findmnt -n -o FSTYPE / 2>/dev/null)" != "btrfs" ]]; then
                log_error "Btrfs snapshot failed: / is not a btrfs filesystem"
                return 1
            fi
            local snap_dir="/.snapshots/nudge"
            local snap_path
            snap_path="${snap_dir}/$(date +%Y%m%d%H%M%S)"
            sudo mkdir -p "$snap_dir" 2>/dev/null || {
                log_error "Btrfs snapshot failed: cannot create $snap_dir"
                return 1
            }
            # A read-only snapshot of the mounted root subvolume
            sudo btrfs subvolume snapshot -r / "$snap_path" 2>/dev/null || {
                log_error "Btrfs snapshot failed"
                return 1
            }
            snapshot_id="$snap_path"
            ;;
        *)
            log_error "Unknown snapshot tool: $tool"
            return 1
            ;;
    esac

    log_info "Snapshot created: $snapshot_id"
    json_set "snapshot_id" "\"$(json_escape "$snapshot_id")\""
    return 0
}
