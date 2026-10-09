#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge uninstaller — delegates to setup.sh
# Version: 2.2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/setup.sh" ]]; then
    echo "Error: setup.sh not found in $SCRIPT_DIR" >&2
    exit 1
fi

args=()
for arg in "$@"; do
    case "$arg" in
        --yes|-y) args+=(--unattended) ;;
        *)        args+=("$arg") ;;
    esac
done

exec "$SCRIPT_DIR/setup.sh" --uninstall "${args[@]}"
