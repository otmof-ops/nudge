#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — A gentle nudge to keep your system fresh.
# Version: 2.2.0

set -euo pipefail

NUDGE_VERSION="2.2.0"
_NUDGE_START_TIME=$(date +%s)
_NUDGE_TRIGGER="${_NUDGE_TRIGGER:-manual}"
case "$_NUDGE_TRIGGER" in
    manual|login|timer|cron) ;;
    *) _NUDGE_TRIGGER="manual" ;;
esac

# --- Locate ourselves and the lib directory ---
NUDGE_SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
_NUDGE_SELF_DIR="$(cd "$(dirname "$NUDGE_SELF")" && pwd)"
NUDGE_PREFIX=""
# Installed layout: PREFIX/.local/bin/nudge.sh beside PREFIX/.local/lib/nudge
if [[ "$_NUDGE_SELF_DIR" == */.local/bin ]]; then
    # shellcheck disable=SC2034  # read by lib/notify.sh (the icon) and lib/selfupdate.sh (the prefix)
    NUDGE_PREFIX="${_NUDGE_SELF_DIR%/.local/bin}"
fi

_nudge_find_lib() {
    local c
    # The script's own layout first; the environment only as a last resort
    for c in "$_NUDGE_SELF_DIR/lib" "$_NUDGE_SELF_DIR/../lib/nudge" "${HOME}/.local/lib/nudge" "${NUDGE_LIB_DIR:-}"; do
        [[ -n "$c" ]] && [[ -f "$c/output.sh" ]] && { printf '%s' "$c"; return 0; }
    done
    return 1
}

if ! NUDGE_LIB_DIR="$(_nudge_find_lib)"; then
    echo "Error: nudge lib directory not found (looked beside $NUDGE_SELF and in ~/.local/lib/nudge)" >&2
    exit 10  # EXIT_CONFIG_ERROR — constants not yet sourced
fi
NUDGE_LIB_DIR="$(cd "$NUDGE_LIB_DIR" && pwd)"

# --- Source all modules ---
# shellcheck source=lib/output.sh
source "$NUDGE_LIB_DIR/output.sh"
# shellcheck source=lib/config.sh
source "$NUDGE_LIB_DIR/config.sh"
# shellcheck source=lib/lock.sh
source "$NUDGE_LIB_DIR/lock.sh"
# shellcheck source=lib/network.sh
source "$NUDGE_LIB_DIR/network.sh"
# shellcheck source=lib/pkgmgr.sh
source "$NUDGE_LIB_DIR/pkgmgr.sh"
# shellcheck source=lib/notify.sh
source "$NUDGE_LIB_DIR/notify.sh"
# shellcheck source=lib/schedule.sh
source "$NUDGE_LIB_DIR/schedule.sh"
# shellcheck source=lib/history.sh
source "$NUDGE_LIB_DIR/history.sh"
# shellcheck source=lib/safety.sh
source "$NUDGE_LIB_DIR/safety.sh"
# shellcheck source=lib/selfupdate.sh
source "$NUDGE_LIB_DIR/selfupdate.sh"
# shellcheck source=lib/errorreport.sh
source "$NUDGE_LIB_DIR/errorreport.sh"
# shellcheck source=lib/tui.sh
source "$NUDGE_LIB_DIR/tui.sh"
# shellcheck source=lib/select.sh
source "$NUDGE_LIB_DIR/select.sh"
# shellcheck source=lib/bunny-poses.sh
source "$NUDGE_LIB_DIR/bunny-poses.sh"
# shellcheck source=lib/bunny-dialogue.sh
source "$NUDGE_LIB_DIR/bunny-dialogue.sh"
# shellcheck source=lib/bunny.sh
source "$NUDGE_LIB_DIR/bunny.sh"
# shellcheck source=lib/dialog.sh
source "$NUDGE_LIB_DIR/dialog.sh"

