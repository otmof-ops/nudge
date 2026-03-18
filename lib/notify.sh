#!/usr/bin/env bash
# nudge — lib/notify.sh
# Notification backends — kdialog/zenity/dunst/dbus/notify-send
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

# Detected backend
NOTIFY_BACKEND=""

# Dialog response: accepted, declined, deferred
NOTIFY_RESPONSE=""

# --- Detect best available backend ---
notify_detect() {
    if [[ "${NOTIFICATION_BACKEND:-auto}" != "auto" ]]; then
        NOTIFY_BACKEND="$NOTIFICATION_BACKEND"
        log_info "Notification backend (config): $NOTIFY_BACKEND"
        return 0
    fi

    if command -v dunstify &>/dev/null; then
        NOTIFY_BACKEND="dunstify"
    elif command -v kdialog &>/dev/null; then
        NOTIFY_BACKEND="kdialog"
    elif command -v zenity &>/dev/null; then
        NOTIFY_BACKEND="zenity"
    elif command -v gdbus &>/dev/null; then
        NOTIFY_BACKEND="gdbus"
    elif command -v notify-send &>/dev/null; then
        NOTIFY_BACKEND="notify-send"
    else
        NOTIFY_BACKEND="none"
    fi

    log_info "Notification backend (detected): $NOTIFY_BACKEND"
    return 0
}

# --- Show update preview (scrollable list) ---
_show_preview_kdialog() {
    local preview="$1"
    kdialog --title "Package Updates" \
        --textbox <(echo "$preview") 500 400 2>/dev/null || true
}

_show_preview_zenity() {
    local preview="$1"
    echo "$preview" | zenity --text-info \
        --title="Package Updates" \
        --width=500 --height=400 2>/dev/null || true
}

# --- kdialog backend ---
_prompt_kdialog() {
    local msg="$1" preview="${2:-}"
    local dismiss="${AUTO_DISMISS:-0}"

    # Show preview if enabled and available
    if [[ -n "$preview" ]] && [[ "${PREVIEW_UPDATES:-true}" == "true" ]]; then
        _show_preview_kdialog "$preview"
    fi

    local args=(--icon system-software-update --title "System Updates Available")
    args+=(--yesnocancel "$msg\n\nUpdate Now / Remind Me Later / Not Now")

    if [[ "$dismiss" -gt 0 ]]; then
        timeout "$dismiss" kdialog "${args[@]}" 2>/dev/null && true
        local rc=$?
        if [[ "$rc" -eq 124 ]]; then
            log_info "Dialog auto-dismissed after ${dismiss}s"
            NOTIFY_RESPONSE="declined"
            return 0
        fi
    else
        kdialog "${args[@]}" 2>/dev/null && true
        local rc=$?
    fi

    case "$rc" in
        0) NOTIFY_RESPONSE="accepted" ;;
        1) NOTIFY_RESPONSE="declined" ;;
        2) NOTIFY_RESPONSE="deferred" ;;
        *) NOTIFY_RESPONSE="declined" ;;
    esac
}

# --- zenity backend ---
_prompt_zenity() {
    local msg="$1" preview="${2:-}"
    local dismiss="${AUTO_DISMISS:-0}"
    local -a timeout_arg=()

    # Show preview if enabled and available
    if [[ -n "$preview" ]] && [[ "${PREVIEW_UPDATES:-true}" == "true" ]]; then
        _show_preview_zenity "$preview"
    fi

    [[ "$dismiss" -gt 0 ]] && timeout_arg=("--timeout=$dismiss")

    zenity --question --icon-name=system-software-update \
        --title="System Updates Available" \
        --text="$(echo -e "$msg")" \
        --ok-label="Update Now" \
        --cancel-label="Not Now" \
        --extra-button="Remind Me Later" \
        "${timeout_arg[@]}" 2>/dev/null && true
    local rc=$?

    case "$rc" in
        0) NOTIFY_RESPONSE="accepted" ;;
        5) NOTIFY_RESPONSE="deferred" ;;  # extra-button
        *) NOTIFY_RESPONSE="declined" ;;
    esac

    # zenity returns the extra-button label on stdout when clicked
    # Some versions use exit code 1 with stdout text
    if [[ "$rc" -eq 1 ]]; then
        # Check if "Remind Me Later" was captured
        NOTIFY_RESPONSE="declined"
    fi
}

