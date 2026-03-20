#!/usr/bin/env bash
# nudge — A gentle nudge to keep your system fresh.
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.
# Version: 2.0.0

set -euo pipefail

NUDGE_VERSION="2.0.0"
_NUDGE_START_TIME=$(date +%s)
_NUDGE_TRIGGER="${_NUDGE_TRIGGER:-manual}"
case "$_NUDGE_TRIGGER" in
    manual|login|timer|cron) ;;
    *) _NUDGE_TRIGGER="manual" ;;
esac

# --- Locate lib directory ---
NUDGE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
if [[ ! -d "$NUDGE_LIB_DIR" ]]; then
    # Installed location fallback
    NUDGE_LIB_DIR="${HOME}/.local/lib/nudge"
fi

if [[ ! -d "$NUDGE_LIB_DIR" ]]; then
    echo "Error: nudge lib directory not found" >&2
    exit 10  # EXIT_CONFIG_ERROR — constants not yet sourced
fi

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
# shellcheck source=lib/tui.sh
source "$NUDGE_LIB_DIR/tui.sh"
# shellcheck source=lib/bunny-poses.sh
source "$NUDGE_LIB_DIR/bunny-poses.sh"
# shellcheck source=lib/bunny-dialogue.sh
source "$NUDGE_LIB_DIR/bunny-dialogue.sh"
# shellcheck source=lib/bunny.sh
source "$NUDGE_LIB_DIR/bunny.sh"

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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            echo "nudge $NUDGE_VERSION"
            exit "$EXIT_OK"
            ;;
        --help|-h)
            cat <<'HELP'

 (\__/)
 (='.'=)  nudge 2.0.0
 (")_(")  A gentle nudge to keep your system fresh.

Usage: nudge [OPTIONS]

Options:
  --version              Print version and exit
  --help, -h             Show this help
  --dry-run              Run checks but don't show dialogs
  --check-only           Print update count and exit
  --json                 Machine-readable JSON output
  --verbose              Verbose logging to stdout
  --history [N]          Show last N history records (default: 20)
  --history --json       Dump raw JSONL history
  --history --since DATE Filter history by date
  --defer DURATION       Defer next check (1h, 4h, 1d, 1w)
  --self-update          Download and install latest nudge
  --config               Print current resolved configuration
  --validate             Validate config and exit
  --migrate              Run config migration manually

Environment:
  XDG_CONFIG_HOME        Config directory (default: ~/.config)
  XDG_DATA_HOME          Data directory (default: ~/.local/share)

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
            _HISTORY_SINCE="${2:-}"
            shift
            ;;
        --defer)
            _DEFER_CMD="${2:-}"
            shift
            ;;
        --self-update) _SELF_UPDATE_CMD=true ;;
        --config)      _CONFIG_CMD=true ;;
        --validate)    _VALIDATE_CMD=true ;;
        --migrate)     _MIGRATE_CMD=true ;;
    esac
    shift
done

# --- Load config ---
config_load
config_ensure_dirs
output_init
bunny_init

# --- Handle utility commands (no lock needed) ---

if [[ "$_HISTORY_CMD" == "true" ]]; then
    [[ "$_JSON_FLAG" == "true" ]] && _HISTORY_FORMAT="json"
    history_show "$_HISTORY_COUNT" "$_HISTORY_FORMAT" "$_HISTORY_SINCE"
    exit "$EXIT_OK"
fi

if [[ "$_SELF_UPDATE_CMD" == "true" ]]; then
    selfupdate_install
    exit $?
fi

if [[ -n "$_DEFER_CMD" ]]; then
    schedule_defer "$_DEFER_CMD"
    echo "Next check deferred for $_DEFER_CMD"
    exit "$EXIT_DEFERRED"
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

# --- Disabled check ---
if [[ "$ENABLED" != "true" ]]; then
    log_info "nudge is disabled"
    exit "$EXIT_DISABLED"
fi

# --- Finalize duration ---
_finalize() {
    local end_time
    end_time=$(date +%s)
    json_set "duration_seconds" "$(( end_time - _NUDGE_START_TIME ))"
}

# --- Signal handling ---
CLEANUP_PIDS=()