# --- A UTF-8 locale for the text we cut and measure (a user unit may have none) ---
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
    *) export LC_ALL=C.UTF-8 2>/dev/null || true ;;
esac

# --- The mascot's SVGs: beside the modules once installed, share/mascot in a checkout ---
_nudge_find_mascot() {
    local c
    for c in "$NUDGE_LIB_DIR/mascot" "$_NUDGE_SELF_DIR/share/mascot" "${NUDGE_MASCOT_DIR:-}"; do
        [[ -n "$c" ]] || continue
        c=$(cd "$c" 2>/dev/null && pwd -P) || continue
        [[ -f "$c/bunny.svg" ]] && { printf '%s' "$c"; return 0; }
    done
    return 1
}
NUDGE_MASCOT_DIR="$(_nudge_find_mascot)" || NUDGE_MASCOT_DIR=""

# --- Upgrade session runner (launched inside a terminal by pkgmgr_upgrade) ---
if [[ "${1:-}" == "--_run-upgrade" ]]; then
    config_load
    output_init
    _tui_init
    pkgmgr_run_upgrade_session "${2:-}"
    exit $?
fi

# --- Exit with an outcome ---
# A login or timer run exits 0 on the ordinary outcomes (declined, applied,
# disabled, offline, the package manager busy, another run in progress,
# deferred, reboot pending): the autostart unit must not count a "Not Now" as
# a failed service. The JSON and every history row keep the real code, and a
# manual run exits with it. Failures (3, 8, 10, 11, 12) stay non-zero.
_nudge_exit() {
    local code="$1"
    if [[ "$_NUDGE_TRIGGER" != "manual" ]]; then
        case "$code" in
            "$EXIT_UPDATES_DECLINED"|"$EXIT_UPDATES_APPLIED"|"$EXIT_DISABLED"|"$EXIT_NETWORK_FAIL"|"$EXIT_PKG_LOCK"|"$EXIT_ALREADY_RUNNING"|"$EXIT_DEFERRED"|"$EXIT_REBOOT_PENDING")
                exit "$EXIT_OK" ;;
        esac
    fi
    exit "$code"
}

# --- CLI flags ---
DRY_RUN=false
CHECK_ONLY=false
_JSON_FLAG=false
_VERBOSE_FLAG=false

# --- Parse arguments ---
_HISTORY_CMD=false
_HISTORY_COUNT=20
_HISTORY_FORMAT="table"
_HISTORY_SINCE=""
_DEFER_CMD=""
_SELF_UPDATE_CMD=false
_CONFIG_CMD=false
_VALIDATE_CMD=false
_MIGRATE_CMD=false
_REPORT_CMD=false
_REPORT_FILE_CMD=false
_REPORT_CLEAR_CMD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            echo "nudge $NUDGE_VERSION"
            exit "$EXIT_OK"
            ;;
        --help|-h)
            output_banner "nudge $NUDGE_VERSION" "A gentle nudge to keep your system fresh."
            cat <<'HELP'

Usage: nudge [OPTIONS]

Options:
  --version              Print version and exit
  --help, -h             Show this help
  --dry-run              Run checks but don't show dialogs
  --check-only           Print update count and exit
  --json                 Machine-readable JSON output
  --verbose              Verbose logging to stderr
  --history [N]          Show last N history records (default: 20)
  --history --json       Dump raw JSONL history
  --history --since DATE Filter history by date
  --defer DURATION       Defer next check (a number of h, d or w: 1h, 4h, 1d, 1w)
  --self-update          Download and install latest nudge
  --config               Print current resolved configuration
  --validate             Validate config and exit
  --migrate              Run config migration manually
  --report               Show crash reports
  --report --file        File latest crash report as GitHub issue
  --report --clear       Clear all crash reports

Environment:
  XDG_CONFIG_HOME        Config directory (default: ~/.config)
  XDG_DATA_HOME          Data directory (default: ~/.local/share)
  NUDGE_LIB_DIR          Library directory, used only when none is found beside the script