# --- dunstify backend ---
_prompt_dunstify() {
    local msg="$1"
    local appname="${DUNST_APPNAME:-nudge}"
    local dismiss="${AUTO_DISMISS:-0}"
    local timeout_ms=0
    [[ "$dismiss" -gt 0 ]] && timeout_ms=$((dismiss * 1000))

    local action
    action=$(dunstify --action="update,Update Now" \
        --action="defer,Remind Me Later" \
        -i system-software-update \
        -a "$appname" \
        -t "$timeout_ms" \
        "System Updates Available" "$msg" 2>/dev/null) || true

    case "$action" in
        update) NOTIFY_RESPONSE="accepted" ;;
        defer)  NOTIFY_RESPONSE="deferred" ;;
        *)      NOTIFY_RESPONSE="declined" ;;
    esac
}

# --- gdbus (D-Bus Notifications) backend ---
_prompt_gdbus() {
    local msg="$1"
    local dismiss="${AUTO_DISMISS:-0}"
    local timeout_ms=0
    [[ "$dismiss" -gt 0 ]] && timeout_ms=$((dismiss * 1000))

    local _result
    _result=$(gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify \
        "nudge" 0 "system-software-update" \
        "System Updates Available" "$msg" \
        "['update','Update Now','defer','Remind Me Later']" \
        '{}' "$timeout_ms" 2>/dev/null) || true

    # gdbus notification actions require monitoring — simplified fallback
    # In practice, this is passive notification
    NOTIFY_RESPONSE="declined"
}

# --- notify-send backend (passive, no interaction) ---
_prompt_notify_send() {
    local msg="$1"

    notify-send -i system-software-update "System Updates Available" \
        "$msg" 2>/dev/null || true
    log_info "Sent desktop notification (notify-send — no interactive prompt)"
    NOTIFY_RESPONSE="declined"
}

# --- Main prompt dispatcher ---
notify_prompt() {
    local msg="$1"
    local preview="${2:-}"

    NOTIFY_RESPONSE=""

    case "$NOTIFY_BACKEND" in
        kdialog)    _prompt_kdialog "$msg" "$preview" ;;
        zenity)     _prompt_zenity "$msg" "$preview" ;;
        dunstify)   _prompt_dunstify "$msg" ;;
        gdbus)      _prompt_gdbus "$msg" ;;
        notify-send) _prompt_notify_send "$msg" ;;
        none)
            log_error "No notification backend available"
            return 1
            ;;
        *)
            log_error "Unknown backend: $NOTIFY_BACKEND"
            return 1
            ;;
    esac

    log_info "User response: $NOTIFY_RESPONSE"
    return 0
}

# --- Show reboot notification ---
notify_reboot() {
    local msg="A system reboot is required to complete the update.\n\nReboot now?"

    case "$NOTIFY_BACKEND" in
        kdialog)
            if kdialog --icon system-reboot --title "Reboot Required" \
                --yesno "$msg" 2>/dev/null; then
                return 0  # user wants reboot
            fi
            return 1
            ;;
        zenity)
            if zenity --question --icon-name=system-reboot \
                --title="Reboot Required" \
                --text="$(echo -e "$msg")" 2>/dev/null; then
                return 0
            fi
            return 1
            ;;
        dunstify)
            dunstify -i system-reboot -a "${DUNST_APPNAME:-nudge}" \
                "Reboot Required" \
                "A system reboot is required to complete the update." 2>/dev/null || true
            return 1
            ;;
        *)
            notify-send -i system-reboot "nudge" \
                "A system reboot is required to complete the update." 2>/dev/null || true
            return 1
            ;;
    esac
}

# --- Show self-update notification ---
notify_selfupdate() {
    local current="$1" latest="$2"
    local msg="nudge v${latest} is available (you have v${current}).\nRun: nudge --self-update"

    case "$NOTIFY_BACKEND" in
        kdialog)
            kdialog --icon system-software-update --title "nudge Update Available" \
                --passivepopup "$msg" 10 2>/dev/null || true
            ;;
        zenity)
            zenity --info --icon-name=system-software-update \
                --title="nudge Update Available" \
                --text="$(echo -e "$msg")" --timeout=10 2>/dev/null || true
            ;;
        *)
            notify-send -i system-software-update "nudge Update Available" \
                "$(echo -e "$msg")" 2>/dev/null || true
            ;;
    esac
}
