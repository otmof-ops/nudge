#!/usr/bin/env bash
# nudge uninstaller
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.

set -euo pipefail

echo "=== nudge uninstaller ==="
echo ""

# --- Remove script ---
if [[ -f "${HOME}/.local/bin/nudge.sh" ]]; then
    rm "${HOME}/.local/bin/nudge.sh"
    echo "Removed: ~/.local/bin/nudge.sh"
else
    echo "Not found: ~/.local/bin/nudge.sh"
fi

# --- Remove autostart entry ---
if [[ -f "${HOME}/.config/autostart/nudge.desktop" ]]; then
    rm "${HOME}/.config/autostart/nudge.desktop"
    echo "Removed: ~/.config/autostart/nudge.desktop"
else
    echo "Not found: ~/.config/autostart/nudge.desktop"
fi

# --- Remove lock file ---
LOCK="/tmp/nudge-${UID}.lock"
if [[ -f "$LOCK" ]]; then
    rm -f "$LOCK"
    echo "Removed: $LOCK"
fi

# --- Ask about config ---
if [[ -f "${HOME}/.config/nudge.conf" ]]; then
    echo ""
    read -rp "Remove ~/.config/nudge.conf? (y/N): " ANSWER
    if [[ "${ANSWER,,}" == "y" ]]; then
        rm "${HOME}/.config/nudge.conf"
        echo "Removed: ~/.config/nudge.conf"
    else
        echo "Kept:    ~/.config/nudge.conf"
    fi
fi

echo ""
echo "nudge uninstalled."
