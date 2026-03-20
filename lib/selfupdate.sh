#!/usr/bin/env bash
# nudge — lib/selfupdate.sh
# GitHub release self-update check
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

SELFUPDATE_STATE_FILE="${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/selfupdate_last_check"
SELFUPDATE_REPO="otmof-ops/nudge"

# --- Semantic version comparison ---
# Returns 0 if version $1 > $2
version_gt() {
    local v1="$1" v2="$2"

    # Strip leading 'v' if present
    v1="${v1#v}"
    v2="${v2#v}"

    local IFS='.'
    local -a a1 a2
    read -ra a1 <<< "$v1"
    read -ra a2 <<< "$v2"

    local i
    for i in 0 1 2; do
        local n1="${a1[$i]:-0}" n2="${a2[$i]:-0}"
        if [[ "$n1" -gt "$n2" ]]; then
            return 0
        elif [[ "$n1" -lt "$n2" ]]; then
            return 1
        fi
    done
    return 1  # equal
}

# --- Check if self-update check is due (rate limit: 24h) ---
selfupdate_check_due() {
    [[ "${SELF_UPDATE_CHECK:-true}" != "true" ]] && return 1

    if [[ ! -f "$SELFUPDATE_STATE_FILE" ]]; then
        return 0
    fi

    local last
    last=$(cat "$SELFUPDATE_STATE_FILE" 2>/dev/null || true)
    [[ -z "$last" ]] && return 0

    local last_epoch now_epoch elapsed
    last_epoch=$(date -d "$last" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    elapsed=$(( (now_epoch - last_epoch) / 3600 ))

    [[ "$elapsed" -ge 24 ]] && return 0
    return 1
}

# --- Mark self-update check done ---
selfupdate_mark_checked() {
    mkdir -p "$(dirname "$SELFUPDATE_STATE_FILE")" 2>/dev/null || true
    local ts tmp
    ts=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
    tmp=$(mktemp "${SELFUPDATE_STATE_FILE}.XXXXXX") && echo "$ts" > "$tmp" && mv "$tmp" "$SELFUPDATE_STATE_FILE"
}

# --- Check for new release ---
selfupdate_check() {
    local current_version="${NUDGE_VERSION:-2.0.0}"
    local channel="${SELF_UPDATE_CHANNEL:-stable}"

    if ! selfupdate_check_due; then
        log_debug "Self-update check not due"
        return 1
    fi

    selfupdate_mark_checked

    local api_url
    if [[ "$channel" == "stable" ]]; then
        api_url="https://api.github.com/repos/${SELFUPDATE_REPO}/releases/latest"
    else
        api_url="https://api.github.com/repos/${SELFUPDATE_REPO}/releases"
    fi

    local response=""
    if command -v curl &>/dev/null; then
        response=$(curl -s --max-time 10 "$api_url" 2>/dev/null) || true
    elif command -v wget &>/dev/null; then
        response=$(wget -q --timeout=10 -O- "$api_url" 2>/dev/null) || true
    fi

    if [[ -z "$response" ]]; then
        log_debug "Self-update check: no response from GitHub"
        return 1
    fi

    local latest_version
    if [[ "$channel" == "stable" ]]; then
        latest_version=$(echo "$response" | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/')
    else
        # Get first non-prerelease, or first release for beta
        latest_version=$(echo "$response" | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/')
    fi

    if [[ -z "$latest_version" ]]; then
        log_debug "Self-update check: couldn't parse version"
        return 1
    fi

    if version_gt "$latest_version" "$current_version"; then
        log_info "New nudge version available: v$latest_version (current: v$current_version)"
        echo "$latest_version"
        return 0
    fi

    log_debug "nudge is up to date (v$current_version)"
    return 1
}

# --- Download and install update ---
selfupdate_install() {
    local current_version="${NUDGE_VERSION:-2.0.0}"
    local channel="${SELF_UPDATE_CHANNEL:-stable}"

    echo "Checking for updates..."

    local api_url="https://api.github.com/repos/${SELFUPDATE_REPO}/releases/latest"
    local response=""

    if command -v curl &>/dev/null; then
        response=$(curl -s --max-time 10 "$api_url" 2>/dev/null) || true
    elif command -v wget &>/dev/null; then
        response=$(wget -q --timeout=10 -O- "$api_url" 2>/dev/null) || true
    fi

    if [[ -z "$response" ]]; then
        echo "Error: Could not reach GitHub API"
        return 1
    fi

    local latest_version
    latest_version=$(echo "$response" | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/')

    if [[ -z "$latest_version" ]]; then
        echo "Error: Could not determine latest version"
        return 1
    fi

    if ! version_gt "$latest_version" "$current_version"; then
        echo "Already up to date (v$current_version)"
        return 0
    fi

    echo "Downloading nudge v$latest_version..."

    # Get tarball URL
    local tarball_url
    tarball_url=$(echo "$response" | grep -oE '"tarball_url":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tarball_url":[[:space:]]*"\([^"]*\)".*/\1/')

    if [[ -z "$tarball_url" ]]; then
        echo "Error: Could not find download URL"
        return 1
    fi

    # Download to temp directory
    local tmpdir
    tmpdir=$(mktemp -d)
    local tarball="$tmpdir/nudge-${latest_version}.tar.gz"

    if command -v curl &>/dev/null; then
        curl -sL --max-time 60 -o "$tarball" "$tarball_url" 2>/dev/null || {
            echo "Error: Download failed"
            rm -rf "$tmpdir"
            return 1
        }
    elif command -v wget &>/dev/null; then
        wget -q --timeout=60 -O "$tarball" "$tarball_url" 2>/dev/null || {
            echo "Error: Download failed"
            rm -rf "$tmpdir"
            return 1
        }
    fi

    # Check SHA256 (mandatory)
    local checksum_url
    checksum_url=$(echo "$response" | grep -oE '"browser_download_url":[[:space:]]*"[^"]*SHA256[^"]*"' | head -1 | sed 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/')
    if [[ -z "$checksum_url" ]]; then
        echo "Error: No SHA256 checksum found in release. Aborting for safety."
        rm -rf "$tmpdir"
        return 1
    fi
    local expected_hash
    if command -v curl &>/dev/null; then
        expected_hash=$(curl -sL "$checksum_url" 2>/dev/null | awk '{print $1}')
    elif command -v wget &>/dev/null; then
        expected_hash=$(wget -q -O- "$checksum_url" 2>/dev/null | awk '{print $1}')
    fi
    if [[ -z "$expected_hash" ]]; then
        echo "Error: Could not download SHA256 checksum. Aborting for safety."
        rm -rf "$tmpdir"
        return 1
    fi
    local actual_hash
    actual_hash=$(sha256sum "$tarball" | awk '{print $1}')
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        echo "Error: Checksum mismatch! Aborting."
        echo "  Expected: $expected_hash"
        echo "  Got:      $actual_hash"
        rm -rf "$tmpdir"
        return 1
    fi
    echo "SHA256 checksum verified."

    # GPG signature verification (if gpg available and .asc signature exists)
    local sig_url
    sig_url=$(echo "$response" | grep -oE '"browser_download_url":[[:space:]]*"[^"]*\.asc"' | head -1 | sed 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/')
    if [[ -n "$sig_url" ]] && command -v gpg &>/dev/null; then
        local sig_file="$tmpdir/SHA256SUMS.asc"
        local checksum_file="$tmpdir/SHA256SUMS"
        echo "$expected_hash  $(basename "$tarball")" > "$checksum_file"
        if command -v curl &>/dev/null; then
            curl -sL -o "$sig_file" "$sig_url" 2>/dev/null
        elif command -v wget &>/dev/null; then
            wget -q -O "$sig_file" "$sig_url" 2>/dev/null
        fi
        if [[ -f "$sig_file" ]]; then
            if gpg --verify "$sig_file" "$checksum_file" 2>/dev/null; then
                echo "GPG signature verified."
            else
                echo "Error: GPG signature verification failed! Aborting."
                rm -rf "$tmpdir"
                return 1
            fi
        fi
    elif [[ -n "$sig_url" ]] && ! command -v gpg &>/dev/null; then
        echo "Warning: GPG signature available but gpg not installed. Skipping signature verification."
        echo "  Install gnupg for enhanced security: sudo apt install gnupg"
    fi

    # Extract and install
    tar xzf "$tarball" -C "$tmpdir" 2>/dev/null || {
        echo "Error: Extraction failed"
        rm -rf "$tmpdir"
        return 1
    }

    local extract_dir
    extract_dir=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1)

    if [[ -z "$extract_dir" ]] || [[ ! -f "$extract_dir/install.sh" ]]; then
        echo "Error: Invalid release archive"
        rm -rf "$tmpdir"
        return 1
    fi

    echo "Installing v$latest_version..."
    (cd "$extract_dir" && bash install.sh --upgrade --unattended) || {
        echo "Error: Installation failed"
        rm -rf "$tmpdir"
        return 1
    }

    rm -rf "$tmpdir"
    echo "nudge updated to v$latest_version successfully!"
    return 0
}
