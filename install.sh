#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge installer — delegates to setup.sh
# Version: 2.1.0

set -euo pipefail

# shellcheck disable=SC2034  # VERSION is for §10.2 compliance; install.sh delegates to setup.sh
VERSION="2.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/setup.sh" ]]; then
    echo "Error: setup.sh not found in $SCRIPT_DIR" >&2
    exit 1
fi

exec "$SCRIPT_DIR/setup.sh" --install "$@"
