#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — docs/assets/make-screenshots.sh
# Draws the dialogs and the terminal session with sample data on a virtual X
# display and writes docs/assets/screenshot-*.png; nothing reaches the real
# screen. The terminal picture runs the real session runner on a sample
# session file that asks for the menu, and the runner is killed once the
# picture is taken, so nothing is ever installed. Needs Xvfb, kdialog, konsole
# (or xterm), ImageMagick (import, convert) and xdotool. Run from the
# repository root:
#
#   docs/assets/make-screenshots.sh

# shellcheck disable=SC2034,SC2317  # the sample data is read by the sourced modules
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

for t in Xvfb kdialog import convert xdotool; do
    command -v "$t" >/dev/null 2>&1 || { echo "make-screenshots: missing $t" >&2; exit 1; }
done

OUT="docs/assets"
VDISPLAY=":97"
TMP=$(mktemp -d)
Xvfb "$VDISPLAY" -screen 0 1100x900x24 -nolisten tcp >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null || true; rm -rf "$TMP"' EXIT
sleep 1.5
export DISPLAY="$VDISPLAY" XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=5

# --- The sample data: one system of updates, the same in every picture ---
sample() {
    # shellcheck source=lib/output.sh
    source lib/output.sh
    # shellcheck source=lib/pkgmgr.sh
    source lib/pkgmgr.sh
    # shellcheck source=lib/notify.sh
    source lib/notify.sh
    # shellcheck source=lib/bunny-poses.sh
    source lib/bunny-poses.sh
    # shellcheck source=lib/bunny-dialogue.sh
    source lib/bunny-dialogue.sh
    # shellcheck source=lib/bunny.sh
    source lib/bunny.sh
    # shellcheck source=lib/dialog.sh
    source lib/dialog.sh
    NUDGE_MASCOT_DIR="$PWD/share/mascot"
    NUDGE_STATE_DIR="$TMP/state"
    DETECTED_PKGMGR=apt NOTIFY_BACKEND=kdialog _DIALOG_READY=true
    PKG_UPDATE_LIST=$'linux-image-generic|6.8.0-85.85|6.8.0-86.86|CRITICAL|amd64|0\nlinux-headers-generic|6.8.0-85.85|6.8.0-86.86|CRITICAL|amd64|0\nopenssl|3.0.13-0ubuntu3.5|3.0.13-0ubuntu3.6|SECURITY|amd64|1\nlibssl3t64|3.0.13-0ubuntu3.5|3.0.13-0ubuntu3.6|SECURITY|amd64|1\nfirefox|143.0.1|143.0.4|STANDARD|amd64|0\nlibreoffice-core|4:24.2.7-0ubuntu0.24.04.4|4:24.2.7-0ubuntu0.24.04.5|STANDARD|amd64|0\nmesa-vulkan-drivers|25.2.8-0ubuntu0.24.04.2|25.2.8-0ubuntu0.24.04.4|STANDARD|amd64|0\nmesa-vulkan-drivers|25.2.8-0ubuntu0.24.04.2|25.2.8-0ubuntu0.24.04.4|STANDARD|i386|0\ngir1.2-mutter-14|46.2-1ubuntu0.24.04.16|46.2-1ubuntu0.24.04.18|STANDARD|amd64|0\nalsa-ucm-conf|1.2.10-1ubuntu5.14|1.2.10-1ubuntu5.15|STANDARD|all|0\ndnsmasq-base|2.90-2ubuntu0.4|2.91-0ubuntu0.24.04.2|STANDARD|amd64|0\nthermald|2.5.6-2ubuntu1|2.5.6-2ubuntu1.1|STANDARD|amd64|0'
    local i
    for i in $(seq 1 14); do PKG_UPDATE_LIST+=$'\n'"libpkg${i}|1.${i}.0|1.${i}.1|STANDARD|amd64|0"; done
    PKG_UPDATES_TOTAL=26 PKG_UPDATES_FLATPAK=2 PKG_UPDATES_SNAP=2 PKG_UPDATES_SECURITY=2 PKG_UPDATES_CRITICAL=2
    PKG_FLATPAK_LIST=$'app|app/org.videolan.VLC/x86_64/stable|org.videolan.VLC|VLC|3.0.21\nruntime|runtime/org.freedesktop.Platform/x86_64/24.08|org.freedesktop.Platform|Freedesktop Platform|24.08.21'
    PKG_SNAP_LIST=$'firefox|143.0.4|6321|289MB|mozilla**\ncore22|20250923|2082|77MB|canonical**'
    pkgmgr_native_arch() { echo amd64; }
}

