#!/usr/bin/env bash
# nudge — lib/errorreport.sh
# Crash report capture and automated GitHub issue filing
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

CRASH_REPORT_DIR="${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/crash-reports"
CRASH_REPORT_MAX=20
CRASH_REPORT_REPO="otmof-ops/nudge"

# Exit codes that are normal operation (not errors)
readonly _NORMAL_EXITS="0 1 2 4 9"

# --- Check if an exit code is an error ---
_is_error_exit() {
    local code="$1"
    local normal
    for normal in $_NORMAL_EXITS; do
        [[ "$code" == "$normal" ]] && return 1
    done
    return 0
}

# --- Collect system context ---
_collect_system_info() {
    local info=""

    # OS / distro
    if [[ -f /etc/os-release ]]; then
        info+="distro: $(. /etc/os-release && echo "${PRETTY_NAME:-$ID}")"$'\n'
    elif [[ -f /etc/lsb-release ]]; then
        info+="distro: $(. /etc/lsb-release && echo "${DISTRIB_DESCRIPTION:-unknown}")"$'\n'
    else
        info+="distro: unknown"$'\n'
    fi

    info+="kernel: $(uname -r 2>/dev/null || echo unknown)"$'\n'
    info+="arch: $(uname -m 2>/dev/null || echo unknown)"$'\n'
    info+="bash: ${BASH_VERSION:-unknown}"$'\n'
    info+="shell: $(readlink -f /proc/$$/exe 2>/dev/null || echo "$SHELL")"$'\n'

    # Desktop environment
    info+="desktop: ${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"$'\n'
    info+="session_type: ${XDG_SESSION_TYPE:-unknown}"$'\n'
    info+="display_server: ${WAYLAND_DISPLAY:+wayland}${DISPLAY:+x11}"$'\n'

    # Package manager
    info+="pkg_manager: ${DETECTED_PKGMGR:-not_detected}"$'\n'

    # Notification backend
    info+="notify_backend: ${NOTIFY_BACKEND:-not_detected}"$'\n'

    # Terminal
    info+="terminal: ${TERM:-unknown}"$'\n'

    # Flatpak/Snap
    command -v flatpak &>/dev/null && info+="flatpak: $(flatpak --version 2>/dev/null || echo installed)"$'\n'
    command -v snap &>/dev/null && info+="snap: $(snap version 2>/dev/null | head -1 || echo installed)"$'\n'

    printf '%s' "$info"
}

# --- Collect sanitized config ---
_collect_config_summary() {
    local summary=""
    # Include non-sensitive config keys only
    local safe_keys=(
        ENABLED DELAY CHECK_SECURITY AUTO_DISMISS
        NETWORK_HOST NETWORK_TIMEOUT NETWORK_RETRIES OFFLINE_MODE
        NOTIFICATION_BACKEND DUNST_APPNAME PREVIEW_UPDATES SECURITY_PRIORITY
        SCHEDULE_MODE SCHEDULE_INTERVAL_HOURS DEFERRAL_OPTIONS
        PKGMGR_OVERRIDE FLATPAK_ENABLED SNAP_ENABLED
        HISTORY_ENABLED HISTORY_MAX_LINES LOG_LEVEL JSON_OUTPUT
        REBOOT_CHECK SNAPSHOT_ENABLED SNAPSHOT_TOOL
        SELF_UPDATE_CHECK SELF_UPDATE_CHANNEL BUNNY_PERSONALITY
    )
    for key in "${safe_keys[@]}"; do
        local val="${!key:-}"
        [[ -n "$val" ]] && summary+="$key=$val"$'\n'
    done
    # Explicitly exclude UPDATE_COMMAND, LOG_FILE (may contain paths/secrets)
    summary+="UPDATE_COMMAND=[redacted]"$'\n'
    summary+="LOG_FILE=[redacted]"$'\n'
    printf '%s' "$summary"
}

# --- Write a crash report ---
errorreport_write() {
    local exit_code="${1:-0}"
    local error_context="${2:-}"

    # Only write reports for actual errors
    if ! _is_error_exit "$exit_code"; then
        return 0
    fi

    mkdir -p "$CRASH_REPORT_DIR" 2>/dev/null || return 0

    local reason="${EXIT_REASONS[$exit_code]:-UNKNOWN}"
    local ts
    ts=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
    local ts_file
    ts_file=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo "unknown")
    local report_file="${CRASH_REPORT_DIR}/crash-${ts_file}-${reason}.txt"

    {
        echo "# nudge crash report"
        echo "# Filed automatically — review before submitting"
        echo ""
        echo "## Error"
        echo "exit_code: $exit_code"
        echo "exit_reason: $reason"
        echo "timestamp: $ts"
        echo "nudge_version: ${NUDGE_VERSION:-unknown}"
        echo "trigger: ${_NUDGE_TRIGGER:-unknown}"
        [[ -n "$error_context" ]] && echo "context: $error_context"
        echo ""
        echo "## System"
        _collect_system_info
        echo ""
        echo "## Config (sanitized)"
        _collect_config_summary
        echo ""
        echo "## Recent Log"
        if [[ -n "${LOG_FILE:-}" ]] && [[ -f "$LOG_FILE" ]]; then
            tail -20 "$LOG_FILE" 2>/dev/null || echo "(could not read log file)"
        else
            echo "(no log file configured)"
        fi
        echo ""
        echo "## Recent History"
        if [[ -f "${HISTORY_FILE:-}" ]]; then
            tail -5 "$HISTORY_FILE" 2>/dev/null || echo "(could not read history)"
        else
            echo "(no history file)"
        fi
    } > "$report_file" 2>/dev/null || return 0

    log_info "Crash report saved: $report_file"

    # Rotate old reports
    _errorreport_rotate

    echo "$report_file"
}

