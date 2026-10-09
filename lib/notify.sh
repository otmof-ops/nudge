#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/notify.sh
# Notification backends — kdialog/zenity/dunst/dbus/notify-send

set -euo pipefail

# Detected backend
NOTIFY_BACKEND=""

# Dialog response: accepted, declined, deferred
NOTIFY_RESPONSE=""

# --- Check if a display server is available ---
_has_display() {
    [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]
}

# --- Did a dialog tool fail to reach the display (rather than the user answering)? ---
# Usage: _notify_display_failed <rc> <stderr-text>
_notify_display_failed() {
    local rc="$1" err="${2:-}"
    [[ "$rc" -ne 0 ]] || return 1
    local lower="${err,,}"
    [[ "$lower" =~ (could\ not\ connect|cannot\ open\ display|failed\ to\ open\ display|unable\ to\ open\ display|could\ not\ load\ the\ qt\ platform|no\ protocol\ specified|failed\ to\ connect\ to) ]]
}

# --- The dialog icon: the Nudge Bunny when installed, the stock icon otherwise ---
_notify_icon_file() {
    local base="${NUDGE_PREFIX:-}"
    local f
    if [[ -n "$base" ]]; then
        f="${base}/.local/share/icons/hicolor/scalable/apps/nudge.svg"
    else
        f="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/nudge.svg"
    fi
    [[ -f "$f" ]] && printf '%s' "$f"
}
# Usage: _notify_icon name|path -> an icon theme name, or a file path
_notify_icon() {
    local f
    f=$(_notify_icon_file) || f=""
    if [[ -n "$f" ]]; then
        if [[ "${1:-name}" == "path" ]]; then printf '%s' "$f"; else printf 'nudge'; fi
    else
        printf 'system-software-update'
    fi
}

# --- Detect best available backend ---
notify_detect() {
    if [[ "${NOTIFICATION_BACKEND:-auto}" != "auto" ]]; then
        if [[ "$NOTIFICATION_BACKEND" != "none" ]] && ! command -v "$NOTIFICATION_BACKEND" &>/dev/null; then
            log_warn "Configured backend '$NOTIFICATION_BACKEND' not found, falling back to auto-detect"
        else
            NOTIFY_BACKEND="$NOTIFICATION_BACKEND"
            log_info "Notification backend (config): $NOTIFY_BACKEND"
            return 0
        fi
    fi

    # GUI backends require a display server
    if _has_display; then
        if command -v dunstify &>/dev/null && pgrep -x dunst &>/dev/null; then
            NOTIFY_BACKEND="dunstify"
        elif command -v kdialog &>/dev/null && [[ -n "${KDE_SESSION_VERSION:-}" ]]; then
            NOTIFY_BACKEND="kdialog"
        elif command -v zenity &>/dev/null; then
            NOTIFY_BACKEND="zenity"
        elif command -v kdialog &>/dev/null; then
            # kdialog outside KDE — still usable, just not preferred
            NOTIFY_BACKEND="kdialog"
        elif command -v dunstify &>/dev/null; then
            # dunst binary exists but daemon not running — still try
            NOTIFY_BACKEND="dunstify"
        elif command -v gdbus &>/dev/null; then
            NOTIFY_BACKEND="gdbus"
        elif command -v notify-send &>/dev/null; then
            NOTIFY_BACKEND="notify-send"
        else
            NOTIFY_BACKEND="none"
        fi
    else
        log_warn "No display server detected (DISPLAY/WAYLAND_DISPLAY unset)"
        NOTIFY_BACKEND="none"
    fi

    log_info "Notification backend (detected): $NOTIFY_BACKEND"
    return 0
}

# --- Show update preview (scrollable list); AUTO_DISMISS applies here too ---
_show_preview_kdialog() {
    local preview="$1"
    local dismiss="${AUTO_DISMISS:-0}"
    local -a wrap=()
    [[ "$dismiss" -gt 0 ]] && wrap=(timeout "$dismiss")
    # kdialog wants a real file for --textbox (a /dev/fd path shows up empty)
    local tmp
    tmp=$(umask 077 && mktemp) || return 0
    printf '%s\n' "$preview" > "$tmp"
    "${wrap[@]}" kdialog --title "Package Updates" \
        --textbox "$tmp" 500 400 2>/dev/null || true
    rm -f "$tmp"
}

_show_preview_zenity() {
    local preview="$1"
    local dismiss="${AUTO_DISMISS:-0}"
    local -a timeout_arg=()
    [[ "$dismiss" -gt 0 ]] && timeout_arg=("--timeout=$dismiss")
    echo "$preview" | zenity --text-info \
        --title="Package Updates" \
        --width=500 --height=400 "${timeout_arg[@]}" 2>/dev/null || true
}

