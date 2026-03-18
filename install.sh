#!/usr/bin/env bash
# nudge installer
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== nudge installer ==="
echo "A gentle nudge to keep your system fresh."
echo ""

# --- Check dependencies ---
MISSING=()
command -v kdialog &>/dev/null || MISSING+=("kdialog")
command -v konsole &>/dev/null || MISSING+=("konsole")

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "ERROR: Missing required dependencies: ${MISSING[*]}"
    echo "Install them with: sudo apt install ${MISSING[*]}"
    exit 1
fi

# --- Create directories ---
mkdir -p "${HOME}/.local/bin"
mkdir -p "${HOME}/.config/autostart"

# --- Install nudge.sh ---
cp "${SCRIPT_DIR}/nudge.sh" "${HOME}/.local/bin/nudge.sh"
chmod +x "${HOME}/.local/bin/nudge.sh"
echo "Installed: ~/.local/bin/nudge.sh"

# --- Install desktop entry ---
sed "s|HOME_PLACEHOLDER|${HOME}|g" "${SCRIPT_DIR}/nudge.desktop" \
    > "${HOME}/.config/autostart/nudge.desktop"
echo "Installed: ~/.config/autostart/nudge.desktop"

# --- Install config (preserve existing) ---
if [[ ! -f "${HOME}/.config/nudge.conf" ]]; then
    cp "${SCRIPT_DIR}/nudge.conf" "${HOME}/.config/nudge.conf"
    echo "Installed: ~/.config/nudge.conf"
else
    echo "Skipped:   ~/.config/nudge.conf (already exists, preserving your config)"
fi

echo ""
echo "nudge installed successfully."
echo "It will run automatically on your next KDE login."
echo "To test now: ~/.local/bin/nudge.sh"