# --- Rotate old crash reports ---
_errorreport_rotate() {
    [[ ! -d "$CRASH_REPORT_DIR" ]] && return 0
    local count
    count=$(find "$CRASH_REPORT_DIR" -name "crash-*.txt" -type f 2>/dev/null | wc -l || echo 0)
    if [[ "$count" -gt "$CRASH_REPORT_MAX" ]]; then
        local to_remove=$(( count - CRASH_REPORT_MAX ))
        # Remove oldest first (sorted by filename which includes timestamp)
        find "$CRASH_REPORT_DIR" -name "crash-*.txt" -type f 2>/dev/null \
            | sort | head -n "$to_remove" \
            | while IFS= read -r f; do rm -f "$f" 2>/dev/null; done
    fi
}

# --- List crash reports ---
errorreport_list() {
    local count="${1:-10}"
    local format="${2:-table}"

    if [[ ! -d "$CRASH_REPORT_DIR" ]]; then
        echo "No crash reports found."
        return 0
    fi

    local reports
    reports=$(find "$CRASH_REPORT_DIR" -name "crash-*.txt" -type f 2>/dev/null | sort -r | head -n "$count")

    if [[ -z "$reports" ]]; then
        echo "No crash reports found."
        return 0
    fi

    if [[ "$format" == "json" ]]; then
        local json="["
        local first=true
        while IFS= read -r report; do
            local code reason ts
            code=$(grep "^exit_code:" "$report" 2>/dev/null | cut -d' ' -f2)
            reason=$(grep "^exit_reason:" "$report" 2>/dev/null | cut -d' ' -f2)
            ts=$(grep "^timestamp:" "$report" 2>/dev/null | cut -d' ' -f2)
            [[ "$first" == "true" ]] && first=false || json+=","
            json+="{\"file\":\"$(json_escape "$report")\",\"exit_code\":${code:-0},\"exit_reason\":\"$(json_escape "${reason:-UNKNOWN}")\",\"timestamp\":\"$(json_escape "${ts:-}")\"}"
        done <<< "$reports"
        json+="]"
        echo "$json"
    else
        printf "%-20s  %-6s  %-18s  %s\n" "TIMESTAMP" "CODE" "REASON" "FILE"
        printf "%s\n" "$(printf '%.0s─' {1..80})"
        while IFS= read -r report; do
            local code reason ts basename_r
            code=$(grep "^exit_code:" "$report" 2>/dev/null | cut -d' ' -f2)
            reason=$(grep "^exit_reason:" "$report" 2>/dev/null | cut -d' ' -f2)
            ts=$(grep "^timestamp:" "$report" 2>/dev/null | cut -d' ' -f2)
            basename_r=$(basename "$report")
            printf "%-20s  %-6s  %-18s  %s\n" "${ts:0:19}" "${code:-?}" "${reason:-?}" "$basename_r"
        done <<< "$reports"
    fi
}

# --- Show a specific crash report ---
errorreport_show() {
    local target="${1:-latest}"

    if [[ "$target" == "latest" ]]; then
        target=$(find "$CRASH_REPORT_DIR" -name "crash-*.txt" -type f 2>/dev/null | sort -r | head -1)
        if [[ -z "$target" ]]; then
            echo "No crash reports found."
            return 1
        fi
    fi

    if [[ ! -f "$target" ]]; then
        echo "Crash report not found: $target" >&2
        return 1
    fi

    cat "$target"
}

