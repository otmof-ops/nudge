#!/usr/bin/env bash
# nudge — lib/safety.sh
# Pre-upgrade snapshot and reboot detection
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

REBOOT_PENDING_FILE="${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/reboot_pending"

# --- Detect if reboot is required ---
safety_reboot_check() {
    [[ "${REBOOT_CHECK:-true}" != "true" ]] && return 1

    # Debian/Ubuntu: check reboot-required file
    if [[ -f /var/run/reboot-required ]]; then
        log_info "Reboot required (detected via /var/run/reboot-required)"
        return 0
    fi

    # Debian/Ubuntu: needrestart (if available)
    if command -v needrestart &>/dev/null; then
        if needrestart -b 2>/dev/null | grep -q 'NEEDRESTART-KSTA: 3'; then
            log_info "Reboot required (detected via needrestart)"
            return 0
        fi
    fi

    # Fedora/RHEL: dnf needs-restarting
    if command -v dnf &>/dev/null; then
        if ! dnf needs-restarting -r &>/dev/null; then
            log_info "Reboot required (detected via dnf needs-restarting)"
            return 0
        fi
    fi

    # Arch: compare running vs installed kernel
    if command -v pacman &>/dev/null; then
        local running installed
        running=$(uname -r)
        installed=$(pacman -Q linux 2>/dev/null | awk '{print $2}' || true)
        if [[ -n "$installed" ]] && [[ "$running" != *"$installed"* ]]; then
            log_info "Reboot required (kernel mismatch: running=$running, installed=$installed)"
            return 0
        fi
    fi

    # Generic: compare uname -r vs installed kernel packages
    local running_kernel
    running_kernel=$(uname -r)
    if [[ -d /boot ]]; then
        local newest_kernel
        # shellcheck disable=SC2012
        newest_kernel=$(ls -t /boot/vmlinuz-* 2>/dev/null | head -1 | sed 's|/boot/vmlinuz-||' || true)
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
        { date -Iseconds 2>/dev/null || date; } > "$REBOOT_PENDING_FILE"

        json_set "reboot_required" "true"

        # Show reboot dialog
        if notify_reboot; then
            log_info "User accepted reboot"
            systemctl reboot 2>/dev/null || sudo reboot 2>/dev/null || true
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
safety_check_pending_reboot() {
    if [[ -f "$REBOOT_PENDING_FILE" ]]; then
        log_warn "Reboot pending from previous upgrade"
        return 0
    fi
    return 1
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
        elif command -v btrfs &>/dev/null && mount | grep -q 'type btrfs'; then
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
            output=$(sudo timeshift --create --comments "nudge pre-upgrade $(date -Iseconds)" 2>&1) || {
                log_error "Timeshift snapshot failed"
                return 1
            }
            snapshot_id=$(echo "$output" | grep -oP 'Tagged snapshot.*: \K.*' || echo "timeshift-$(date +%s)")
            ;;
        snapper)
            snapshot_id=$(sudo snapper create -d "nudge pre-upgrade" --print-number 2>/dev/null) || {
                log_error "Snapper snapshot failed"
                return 1
            }
            ;;
        btrfs)
            local root_subvol
            root_subvol=$(findmnt -n -o SOURCE / 2>/dev/null | head -1)
            local snap_path
            snap_path="/snapshots/nudge-$(date +%Y%m%d%H%M%S)"
            sudo btrfs subvolume snapshot "$root_subvol" "$snap_path" 2>/dev/null || {
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
    json_set "snapshot_id" "\"$snapshot_id\""
    return 0
}
