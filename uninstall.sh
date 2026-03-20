#!/usr/bin/env bash
# nudge uninstaller — delegates to setup.sh
# Copyright (c) 2026 OFFTRACKMEDIA Studios. All rights reserved.
# Version: 2.0.0

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
