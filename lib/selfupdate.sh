#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — lib/selfupdate.sh
# GitHub release self-update check

set -euo pipefail

SELFUPDATE_STATE_FILE="${NUDGE_STATE_DIR:-$HOME/.local/share/nudge}/selfupdate_last_check"
SELFUPDATE_REPO="otmof-ops/nudge"

# A release tag is a plain version; a download URL stays on GitHub over https
_selfupdate_valid_version() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]
}
_selfupdate_valid_url() {
    [[ "$1" =~ ^https://(api\.github\.com|github\.com|codeload\.github\.com|objects\.githubusercontent\.com)/ ]]
}

# The API endpoint for the configured channel
_selfupdate_api_url() {
    local channel="${SELF_UPDATE_CHANNEL:-stable}"
    if [[ "$channel" == "stable" ]]; then
        echo "https://api.github.com/repos/${SELFUPDATE_REPO}/releases/latest"
    else
        echo "https://api.github.com/repos/${SELFUPDATE_REPO}/releases"
    fi
}

# --- Semantic version comparison ---
# Returns 0 if version $1 > $2. A pre-release (2.1.0-rc1) ranks below its
# release (2.1.0); anything that is not digits counts as 0.
version_gt() {
    local v1="$1" v2="$2"

    # Strip leading 'v' if present
    v1="${v1#v}"
    v2="${v2#v}"

    # Split off pre-release suffixes
    local pre1="" pre2=""
    [[ "$v1" == *-* ]] && { pre1="${v1#*-}"; v1="${v1%%-*}"; }
    [[ "$v2" == *-* ]] && { pre2="${v2#*-}"; v2="${v2%%-*}"; }

    local IFS='.'
    local -a a1 a2
    read -ra a1 <<< "$v1"
    read -ra a2 <<< "$v2"

    local i
    for i in 0 1 2; do
        local n1="${a1[$i]:-0}" n2="${a2[$i]:-0}"
        n1="${n1//[!0-9]/}"; n2="${n2//[!0-9]/}"
        n1="${n1:-0}"; n2="${n2:-0}"
        if [[ "$n1" -gt "$n2" ]]; then
            return 0
        elif [[ "$n1" -lt "$n2" ]]; then
            return 1
        fi
    done
    # Same numbers: a release beats a pre-release; otherwise not greater
    [[ -z "$pre1" && -n "$pre2" ]] && return 0
    return 1
}

# --- Fetch helpers: https only, no redirects to anything else ---
_selfupdate_fetch() {
    local url="$1" max="${2:-10}"
    if command -v curl &>/dev/null; then
        curl -fsSL --proto '=https' --proto-redir '=https' --max-time "$max" "$url" 2>/dev/null
    elif command -v wget &>/dev/null; then
        wget -q --https-only --timeout="$max" -O- "$url" 2>/dev/null
    else
        return 1
    fi
}

_selfupdate_download() {
    local url="$1" dest="$2" max="${3:-60}"
    if command -v curl &>/dev/null; then
        curl -fsSL --proto '=https' --proto-redir '=https' --max-time "$max" -o "$dest" "$url" 2>/dev/null
    elif command -v wget &>/dev/null; then
        wget -q --https-only --timeout="$max" -O "$dest" "$url" 2>/dev/null
    else
        return 1
    fi
}

# --- Verify an extracted release tree against its SHA256SUMS ---
# Every listed file must match, and every shipped script in the tree must be
# listed: a file the release never hashed is a file we never run.
# Usage: _selfupdate_verify_tree <extract_dir> <checksums_file>
_selfupdate_verify_tree() {
    local extract_dir="$1" checksums_file="$2"
    local line expected_hash file_path verify_count=0
    declare -A verified=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^([0-9a-fA-F]{64})[[:space:]]+\*?(.+)$ ]] || continue
        expected_hash="${BASH_REMATCH[1],,}"
        file_path="${BASH_REMATCH[2]}"
        file_path="${file_path#./}"
        [[ "$file_path" == /* || "$file_path" == *..* ]] && continue
        local check_path="$extract_dir/$file_path"
        [[ -f "$check_path" ]] || continue
        local actual_hash
        actual_hash=$(sha256sum "$check_path" | awk '{print $1}')
        if [[ "$actual_hash" != "$expected_hash" ]]; then
            echo "Error: Checksum mismatch for $file_path"
            echo "  Expected: $expected_hash"
            echo "  Got:      $actual_hash"
            return 1
        fi
        verified["$file_path"]=1
        verify_count=$((verify_count + 1))
    done < "$checksums_file"

    if [[ "$verify_count" -eq 0 ]]; then
        echo "Error: No files could be verified against checksums. Aborting."
        return 1
    fi

    local f rel
    for f in "$extract_dir"/nudge.sh "$extract_dir"/setup.sh "$extract_dir"/install.sh "$extract_dir"/uninstall.sh "$extract_dir"/lib/*.sh; do
        [[ -f "$f" ]] || continue
        rel="${f#"$extract_dir"/}"
        if [[ -z "${verified[$rel]:-}" ]]; then
            echo "Error: $rel is in the release but not in SHA256SUMS. Aborting for safety."
            return 1
        fi
    done

    echo "SHA256 checksums verified ($verify_count files)."
    return 0
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

    # Validate timestamp format — corrupt state files should not bypass rate limit
    if [[ ! "$last" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
        log_warn "Corrupt selfupdate state file — resetting"
        selfupdate_mark_checked
        return 1
    fi

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
# _SELFUPDATE_STATUS says why there was nothing: not-due, unreachable, unparseable, up-to-date
_SELFUPDATE_STATUS=""
selfupdate_check() {
    local current_version="${NUDGE_VERSION:-2.0.0}"
    local channel="${SELF_UPDATE_CHANNEL:-stable}"
    _SELFUPDATE_STATUS=""

    if ! selfupdate_check_due; then
        log_debug "Self-update check not due"
        _SELFUPDATE_STATUS="not-due"
        return 1
    fi

    local api_url
    api_url=$(_selfupdate_api_url)

    local response=""
    response=$(_selfupdate_fetch "$api_url" 10) || true

    if [[ -z "$response" ]]; then
        log_debug "Self-update check: no response from GitHub (will retry next run)"
        _SELFUPDATE_STATUS="unreachable"
        return 1
    fi

    # The window is spent only once a response came back
    selfupdate_mark_checked

    local latest_version
    if [[ "$channel" == "stable" ]]; then
        latest_version=$(echo "$response" | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/')
    else
        # Beta channel: include prereleases — grab the newest tag from the array
        latest_version=$(echo "$response" | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/')
    fi

    if [[ -z "$latest_version" ]] || ! _selfupdate_valid_version "$latest_version"; then
        log_debug "Self-update check: couldn't parse version"
        _SELFUPDATE_STATUS="unparseable"
        return 1
    fi

    if version_gt "$latest_version" "$current_version"; then
        log_info "New nudge version available: v$latest_version (current: v$current_version)"
        _SELFUPDATE_STATUS="available"
        echo "$latest_version"
        return 0
    fi

    log_debug "nudge is up to date (v$current_version)"
    _SELFUPDATE_STATUS="up-to-date"
    return 1
}

# --- Download and install update ---
selfupdate_install() {
    local current_version="${NUDGE_VERSION:-2.0.0}"
    local channel="${SELF_UPDATE_CHANNEL:-stable}"

    echo "Checking for updates (channel: $channel)..."

    local api_url
    api_url=$(_selfupdate_api_url)
    local response=""
    response=$(_selfupdate_fetch "$api_url" 10) || true

    if [[ -z "$response" ]]; then
        echo "Error: Could not reach GitHub API"
        return 1
    fi

    local latest_version
    latest_version=$(echo "$response" | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/')

    if [[ -z "$latest_version" ]] || ! _selfupdate_valid_version "$latest_version"; then
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

    if ! _selfupdate_valid_url "$tarball_url"; then
        echo "Error: Release download URL is not on GitHub over https"
        return 1
    fi

    # Download to temp directory
    local tmpdir
    tmpdir=$(mktemp -d)
    local tarball="$tmpdir/nudge-${latest_version}.tar.gz"

    _selfupdate_download "$tarball_url" "$tarball" 60 || {
        echo "Error: Download failed"
        rm -rf "$tmpdir"
        return 1
    }

    # Extract tarball into its own directory, as this user, without special files
    mkdir -p "$tmpdir/src"
    tar -xzf "$tarball" -C "$tmpdir/src" --no-same-owner --no-same-permissions 2>/dev/null || {
        echo "Error: Extraction failed"
        rm -rf "$tmpdir"
        return 1
    }

    local extract_dir
    extract_dir=$(find "$tmpdir/src" -mindepth 1 -maxdepth 1 -type d | head -1)
    local top_count
    top_count=$(find "$tmpdir/src" -mindepth 1 -maxdepth 1 | wc -l)

    if [[ -z "$extract_dir" ]] || [[ "$top_count" -ne 1 ]] || [[ ! -f "$extract_dir/install.sh" ]]; then
        echo "Error: Invalid release archive"
        rm -rf "$tmpdir"
        return 1
    fi

    # Verify extracted files against SHA256SUMS (mandatory)
    local checksum_url
    checksum_url=$(echo "$response" | grep -oE '"browser_download_url":[[:space:]]*"[^"]*SHA256[^"]*"' | head -1 | sed 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/')
    if [[ -z "$checksum_url" ]] || ! _selfupdate_valid_url "$checksum_url"; then
        echo "Error: No SHA256 checksum found in release. Aborting for safety."
        rm -rf "$tmpdir"
        return 1
    fi
    local checksums_file="$tmpdir/SHA256SUMS"
    _selfupdate_download "$checksum_url" "$checksums_file" 30 || true
    if [[ ! -s "$checksums_file" ]]; then
        echo "Error: Could not download SHA256 checksums. Aborting for safety."
        rm -rf "$tmpdir"
        return 1
    fi
    if ! _selfupdate_verify_tree "$extract_dir" "$checksums_file"; then
        echo "Error: Integrity verification failed. Aborting."
        rm -rf "$tmpdir"
        return 1
    fi

    # GPG signature verification (if gpg available and .asc signature exists)
    local sig_url
    sig_url=$(echo "$response" | grep -oE '"browser_download_url":[[:space:]]*"[^"]*\.asc"' | head -1 | sed 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/')
    if [[ -n "$sig_url" ]] && _selfupdate_valid_url "$sig_url" && command -v gpg &>/dev/null; then
        local sig_file="$tmpdir/SHA256SUMS.asc"
        _selfupdate_download "$sig_url" "$sig_file" 30 || true
        if [[ -f "$sig_file" ]]; then
            if gpg --verify "$sig_file" "$checksums_file" 2>/dev/null; then
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

    echo "Installing v$latest_version..."
    local -a install_args=(--upgrade --unattended)
    [[ -n "${NUDGE_PREFIX:-}" ]] && install_args+=("--prefix=${NUDGE_PREFIX}")
    (cd "$extract_dir" && bash install.sh "${install_args[@]}") || {
        echo "Error: Installation failed"
        rm -rf "$tmpdir"
        return 1
    }

    rm -rf "$tmpdir"
    echo "nudge updated to v$latest_version successfully!"
    return 0
}