# shellcheck disable=SC2317  # _cleanup is invoked via trap, not directly
_cleanup() {
    local sig="${1:-EXIT}"
    for pid in "${CLEANUP_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    tput cnorm 2>/dev/null || true

    # Calculate duration
    _finalize

    # Write history on non-EXIT signals
    if [[ "$sig" != "EXIT" ]]; then
        history_write "CANCELLED" "Signal: $sig" "$EXIT_INTERRUPTED"
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
        exit "$EXIT_ALREADY_RUNNING"
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
    log_warn "Reboot pending from previous upgrade"
    if [[ "$DRY_RUN" != "true" ]] && [[ "$CHECK_ONLY" != "true" ]]; then
        notify_detect
        if notify_reboot; then
            systemctl reboot 2>/dev/null || sudo reboot 2>/dev/null || true
        fi
    fi
fi

# --- Delay (skip for dry-run and check-only) ---
if [[ "$DRY_RUN" != "true" ]] && [[ "$CHECK_ONLY" != "true" ]]; then
    if [[ "${DELAY:-0}" -gt 0 ]]; then
        log_info "Waiting ${DELAY}s before checking for updates"
        sleep "$DELAY"
    fi
fi

# --- Network check ---
if ! network_check; then
    network_handle_offline
    _NETWORK_RC=$?
    json_emit "$_NETWORK_RC"
    exit "$_NETWORK_RC"
fi

# --- Detect package manager ---
if ! pkgmgr_detect; then
    log_error "No supported package manager found"
    json_emit "$EXIT_CONFIG_ERROR"
    exit "$EXIT_CONFIG_ERROR"
fi
json_set "pkg_manager" "$DETECTED_PKGMGR"

# --- Package manager lock check ---
if ! pkgmgr_lock_check; then
    json_emit "$EXIT_PKG_LOCK"
    exit "$EXIT_PKG_LOCK"
fi

# --- Count updates (system + flatpak + snap) ---
pkgmgr_count_updates
flatpak_count
snap_count

# --- Mark last check ---
schedule_mark_done

# --- Update JSON data ---
json_set "updates_total" "$PKG_UPDATES_TOTAL"
json_set "updates_security" "$PKG_UPDATES_SECURITY"
json_set "updates_critical" "$PKG_UPDATES_CRITICAL"
json_set "updates_flatpak" "$PKG_UPDATES_FLATPAK"
json_set "updates_snap" "$PKG_UPDATES_SNAP"

# --- Self-update check (non-blocking) ---
SELFUPDATE_AVAILABLE=""
SELFUPDATE_AVAILABLE=$(selfupdate_check 2>/dev/null) || true

# --- Exit if no updates ---
TOTAL_UPDATES=$((PKG_UPDATES_TOTAL + PKG_UPDATES_FLATPAK + PKG_UPDATES_SNAP))

if [[ "$TOTAL_UPDATES" -eq 0 ]]; then
    log_info "System is up to date"
    bunny_reset_streak

    # Still notify about self-update if available
    if [[ -n "$SELFUPDATE_AVAILABLE" ]] && [[ "$DRY_RUN" != "true" ]]; then
        notify_detect
        notify_selfupdate "$NUDGE_VERSION" "$SELFUPDATE_AVAILABLE"
    fi

    _finalize
    json_emit "$EXIT_OK"
    history_write "NO_UPDATES" "" "$EXIT_OK"
    exit "$EXIT_OK"
fi

# --- Check-only mode ---
if [[ "$CHECK_ONLY" == "true" ]]; then
    if [[ "$_JSON_FLAG" == "true" ]]; then
        # List updates for JSON detail
        pkgmgr_list_updates
        json_set "packages" "$(pkgmgr_build_json_packages)"
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
    pkgmgr_list_updates
    PREVIEW_TEXT=$(pkgmgr_build_preview 30)
    json_set "packages" "$(pkgmgr_build_json_packages)"
fi

# --- Build dialog message ---
MSG="$(pkgmgr_build_summary)"
# Build bunny-formatted message for dialog backends
_CHECK_TOTAL=$((PKG_UPDATES_TOTAL + PKG_UPDATES_FLATPAK + PKG_UPDATES_SNAP))
_CHECK_SEC="${PKG_UPDATES_SECURITY:-0}"
_CHECK_CRIT="${PKG_UPDATES_CRITICAL:-0}"
_CHECK_DETAIL=""
[[ "$_CHECK_SEC" -gt 0 ]] && _CHECK_DETAIL="${_CHECK_SEC} security"
[[ "$_CHECK_CRIT" -gt 0 ]] && { [[ -n "$_CHECK_DETAIL" ]] && _CHECK_DETAIL+=" · "; _CHECK_DETAIL+="${_CHECK_CRIT} critical"; }
[[ -z "$_CHECK_DETAIL" ]] && _CHECK_DETAIL="all standard priority"

# Bunny personality
BUNNY_MSG=$(bunny_render "prompt" "nudge: ${_CHECK_TOTAL} updates · ${_CHECK_DETAIL}" "$TOTAL_UPDATES")
MSG="${BUNNY_MSG}\n\nWould you like to update now?"

if [[ -n "$SELFUPDATE_AVAILABLE" ]]; then
    MSG+="\n\n(nudge v${SELFUPDATE_AVAILABLE} is available — run: nudge --self-update)"
fi

# --- Dry run exits here ---
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry run — would show dialog"
    notify_detect
    echo "Backend: $NOTIFY_BACKEND"
    echo "Message: $(echo -e "$MSG")"
    if [[ -n "$PREVIEW_TEXT" ]]; then
        echo "Preview:"
        echo "$PREVIEW_TEXT"
    fi
    _finalize
    json_emit "$EXIT_OK"
    exit "$EXIT_OK"
fi

# --- Detect notification backend ---
notify_detect
if [[ "$NOTIFY_BACKEND" == "none" ]]; then
    log_error "No notification backend available"
    json_emit "$EXIT_NO_BACKEND"
    history_write "NO_BACKEND" "" "$EXIT_NO_BACKEND"
    exit "$EXIT_NO_BACKEND"
fi

# --- Show prompt ---
if ! notify_prompt "$MSG" "$PREVIEW_TEXT"; then
    json_emit "$EXIT_NO_BACKEND"
    history_write "NO_BACKEND" "" "$EXIT_NO_BACKEND"
    exit "$EXIT_NO_BACKEND"
fi

# --- Handle response ---
case "$NOTIFY_RESPONSE" in
    accepted)
        log_info "User accepted update"
        bunny_reset_streak

        # Pre-upgrade snapshot
        if [[ "${SNAPSHOT_ENABLED:-false}" == "true" ]]; then
            if ! safety_snapshot; then
                log_error "Snapshot failed — aborting upgrade"
                json_emit "$EXIT_SNAPSHOT_FAILED"
                history_write "SNAPSHOT_FAILED" "" "$EXIT_SNAPSHOT_FAILED"
                exit "$EXIT_SNAPSHOT_FAILED"
            fi
        fi

        # Run system upgrade
        if pkgmgr_upgrade; then
            log_info "System upgrade completed"

            # Flatpak + Snap upgrades
            flatpak_upgrade
            snap_upgrade

            # Reboot detection
            safety_handle_reboot

            _finalize
            json_emit "$EXIT_UPDATES_APPLIED"
            history_write "APPLIED" "" "$EXIT_UPDATES_APPLIED"
            exit "$EXIT_UPDATES_APPLIED"
        else
            log_error "System upgrade failed"
            _finalize
            json_emit "$EXIT_UPDATES_FAILED"
            history_write "FAILED" "Upgrade command returned non-zero" "$EXIT_UPDATES_FAILED"
            exit "$EXIT_UPDATES_FAILED"
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
            exit "$EXIT_UPDATES_DECLINED"
        fi

        _finalize
        json_emit "$EXIT_DEFERRED"
        history_write "DEFERRED" "" "$EXIT_DEFERRED"
        exit "$EXIT_DEFERRED"
        ;;

    declined|*)
        log_info "User declined update"
        bunny_increment_streak
        _finalize
        json_emit "$EXIT_UPDATES_DECLINED"
        history_write "DECLINED" "" "$EXIT_UPDATES_DECLINED"
        exit "$EXIT_UPDATES_DECLINED"
        ;;
esac