# --- kdialog backend ---
_prompt_kdialog() {
    local msg="$1" preview="${2:-}"
    local dismiss="${AUTO_DISMISS:-0}"

    # Show preview if enabled and available
    if [[ -n "$preview" ]] && [[ "${PREVIEW_UPDATES:-true}" == "true" ]]; then
        _show_preview_kdialog "$preview"
    fi

    # The buttons say what they do: Yes = Update Now, No = Remind Me Later,
    # Cancel = Not Now (also Esc and closing the window).
    local args=(--icon "$(_notify_icon name)" --title "System Updates Available"
                --yes-label "Update Now" --no-label "Remind Me Later" --cancel-label "Not Now"
                --yesnocancel "$msg")

    local rc=0 err=""
    if [[ "$dismiss" -gt 0 ]]; then
        if err=$(timeout "$dismiss" kdialog "${args[@]}" 2>&1 >/dev/null); then rc=0; else rc=$?; fi
        if [[ "$rc" -eq 124 ]]; then
            log_info "Dialog auto-dismissed after ${dismiss}s"
            NOTIFY_RESPONSE="declined"
            return 0
        fi
    else
        if err=$(kdialog "${args[@]}" 2>&1 >/dev/null); then rc=0; else rc=$?; fi
    fi

    if _notify_display_failed "$rc" "$err"; then
        log_error "kdialog could not open a display: ${err}"
        NOTIFY_RESPONSE=""
        return 1
    fi

    case "$rc" in
        0) NOTIFY_RESPONSE="accepted" ;;
        1) NOTIFY_RESPONSE="deferred" ;;
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

    local zen_output zen_err
    local rc=0
    zen_err=$(mktemp 2>/dev/null) || zen_err=""
    if zen_output=$(zenity --question --icon-name="$(_notify_icon name)" \
        --title="System Updates Available" \
        --text="$(echo -e "$msg")" \
        --ok-label="Update Now" \
        --cancel-label="Not Now" \
        --extra-button="Remind Me Later" \
        "${timeout_arg[@]}" 2>"${zen_err:-/dev/null}"); then rc=0; else rc=$?; fi
    local err=""
    if [[ -n "$zen_err" ]]; then
        err=$(cat "$zen_err" 2>/dev/null || true)
        rm -f "$zen_err" 2>/dev/null || true
    fi

    if _notify_display_failed "$rc" "$err"; then
        log_error "zenity could not open a display: ${err}"
        NOTIFY_RESPONSE=""
        return 1
    fi

    # zenity returns the extra-button label on stdout (exit code 1)
    if [[ "$zen_output" == "Remind Me Later" ]]; then
        NOTIFY_RESPONSE="deferred"
    elif [[ "$rc" -eq 0 ]]; then
        NOTIFY_RESPONSE="accepted"
    else
        NOTIFY_RESPONSE="declined"
    fi
}

# --- dunstify backend ---
_prompt_dunstify() {
    local msg="$1"
    local preview="${2:-}"
    local appname="${DUNST_APPNAME:-nudge}"
    local dismiss="${AUTO_DISMISS:-0}"
    local timeout_ms=0
    [[ "$dismiss" -gt 0 ]] && timeout_ms=$((dismiss * 1000))

    # Append first 5 lines of preview to body
    local body="$msg"
    if [[ -n "$preview" ]] && [[ "${PREVIEW_UPDATES:-true}" == "true" ]]; then
        local preview_lines
        preview_lines=$(echo "$preview" | head -5)
        body="${msg}\n\n${preview_lines}"
    fi

    local action
    action=$(dunstify --action="update,Update Now" \
        --action="defer,Remind Me Later" \
        -i "$(_notify_icon path)" \
        -a "$appname" \
        -t "$timeout_ms" \
        "System Updates Available" "$body" 2>/dev/null) || true

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
        "nudge" 0 "$(_notify_icon path)" \
        "System Updates Available" "$msg" \
        "['update','Update Now','defer','Remind Me Later']" \
        '{}' "$timeout_ms" 2>/dev/null) || true

    # gdbus notification actions require monitoring — simplified fallback
    # In practice, this is passive notification: the user was told, not asked
    log_warn "Notification backend 'gdbus' is passive — nudge cannot prompt for updates interactively. Install kdialog or zenity for interactive prompts."
    NOTIFY_RESPONSE="passive"
}

# --- notify-send backend (passive, no interaction) ---
_prompt_notify_send() {
    local msg="$1"

    notify-send -i "$(_notify_icon path)" "System Updates Available" \
        "$msg" 2>/dev/null || true
    log_warn "Notification backend 'notify-send' is passive — nudge cannot prompt for updates interactively. Install kdialog or zenity for interactive prompts."
    NOTIFY_RESPONSE="passive"
}

# --- Main prompt dispatcher ---
notify_prompt() {
    local msg="$1"
    local preview="${2:-}"

    NOTIFY_RESPONSE=""

    case "$NOTIFY_BACKEND" in
        kdialog)    _prompt_kdialog "$msg" "$preview" || return 1 ;;
        zenity)     _prompt_zenity "$msg" "$preview" || return 1 ;;
        dunstify)   _prompt_dunstify "$msg" "$preview" ;;
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
    local _reboot_personality_msg
    _reboot_personality_msg=$(bunny_message "reboot" 2>/dev/null) || true
    local msg
    if [[ -n "$_reboot_personality_msg" ]]; then
        msg="${_reboot_personality_msg}\n\nReboot now?"
    else
        msg="A system reboot is required to complete the update.\n\nReboot now?"
    fi

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
    local _selfupdate_personality_msg
    _selfupdate_personality_msg=$(bunny_message "selfupdate" 2>/dev/null) || true
    local msg
    if [[ -n "$_selfupdate_personality_msg" ]]; then
        msg="${_selfupdate_personality_msg}\nnudge v${latest} is available (you have v${current}).\nRun: nudge --self-update"
    else
        msg="nudge v${latest} is available (you have v${current}).\nRun: nudge --self-update"
    fi

    case "$NOTIFY_BACKEND" in
        kdialog)
            kdialog --icon "$(_notify_icon name)" --title "nudge Update Available" \
                --passivepopup "$msg" 10 2>/dev/null || true
            ;;
        zenity)
            zenity --info --icon-name="$(_notify_icon name)" \
                --title="nudge Update Available" \
                --text="$(echo -e "$msg")" --timeout=10 2>/dev/null || true
            ;;
        *)
            notify-send -i "$(_notify_icon path)" "nudge Update Available" \
                "$(echo -e "$msg")" 2>/dev/null || true
            ;;
    esac
}