# --- Build GitHub issue body from a crash report ---
_build_issue_body() {
    local report_file="$1"

    local code reason version ts context distro kernel desktop backend pkgmgr
    code=$(grep "^exit_code:" "$report_file" 2>/dev/null | cut -d' ' -f2-)
    reason=$(grep "^exit_reason:" "$report_file" 2>/dev/null | cut -d' ' -f2-)
    version=$(grep "^nudge_version:" "$report_file" 2>/dev/null | cut -d' ' -f2-)
    ts=$(grep "^timestamp:" "$report_file" 2>/dev/null | cut -d' ' -f2-)
    context=$(grep "^context:" "$report_file" 2>/dev/null | cut -d' ' -f2-)
    distro=$(grep "^distro:" "$report_file" 2>/dev/null | cut -d' ' -f2-)
    kernel=$(grep "^kernel:" "$report_file" 2>/dev/null | cut -d' ' -f2-)
    desktop=$(grep "^desktop:" "$report_file" 2>/dev/null | cut -d' ' -f2-)
    backend=$(grep "^notify_backend:" "$report_file" 2>/dev/null | cut -d' ' -f2-)
    pkgmgr=$(grep "^pkg_manager:" "$report_file" 2>/dev/null | cut -d' ' -f2-)

    cat <<ISSUE_EOF
## Automated Crash Report

**Exit Code:** ${code:-unknown} (${reason:-UNKNOWN})
**Version:** nudge v${version:-unknown}
**Timestamp:** ${ts:-unknown}
${context:+**Context:** $context}

### System Information

| Field | Value |
|-------|-------|
| Distro | ${distro:-unknown} |
| Kernel | ${kernel:-unknown} |
| Desktop | ${desktop:-unknown} |
| Notification Backend | ${backend:-unknown} |
| Package Manager | ${pkgmgr:-unknown} |
| Bash | ${BASH_VERSION:-unknown} |

### Sanitized Config

\`\`\`
$(sed -n '/^## Config/,/^## /{ /^## /d; p; }' "$report_file" 2>/dev/null | head -35)
\`\`\`

### Recent Log

\`\`\`
$(sed -n '/^## Recent Log/,/^## /{ /^## /d; p; }' "$report_file" 2>/dev/null | head -20)
\`\`\`

### Recent History

\`\`\`
$(sed -n '/^## Recent History/,/^$/{ p; }' "$report_file" 2>/dev/null | tail -5)
\`\`\`

---
*Filed automatically by \`nudge --report --file\`*
ISSUE_EOF
}

# --- File a GitHub issue from a crash report ---
errorreport_file_issue() {
    local report_file="${1:-}"

    # Default to latest report
    if [[ -z "$report_file" ]] || [[ "$report_file" == "latest" ]]; then
        report_file=$(find "$CRASH_REPORT_DIR" -name "crash-*.txt" -type f 2>/dev/null | sort -r | head -1)
        if [[ -z "$report_file" ]]; then
            echo "No crash reports found." >&2
            return 1
        fi
    fi

    if [[ ! -f "$report_file" ]]; then
        echo "Crash report not found: $report_file" >&2
        return 1
    fi

    # Require gh CLI
    if ! command -v gh &>/dev/null; then
        echo "Error: GitHub CLI (gh) is required to file issues." >&2
        echo "Install: https://cli.github.com/" >&2
        echo "" >&2
        echo "Alternatively, copy the report and file manually:" >&2
        echo "  cat $report_file" >&2
        echo "  https://github.com/${CRASH_REPORT_REPO}/issues/new" >&2
        return 1
    fi

    # Check gh auth
    if ! gh auth status &>/dev/null; then
        echo "Error: Not authenticated with GitHub CLI." >&2
        echo "Run: gh auth login" >&2
        return 1
    fi

    local code reason
    code=$(grep "^exit_code:" "$report_file" 2>/dev/null | cut -d' ' -f2)
    reason=$(grep "^exit_reason:" "$report_file" 2>/dev/null | cut -d' ' -f2)

    local title="[crash] EXIT_${reason:-UNKNOWN} (code ${code:-?}) — automated report"
    local body
    body=$(_build_issue_body "$report_file")

    # Confirm before filing
    echo "About to file issue on ${CRASH_REPORT_REPO}:"
    echo "  Title: $title"
    echo "  Report: $(basename "$report_file")"
    echo ""

    local confirm
    read -rp "File this issue? [y/N] " confirm </dev/tty 2>/dev/null \
        || read -rp "File this issue? [y/N] " confirm
    if [[ "${confirm,,}" != "y" && "${confirm,,}" != "yes" ]]; then
        echo "Cancelled."
        return 1
    fi

    local issue_url
    issue_url=$(gh issue create \
        --repo "$CRASH_REPORT_REPO" \
        --title "$title" \
        --body "$body" \
        --label "bug,automated-report" 2>&1) || {
        echo "Error: Failed to create issue." >&2
        echo "You can file manually at: https://github.com/${CRASH_REPORT_REPO}/issues/new" >&2
        return 1
    }

    echo "Issue filed: $issue_url"

    # Mark report as filed
    echo "" >> "$report_file"
    echo "# FILED: $issue_url" >> "$report_file"
    echo "# FILED_AT: $(date -Iseconds 2>/dev/null || date)" >> "$report_file"

    return 0
}

# --- Clear all crash reports ---
errorreport_clear() {
    if [[ -d "$CRASH_REPORT_DIR" ]]; then
        local count
        count=$(find "$CRASH_REPORT_DIR" -name "crash-*.txt" -type f 2>/dev/null | wc -l || echo 0)
        rm -f "$CRASH_REPORT_DIR"/crash-*.txt 2>/dev/null || true
        echo "Cleared $count crash report(s)."
    else
        echo "No crash reports directory found."
    fi
}