# --- One picture: wait, grab the root window, crop to the window, close it ---
shot() {
    local file="$1" wait="${2:-3}"
    sleep "$wait"
    import -display "$VDISPLAY" -window root "$TMP/raw.png"
    convert "$TMP/raw.png" -trim +repage "$file"
    xdotool key --delay 80 Escape 2>/dev/null || true
    sleep 0.6
    echo "wrote: $file"
}

( sample
  body=$(dialog_prompt_html "psst! there's new things to install!" normal "You choose what to install next." "")
  kdialog --title "nudge · updates" --icon nudge --yes-label "Update Now" --no-label "Remind Me Later" --cancel-label "Not Now" --yesnocancel "$body" >/dev/null 2>&1 || true ) &
shot "$OUT/screenshot-prompt.png"

( sample; _dialog_tally
  _dialog_scope_items | _dialog_pick "What should I install?" "$(_dialog_sources_long)" happy >/dev/null 2>&1 || true ) &
shot "$OUT/screenshot-scope.png"

( sample; dialog_show_fulllist >/dev/null 2>&1 || true ) &
shot "$OUT/screenshot-list.png"

( sample; DEFERRAL_OPTIONS="1h,4h,1d,1w" dialog_defer_pick "okie dokie! i come back later~" >/dev/null 2>&1 || true ) &
shot "$OUT/screenshot-defer.png"

# --- The terminal session: the menu, in konsole when there is one ---
sess="$TMP/session"
( sample
  DETECTED_PKGMGR=apt
  printf '# nudge upgrade session (sample)\npkgmgr=apt\narch=amd64\nscope=pick\n[system]\n%s\n[flatpak]\n%s\n[snap]\n%s\n' \
      "$PKG_UPDATE_LIST" "$PKG_FLATPAK_LIST" "$PKG_SNAP_LIST" > "$sess" )
chmod 600 "$sess"
: > "$sess.status"
export XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_CONFIG_HOME/nudge"
printf 'SELF_UPDATE_CHECK=false\n' > "$XDG_CONFIG_HOME/nudge/nudge.conf"
# konsole without its bars; colour on even when the caller's shell turned it off
printf '[KonsoleWindow]\nShowMenuBarByDefault=false\n[MainWindow]\nMenuBar=Disabled\n[MainWindow][Toolbar mainToolBar]\nHidden=true\n[MainWindow][Toolbar sessionToolbar]\nHidden=true\n' > "$XDG_CONFIG_HOME/konsolerc"
if command -v konsole >/dev/null 2>&1; then
    ( env -u NO_COLOR COLORTERM=truecolor konsole --nofork --hide-menubar --hide-tabbar \
        -p TerminalColumns=84 -p TerminalRows=24 -p ScrollBarPosition=2 \
        -e bash nudge.sh --_run-upgrade "$sess" >/dev/null 2>&1 || true ) &
    sleep 5
    import -display "$VDISPLAY" -window root "$TMP/raw.png"
    # konsole keeps its toolbar whatever the config says: it is the top 46 px of the window
    convert "$TMP/raw.png" -trim +repage -gravity North -chop 0x46 +repage -trim +repage "$OUT/screenshot-terminal.png"
    echo "wrote: $OUT/screenshot-terminal.png"
    # the runner is ended here, not answered: no keystroke can ever accept the menu
    pkill -f -- "--_run-upgrade $sess" 2>/dev/null || true
elif command -v xterm >/dev/null 2>&1; then
    ( env -u NO_COLOR COLORTERM=truecolor xterm -geometry 84x26 -fa 'DejaVu Sans Mono' -fs 11 -bg '#1b1e20' -fg '#e3e5e8' \
        -e bash nudge.sh --_run-upgrade "$sess" >/dev/null 2>&1 || true ) &
    sleep 4
    import -display "$VDISPLAY" -window root "$TMP/raw.png"
    convert "$TMP/raw.png" -trim +repage "$OUT/screenshot-terminal.png"
    echo "wrote: $OUT/screenshot-terminal.png"
    pkill -f -- "--_run-upgrade $sess" 2>/dev/null || true
fi
sleep 1