Files:
  ~/.config/nudge/nudge.conf    Configuration
  ~/.local/share/nudge/         State and history
HELP
            exit "$EXIT_OK"
            ;;
        --dry-run)     DRY_RUN=true ;;
        --check-only)  CHECK_ONLY=true ;;
        --json)        _JSON_FLAG=true ;;
        --verbose)     _VERBOSE_FLAG=true ;;
        --history)
            _HISTORY_CMD=true
            if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                _HISTORY_COUNT="$2"
                shift
            fi
            ;;
        --since)
            if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                echo "--since needs a date (for example: --history --since 2026-01-01)" >&2
                exit 10
            fi
            _HISTORY_SINCE="$2"
            shift
            ;;
        --defer)
            if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                echo "--defer needs a duration (for example: --defer 4h)" >&2
                exit 10
            fi
            _DEFER_CMD="$2"
            shift
            ;;
        --self-update) _SELF_UPDATE_CMD=true ;;
        --config)      _CONFIG_CMD=true ;;
        --validate)    _VALIDATE_CMD=true ;;
        --migrate)     _MIGRATE_CMD=true ;;
        --report)      _REPORT_CMD=true ;;
        --file)        _REPORT_FILE_CMD=true ;;
        --clear)       _REPORT_CLEAR_CMD=true ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Run 'nudge --help' for usage." >&2
            exit 10  # EXIT_CONFIG_ERROR — constants not yet available at parse time
            ;;
    esac
    shift
done

if [[ -n "$_HISTORY_SINCE" && "$_HISTORY_CMD" != "true" ]]; then
    echo "--since only makes sense with --history" >&2
    exit 10
fi
if [[ ( "$_REPORT_FILE_CMD" == "true" || "$_REPORT_CLEAR_CMD" == "true" ) && "$_REPORT_CMD" != "true" ]]; then
    echo "--file and --clear only make sense with --report" >&2
    exit 10
fi

# --- Load config ---
config_load
config_ensure_dirs
output_init
if [[ "$CHECK_ONLY" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
    bunny_init
fi

# --- Handle utility commands (no lock needed) ---

if [[ "$_HISTORY_CMD" == "true" ]]; then
    [[ "$_JSON_MODE" == "true" ]] && _HISTORY_FORMAT="json"
    history_show "$_HISTORY_COUNT" "$_HISTORY_FORMAT" "$_HISTORY_SINCE"
    exit "$EXIT_OK"
fi

if [[ "$_SELF_UPDATE_CMD" == "true" ]]; then
    if selfupdate_install; then
        exit "$EXIT_OK"
    else
        exit "$EXIT_CONFIG_ERROR"
    fi
fi

if [[ -n "$_DEFER_CMD" ]]; then
    if schedule_defer "$_DEFER_CMD"; then
        echo "Next check deferred for $_DEFER_CMD"
        _nudge_exit "$EXIT_DEFERRED"
    else
        echo "Invalid defer duration: $_DEFER_CMD (expected: 1h, 4h, 1d, 1w)" >&2
        exit "$EXIT_CONFIG_ERROR"
    fi
fi

if [[ "$_CONFIG_CMD" == "true" ]]; then
    config_print
    exit "$EXIT_OK"
fi

if [[ "$_VALIDATE_CMD" == "true" ]]; then
    if config_validate; then
        echo "Config validation passed"
        exit "$EXIT_OK"
    else
        echo "Config validation failed"
        exit "$EXIT_CONFIG_ERROR"
    fi
fi

if [[ "$_MIGRATE_CMD" == "true" ]]; then
    config_migrate
    echo "Config migration complete"
    exit "$EXIT_OK"
fi

if [[ "$_REPORT_CMD" == "true" ]]; then
    if [[ "$_REPORT_CLEAR_CMD" == "true" ]]; then
        errorreport_clear
    elif [[ "$_REPORT_FILE_CMD" == "true" ]]; then
        errorreport_file_issue
    elif [[ "$_JSON_MODE" == "true" ]]; then
        errorreport_list 20 "json"
    else
        errorreport_list 20 "table"
    fi
    exit "$EXIT_OK"
fi

# --- Disabled check ---
if [[ "$ENABLED" != "true" ]]; then
    log_info "nudge is disabled"
    json_emit "$EXIT_DISABLED"
    history_write "DISABLED" "ENABLED=false" "$EXIT_DISABLED"
    _nudge_exit "$EXIT_DISABLED"
fi

# --- Finalize duration ---
_finalize() {
    local end_time
    end_time=$(date +%s)
    json_set "duration_seconds" "$(( end_time - _NUDGE_START_TIME ))"
}

# --- Error exit with crash report ---
_exit_error() {
    local exit_code="$1"
    local context="${2:-}"
    _finalize
    errorreport_write "$exit_code" "$context" >/dev/null 2>&1 || true
    exit "$exit_code"
}

# --- Signal handling ---
CLEANUP_PIDS=()
_CLEANUP_DONE=false

# shellcheck disable=SC2317  # _cleanup is invoked via trap, not directly
_cleanup() {
    [[ "$_CLEANUP_DONE" == "true" ]] && return
    _CLEANUP_DONE=true

    local sig="${1:-EXIT}"
    local pid f
    for pid in "${CLEANUP_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    for f in "${_NUDGE_TMPFILES[@]}"; do
        rm -f "$f" 2>/dev/null || true
    done

    # Calculate duration
    _finalize

    # Write history and crash report on non-EXIT signals
    if [[ "$sig" != "EXIT" ]]; then
        history_write "CANCELLED" "Signal: $sig" "$EXIT_INTERRUPTED"
        errorreport_write "$EXIT_INTERRUPTED" "Signal: $sig" >/dev/null 2>&1 || true
    fi

    lock_release
}

trap '_cleanup EXIT'          EXIT
trap '_cleanup INT;  exit "$EXIT_INTERRUPTED"' INT
trap '_cleanup TERM; exit "$EXIT_INTERRUPTED"' TERM
trap '_cleanup HUP;  exit "$EXIT_INTERRUPTED"' HUP

# --- Acquire lock (skip for check-only) ---
if [[ "$CHECK_ONLY" != "true" ]]; then
    if ! lock_acquire; then
        json_emit "$EXIT_ALREADY_RUNNING"
        if [[ "$_NUDGE_TRIGGER" != "manual" ]]; then
            # the other run may be a picker or a session left open: this one steps aside
            log_info "Another nudge instance is running; this ${_NUDGE_TRIGGER} run steps aside"
            history_write "ALREADY_RUNNING" "trigger: $_NUDGE_TRIGGER" "$EXIT_ALREADY_RUNNING"
            _nudge_exit "$EXIT_ALREADY_RUNNING"
        fi
        _exit_error "$EXIT_ALREADY_RUNNING" "Another nudge instance is running"
    fi
fi

# --- Schedule guard ---
if [[ "$DRY_RUN" != "true" ]] && [[ "$CHECK_ONLY" != "true" ]]; then
    if ! schedule_due; then
        json_emit "$EXIT_OK"
        exit "$EXIT_OK"
    fi
fi

# --- Pending reboot reminder ---
if safety_check_pending_reboot; then
    if [[ "$DRY_RUN" != "true" ]] && [[ "$CHECK_ONLY" != "true" ]]; then
        notify_detect
        if notify_reboot; then
            systemctl reboot 2>/dev/null || sudo -n reboot 2>/dev/null || true
        else
            _finalize
            json_emit "$EXIT_REBOOT_PENDING"
            history_write "REBOOT_PENDING" "User declined reboot" "$EXIT_REBOOT_PENDING"
            _nudge_exit "$EXIT_REBOOT_PENDING"
        fi
    fi
fi

# --- Delay after login or a timer (a manual run starts at once) ---
if [[ "$DRY_RUN" != "true" ]] && [[ "$CHECK_ONLY" != "true" ]] && [[ "$_NUDGE_TRIGGER" != "manual" ]]; then
    if [[ "${DELAY:-0}" =~ ^[0-9]+$ ]] && [[ "${DELAY:-0}" -gt 0 ]]; then
        log_info "Waiting ${DELAY}s before checking for updates"
        sleep "$DELAY"
    fi
fi

# --- Network check ---
if ! network_check; then
    _NETWORK_RC=0
    network_handle_offline || _NETWORK_RC=$?
    [[ "$_NETWORK_RC" -eq 0 ]] && _NETWORK_RC="$EXIT_NETWORK_FAIL"
    _finalize
    json_emit "$_NETWORK_RC"
    history_write "OFFLINE" "mode: ${OFFLINE_MODE:-skip}" "$_NETWORK_RC"
    _nudge_exit "$_NETWORK_RC"
fi

# --- Detect package manager ---
if ! pkgmgr_detect; then
    log_error "No supported package manager found"
    json_emit "$EXIT_CONFIG_ERROR"
    _exit_error "$EXIT_CONFIG_ERROR" "No supported package manager found"
fi
json_set "pkg_manager" "$DETECTED_PKGMGR"

# --- Package manager lock check ---
if ! pkgmgr_lock_check; then
    json_emit "$EXIT_PKG_LOCK"
    if [[ "$_NUDGE_TRIGGER" != "manual" ]]; then
        # unattended-upgrades or a software centre has the lock just after login: not our failure
        log_info "Package manager locked by another process; this ${_NUDGE_TRIGGER} run steps aside"
        history_write "PKG_LOCK" "trigger: $_NUDGE_TRIGGER" "$EXIT_PKG_LOCK"
        _nudge_exit "$EXIT_PKG_LOCK"
    fi
    _exit_error "$EXIT_PKG_LOCK" "Package manager locked by another process"
fi

# --- Count updates (system + flatpak + snap) ---
pkgmgr_count_updates
flatpak_count
snap_count

# --- Mark last check (a real run only) ---
if [[ "$DRY_RUN" != "true" ]] && [[ "$CHECK_ONLY" != "true" ]]; then
    schedule_mark_done
fi

# --- Update JSON data ---
json_set "updates_total" "$PKG_UPDATES_TOTAL"
json_set "updates_security" "$PKG_UPDATES_SECURITY"
json_set "updates_flatpak" "$PKG_UPDATES_FLATPAK"
json_set "updates_snap" "$PKG_UPDATES_SNAP"

# --- Self-update check (non-blocking) ---
SELFUPDATE_AVAILABLE=""
SELFUPDATE_AVAILABLE=$(selfupdate_check 2>/dev/null) || true

# --- Exit if no updates ---
TOTAL_UPDATES=$((PKG_UPDATES_TOTAL + PKG_UPDATES_FLATPAK + PKG_UPDATES_SNAP))

if [[ "$TOTAL_UPDATES" -eq 0 ]]; then
    log_info "System is up to date"
    json_set "updates_critical" "0"
    _finalize

    if [[ "$CHECK_ONLY" == "true" ]]; then
        if [[ "$_JSON_MODE" == "true" ]]; then
            json_emit "$EXIT_OK"
        else
            output_banner "nudge: 0 updates available" "everything is up to date"
        fi
        exit "$EXIT_OK"
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        json_emit "$EXIT_OK"
        [[ "$_JSON_MODE" != "true" ]] && echo "Dry run — no updates, nothing to show"
        exit "$EXIT_OK"
    fi

    bunny_reset_streak

    # Still notify about self-update if available
    if [[ -n "$SELFUPDATE_AVAILABLE" ]]; then
        notify_detect
        notify_selfupdate "$NUDGE_VERSION" "$SELFUPDATE_AVAILABLE"
    fi

    json_emit "$EXIT_OK"
    history_write "NO_UPDATES" "" "$EXIT_OK"
    exit "$EXIT_OK"
fi

# --- Package details (also computes the critical count) ---
if [[ -z "$PKG_UPDATE_LIST" ]]; then
    pkgmgr_list_updates
fi
json_set "updates_critical" "$PKG_UPDATES_CRITICAL"
json_set "packages" "$(pkgmgr_build_json_packages)"
_DIALOG_READY=true

# --- Check-only mode ---
if [[ "$CHECK_ONLY" == "true" ]]; then
    if [[ "$_JSON_MODE" == "true" ]]; then
        _finalize
        json_emit "$EXIT_OK"
    else
        _CHECK_TOTAL=$((PKG_UPDATES_TOTAL + PKG_UPDATES_FLATPAK + PKG_UPDATES_SNAP))
        _CHECK_SEC="${PKG_UPDATES_SECURITY:-0}"
        _CHECK_CRIT="${PKG_UPDATES_CRITICAL:-0}"
        _CHECK_DETAIL=""
        [[ "$_CHECK_SEC" -gt 0 ]] && _CHECK_DETAIL="${_CHECK_SEC} security"
        [[ "$_CHECK_CRIT" -gt 0 ]] && { [[ -n "$_CHECK_DETAIL" ]] && _CHECK_DETAIL+=" · "; _CHECK_DETAIL+="${_CHECK_CRIT} critical"; }
        [[ -z "$_CHECK_DETAIL" ]] && _CHECK_DETAIL="all standard priority"
        output_banner "nudge: ${_CHECK_TOTAL} updates available" "$_CHECK_DETAIL"
    fi
    exit "$EXIT_OK"
fi

# --- Build preview if enabled ---
PREVIEW_TEXT=""
if [[ "${PREVIEW_UPDATES:-true}" == "true" ]]; then
    PREVIEW_TEXT=$(pkgmgr_build_preview 30)
fi

# --- Build dialog message ---
_CHECK_TOTAL=$((PKG_UPDATES_TOTAL + PKG_UPDATES_FLATPAK + PKG_UPDATES_SNAP))
_CHECK_SEC="${PKG_UPDATES_SECURITY:-0}"
_CHECK_CRIT="${PKG_UPDATES_CRITICAL:-0}"
_CHECK_DETAIL=""
[[ "$_CHECK_SEC" -gt 0 ]] && _CHECK_DETAIL="${_CHECK_SEC} security"
[[ "$_CHECK_CRIT" -gt 0 ]] && { [[ -n "$_CHECK_DETAIL" ]] && _CHECK_DETAIL+=" · "; _CHECK_DETAIL+="${_CHECK_CRIT} critical"; }
[[ -z "$_CHECK_DETAIL" ]] && _CHECK_DETAIL="all standard priority"

# The bunny: one line and one mood for this run, shared by every backend
_BUNNY_STREAK=$(bunny_get_streak)
DIALOG_QUOTE=$(bunny_say "prompt" "$TOTAL_UPDATES")
DIALOG_MOOD=$(bunny_mood "prompt" "$_BUNNY_STREAK" "$TOTAL_UPDATES")
DIALOG_HINT=""
DIALOG_NOTE=""
BUNNY_MSG=$(bunny_render "prompt" "nudge: ${_CHECK_TOTAL} updates · ${_CHECK_DETAIL}" "$TOTAL_UPDATES" "$DIALOG_QUOTE")
MSG="${BUNNY_MSG}\n\nWould you like to update now?"
if [[ "${SELECT_UPDATES:-true}" == "true" ]]; then
    DIALOG_HINT="You choose what to install next."
else
    DIALOG_HINT="Everything will be installed."
fi
MSG+="\n${DIALOG_HINT}"
if pkgmgr_custom_update_command; then
    DIALOG_NOTE="Update command (from your config): $(_build_upgrade_cmd)"
    MSG+="\n${DIALOG_NOTE}"
fi

if [[ -n "$SELFUPDATE_AVAILABLE" ]]; then
    DIALOG_NOTE+="${DIALOG_NOTE:+  }nudge v${SELFUPDATE_AVAILABLE} is available: run nudge --self-update"
    MSG+="\n\n(nudge v${SELFUPDATE_AVAILABLE} is available — run: nudge --self-update)"
fi

# --- Dry run exits here ---
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry run — would show dialog"
    notify_detect
    if [[ "$_JSON_MODE" != "true" ]]; then
        echo "Backend: $NOTIFY_BACKEND"
        [[ "$NOTIFY_BACKEND" == "none" ]] && echo "Warning: a real run would fail here with no notification backend (install kdialog or zenity)"
        echo "Message: $(echo -e "$MSG")"
        if [[ -n "$PREVIEW_TEXT" ]]; then
            echo "Preview:"
            echo "$PREVIEW_TEXT"
        fi
        if [[ -n "$NUDGE_MASCOT_DIR" ]]; then
            echo "Mascot: ${DIALOG_MOOD} (${NUDGE_MASCOT_DIR})"
        else
            echo "Mascot: not installed (the text bunny only)"
        fi
    fi
    _finalize
    json_emit "$EXIT_OK"
    exit "$EXIT_OK"
fi

# --- No display session: a timer or login run just skips, quietly ---
if ! _has_display && [[ "$_NUDGE_TRIGGER" != "manual" ]]; then
    log_info "No display session (DISPLAY/WAYLAND_DISPLAY unset) — skipping the prompt"
    _finalize
    json_emit "$EXIT_OK"
    history_write "SKIPPED_NO_DISPLAY" "trigger: $_NUDGE_TRIGGER" "$EXIT_OK"
    exit "$EXIT_OK"
fi

# --- Detect notification backend ---
notify_detect
if [[ "$NOTIFY_BACKEND" == "none" ]]; then
    log_error "No notification backend available"
    json_emit "$EXIT_NO_BACKEND"
    history_write "NO_BACKEND" "" "$EXIT_NO_BACKEND"
    _exit_error "$EXIT_NO_BACKEND" "No notification backend (install kdialog, zenity, or dunst)"
fi

# --- Show prompt (the preview text is for dunstify's body; the dialogs draw their own) ---
if ! notify_prompt "$MSG" "$PREVIEW_TEXT"; then
    json_emit "$EXIT_NO_BACKEND"
    history_write "PROMPT_FAILED" "backend ${NOTIFY_BACKEND:-none} could not show the dialog" "$EXIT_NO_BACKEND"
    _exit_error "$EXIT_NO_BACKEND" "Notification prompt failed (backend: ${NOTIFY_BACKEND:-none})"
fi

# --- Handle response ---
case "$NOTIFY_RESPONSE" in
    accepted)
        log_info "User accepted update"

        # What to install: everything, the important ones, one source, or one
        # by one in the terminal. The picker needs kdialog or zenity; without
        # them the terminal menu does the picking.
        _SCOPE="all"
        if [[ "${SELECT_UPDATES:-true}" == "true" ]]; then
            if ! _SCOPE=$(dialog_scope_pick "$(bunny_mood accepted)"); then
                log_info "User cancelled at the scope picker"
                bunny_increment_streak
                _finalize
                json_emit "$EXIT_UPDATES_DECLINED"
                history_write "DECLINED" "Cancelled at the scope picker" "$EXIT_UPDATES_DECLINED"
                _nudge_exit "$EXIT_UPDATES_DECLINED"
            fi
        fi
        log_info "Scope: $_SCOPE"
        bunny_reset_streak
        json_set "scope" "\"$(json_escape "$_SCOPE")\""

        # The menu (when picking one by one), the optional snapshot and the
        # upgrades all run inside a terminal window, where sudo can ask
        _UPGRADE_RC=0
        if pkgmgr_upgrade "$_SCOPE"; then _UPGRADE_RC=0; else _UPGRADE_RC=$?; fi

        if [[ -n "${_UPG_SNAPSHOT_ID:-}" ]]; then
            json_set "snapshot_id" "\"$(json_escape "$_UPG_SNAPSHOT_ID")\""
        fi
        json_set "selected_system" "${_UPG_SELECTED_SYSTEM:-0}"
        json_set "selected_flatpak" "${_UPG_SELECTED_FLATPAK:-0}"
        json_set "selected_snap" "${_UPG_SELECTED_SNAP:-0}"
        _UPG_DETAIL="system:${_UPG_SYSTEM} (${_UPG_SELECTED_SYSTEM:-0}/${_UPG_TOTAL_SYSTEM:-0})"
        _UPG_DETAIL+=" flatpak:${_UPG_FLATPAK} (${_UPG_SELECTED_FLATPAK:-0}/${_UPG_TOTAL_FLATPAK:-0})"
        _UPG_DETAIL+=" snap:${_UPG_SNAP} (${_UPG_SELECTED_SNAP:-0}/${_UPG_TOTAL_SNAP:-0})"

        if [[ "$_UPGRADE_RC" -eq 2 ]]; then
            log_info "User cancelled at the selection menu"
            _finalize
            json_emit "$EXIT_UPDATES_DECLINED"
            history_write "DECLINED" "Cancelled at the selection menu" "$EXIT_UPDATES_DECLINED"
            _nudge_exit "$EXIT_UPDATES_DECLINED"
        fi

        if [[ "$_UPGRADE_RC" -eq 0 ]]; then
            log_info "Upgrade session completed: $_UPG_DETAIL"

            # Reboot detection
            safety_handle_reboot || true

            _extra_failures=""
            [[ "$_UPG_FLATPAK" == "failed" ]] && _extra_failures+=" flatpak"
            [[ "$_UPG_SNAP" == "failed" ]] && _extra_failures+=" snap"

            _finalize
            json_emit "$EXIT_UPDATES_APPLIED"
            history_write "APPLIED" "${_UPG_DETAIL}${_extra_failures:+; partial failures:$_extra_failures}" "$EXIT_UPDATES_APPLIED"
            _nudge_exit "$EXIT_UPDATES_APPLIED"
        else
            log_error "System upgrade failed: $_UPG_DETAIL"
            json_emit "$EXIT_UPDATES_FAILED"
            history_write "FAILED" "$_UPG_DETAIL" "$EXIT_UPDATES_FAILED"
            _exit_error "$EXIT_UPDATES_FAILED" "System upgrade failed (pkg_manager: ${DETECTED_PKGMGR:-unknown}; $_UPG_DETAIL)"
        fi
        ;;

    deferred)
        log_info "User chose to defer"
        json_set "deferred" "true"

        if ! schedule_prompt_defer; then
            # Deferral dialog cancelled — treat as decline
            log_info "Deferral cancelled"
            _finalize
            json_emit "$EXIT_UPDATES_DECLINED"
            history_write "DECLINED" "Deferral cancelled" "$EXIT_UPDATES_DECLINED"
            _nudge_exit "$EXIT_UPDATES_DECLINED"
        fi

        _finalize
        json_emit "$EXIT_DEFERRED"
        history_write "DEFERRED" "" "$EXIT_DEFERRED"
        _nudge_exit "$EXIT_DEFERRED"
        ;;

    passive)
        log_info "Passive notification shown (${NOTIFY_BACKEND}); no answer is possible on this backend"
        _finalize
        json_emit "$EXIT_OK"
        history_write "NOTIFIED" "passive backend ${NOTIFY_BACKEND}" "$EXIT_OK"
        exit "$EXIT_OK"
        ;;

    declined|*)
        log_info "User declined update"
        bunny_increment_streak
        _finalize
        json_emit "$EXIT_UPDATES_DECLINED"
        history_write "DECLINED" "" "$EXIT_UPDATES_DECLINED"
        _nudge_exit "$EXIT_UPDATES_DECLINED"
        ;;
esac
