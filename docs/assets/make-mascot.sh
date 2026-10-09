#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jay Taylor (https://github.com/otmof-ops/nudge)
# SPDX-License-Identifier: BSD-3-Clause
# nudge — docs/assets/make-mascot.sh
# Draws the Nudge Bunny as SVG: one character, seven moods, two poses, the app
# icon, the mood sheet and the social preview. Every asset comes from the same
# shapes, so the bunny looks the same everywhere. Run from the repository root:
#
#   docs/assets/make-mascot.sh            # writes docs/assets/*.svg and share/icons/nudge.svg

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
OUT="docs/assets"
ICON_OUT="share/icons"

# --- Palette ---
FUR="#F6F3EC"
LINE="#C9C1B3"
INNER="#F9C3CE"
CHEEK="#F8C9D2"
NOSE="#E78CA0"
MOUTH="#B96F80"
INK="#2B2B2B"
TEAR="#8CC4F0"
GREEN="#2EA44F"
GREEN_DARK="#1F7A3A"
PAPER="#FBFAF7"

# --- Ears: two tall rounded rectangles, tilted outward, pink inside ---
ears() {
    cat <<SVG
  <g id="ears" stroke="$LINE" stroke-width="3">
    <g transform="translate(96 118) rotate(-14)">
      <rect x="-19" y="-118" width="38" height="124" rx="19" fill="$FUR"/>
      <rect x="-10" y="-102" width="20" height="92" rx="10" fill="$INNER" stroke="none"/>
    </g>
    <g transform="translate(144 118) rotate(14)">
      <rect x="-19" y="-118" width="38" height="124" rx="19" fill="$FUR"/>
      <rect x="-10" y="-102" width="20" height="92" rx="10" fill="$INNER" stroke="none"/>
    </g>
  </g>
SVG
}

# --- Head with cheeks, nose, whiskers (the face is drawn separately) ---
head() {
    cat <<SVG
  <g id="head">
    <circle cx="120" cy="152" r="64" fill="$FUR" stroke="$LINE" stroke-width="3"/>
    <ellipse cx="82" cy="170" rx="12" ry="7.5" fill="$CHEEK"/>
    <ellipse cx="158" cy="170" rx="12" ry="7.5" fill="$CHEEK"/>
    <g stroke="$LINE" stroke-width="2.2" stroke-linecap="round" fill="none">
      <path d="M68 158 H46 M68 165 L46 170 M68 151 L46 146"/>
      <path d="M172 158 H194 M172 165 L194 170 M172 151 L194 146"/>
    </g>
    <path d="M113 161 H127 L120 169 Z" fill="$NOSE"/>
  </g>
SVG
}

# --- Faces: eyes and mouth for each mood ---
face() {
    local mood="$1"
    case "$mood" in
        normal)
            cat <<SVG
  <g id="face-normal">
    <circle cx="98" cy="144" r="7" fill="$INK"/><circle cx="100.5" cy="141.5" r="2.4" fill="#fff"/>
    <circle cx="142" cy="144" r="7" fill="$INK"/><circle cx="144.5" cy="141.5" r="2.4" fill="#fff"/>
    <path d="M120 169 q-4 7 -10 4 M120 169 q4 7 10 4" stroke="$MOUTH" stroke-width="2.6" fill="none" stroke-linecap="round"/>
  </g>
SVG
            ;;
        happy)
            cat <<SVG
  <g id="face-happy">
    <path d="M88 146 q10 -12 20 0 M132 146 q10 -12 20 0" stroke="$INK" stroke-width="4.2" fill="none" stroke-linecap="round"/>
    <path d="M108 170 q12 12 24 0" stroke="$MOUTH" stroke-width="2.8" fill="none" stroke-linecap="round"/>
  </g>
SVG
            ;;
        worried)
            cat <<SVG
  <g id="face-worried">
    <circle cx="98" cy="146" r="8" fill="$INK"/><circle cx="101" cy="143" r="2.6" fill="#fff"/>
    <circle cx="142" cy="146" r="8" fill="$INK"/><circle cx="145" cy="143" r="2.6" fill="#fff"/>
    <path d="M86 128 L108 134 M154 128 L132 134" stroke="$INK" stroke-width="3.2" stroke-linecap="round"/>
    <path d="M112 174 q8 -6 16 0" stroke="$MOUTH" stroke-width="2.6" fill="none" stroke-linecap="round"/>
  </g>
SVG
            ;;
        wide)
            cat <<SVG
  <g id="face-wide">
    <circle cx="98" cy="144" r="9.5" fill="$INK"/><circle cx="101.5" cy="140.5" r="3.2" fill="#fff"/>
    <circle cx="142" cy="144" r="9.5" fill="$INK"/><circle cx="145.5" cy="140.5" r="3.2" fill="#fff"/>
    <ellipse cx="120" cy="174" rx="5" ry="6" fill="$MOUTH"/>
  </g>
SVG
            ;;
        sleepy)
            cat <<SVG
  <g id="face-sleepy">
    <path d="M89 146 h18 M133 146 h18" stroke="$INK" stroke-width="4" stroke-linecap="round"/>
    <path d="M120 169 q-4 7 -10 4 M120 169 q4 7 10 4" stroke="$MOUTH" stroke-width="2.6" fill="none" stroke-linecap="round"/>
    <g fill="$INK" font-family="ui-sans-serif, system-ui, sans-serif" font-weight="700">
      <text x="176" y="98" font-size="18">z</text><text x="190" y="80" font-size="24">z</text><text x="208" y="58" font-size="30">z</text>
    </g>
  </g>
SVG
            ;;
        teary)
            cat <<SVG
  <g id="face-teary">
    <circle cx="98" cy="144" r="7" fill="$INK"/><circle cx="100.5" cy="141.5" r="2.4" fill="#fff"/>
    <circle cx="142" cy="144" r="7" fill="$INK"/><circle cx="144.5" cy="141.5" r="2.4" fill="#fff"/>
    <path d="M86 130 L106 136 M154 130 L134 136" stroke="$INK" stroke-width="3" stroke-linecap="round"/>
    <path d="M92 156 q-5 11 0 14 q5 -3 0 -14z" fill="$TEAR"/>
    <path d="M112 176 q8 -5 16 0" stroke="$MOUTH" stroke-width="2.6" fill="none" stroke-linecap="round"/>
  </g>
SVG
            ;;
        crying)
            cat <<SVG
  <g id="face-crying">
    <path d="M88 142 q10 10 20 0 M132 142 q10 10 20 0" stroke="$INK" stroke-width="4.2" fill="none" stroke-linecap="round"/>
    <path d="M90 154 q-6 14 0 18 q6 -4 0 -18z M150 154 q-6 14 0 18 q6 -4 0 -18z" fill="$TEAR"/>
    <path d="M108 180 q12 -10 24 0" stroke="$MOUTH" stroke-width="2.8" fill="none" stroke-linecap="round"/>
  </g>
SVG
            ;;
        *) echo "unknown mood: $mood" >&2; return 1 ;;
    esac
}

# --- Body, paws, tail; the badge is the little green "fresh" arrow ---
body() {
    local pose="$1"
    cat <<SVG
  <g id="body">
    <circle cx="66" cy="246" r="10" fill="$FUR" stroke="$LINE" stroke-width="3"/>
    <ellipse cx="120" cy="240" rx="50" ry="36" fill="$FUR" stroke="$LINE" stroke-width="3"/>
    <ellipse cx="98" cy="270" rx="17" ry="8" fill="$FUR" stroke="$LINE" stroke-width="3"/>
    <ellipse cx="142" cy="270" rx="17" ry="8" fill="$FUR" stroke="$LINE" stroke-width="3"/>
    <path d="M90 268 v5 M98 269 v5 M106 268 v5 M134 268 v5 M142 269 v5 M150 268 v5" stroke="$LINE" stroke-width="2" stroke-linecap="round"/>
SVG
    case "$pose" in
        wave)
            cat <<SVG
    <circle cx="92" cy="238" r="11" fill="$FUR" stroke="$LINE" stroke-width="3"/>
    <!-- the raised arm: an outlined tube from the shoulder to a paw beside the ear -->
    <path d="M158 226 q22 -26 24 -58" stroke="$LINE" stroke-width="15" fill="none" stroke-linecap="round"/>
    <path d="M158 226 q22 -26 24 -58" stroke="$FUR" stroke-width="9" fill="none" stroke-linecap="round"/>
    <circle cx="183" cy="166" r="12" fill="$FUR" stroke="$LINE" stroke-width="3"/>
    <path d="M176 160 l-4 -7 M183 157 l0 -8 M190 160 l4 -7" stroke="$LINE" stroke-width="2.2" stroke-linecap="round"/>
SVG
            ;;
        *)
            cat <<SVG
    <circle cx="92" cy="238" r="11" fill="$FUR" stroke="$LINE" stroke-width="3"/>
    <circle cx="148" cy="238" r="11" fill="$FUR" stroke="$LINE" stroke-width="3"/>
    <g transform="translate(164 232)">
      <circle r="17" fill="$GREEN"/>
      <path d="M-7 2 a8 8 0 1 1 3.5 6.5" stroke="#fff" stroke-width="3.2" fill="none" stroke-linecap="round"/>
      <path d="M-5 9.5 l5.5 1.2 l-1 -5.6 z" fill="#fff"/>
    </g>
SVG
            ;;
    esac
    echo "  </g>"
}

# --- A whole character ---
# Usage: character <file> <mood> <pose>
character() {
    local file="$1" mood="$2" pose="$3"
    {
        cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 290" width="240" height="290" role="img" aria-label="the Nudge Bunny, $mood">
  <title>the Nudge Bunny ($mood)</title>
SVG
        body "$pose"
        ears
        head
        face "$mood"
        echo "</svg>"
    } > "$file"
}

# --- The app icon: head and ears on a green tile ---
icon() {
    local file="$1"
    {
        cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128" role="img" aria-label="nudge">
  <title>nudge</title>
  <rect width="128" height="128" rx="30" fill="$GREEN"/>
  <g transform="translate(64 86) scale(0.52) translate(-120 -152)">
SVG
        ears
        head
        face normal
        cat <<SVG
  </g>
</svg>
SVG
    } > "$file"
}

# --- The mood sheet: every mood in a row, labelled ---
sheet() {
    local file="$1"
    local moods=(normal happy wide worried sleepy teary crying)
    local n=${#moods[@]} i x
    {
        cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $((n * 200)) 330" width="$((n * 200))" height="330" role="img" aria-label="the Nudge Bunny's moods">
  <title>the Nudge Bunny's moods</title>
  <rect width="100%" height="100%" fill="$PAPER" rx="18"/>
SVG
        for i in "${!moods[@]}"; do
            x=$((i * 200 - 20))
            echo "  <g transform=\"translate($x 10)\">"
            body sit
            ears
            head
            face "${moods[$i]}"
            echo "  </g>"
            echo "  <text x=\"$((i * 200 + 100))\" y=\"318\" text-anchor=\"middle\" font-family=\"ui-sans-serif, system-ui, sans-serif\" font-size=\"18\" fill=\"$INK\">${moods[$i]}</text>"
        done
        echo "</svg>"
    } > "$file"
}

# --- The social preview (1280x640) ---
social() {
    local file="$1"
    {
        cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 640" width="1280" height="640" role="img" aria-label="nudge: a gentle nudge to keep your system fresh">
  <title>nudge</title>
  <rect width="1280" height="640" fill="$PAPER"/>
  <rect x="0" y="600" width="1280" height="40" fill="$GREEN"/>
  <g transform="translate(96 54) scale(1.7)">
SVG
        body sit
        ears
        head
        face happy
        cat <<SVG
  </g>
  <g font-family="ui-sans-serif, system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif" fill="$INK">
    <text x="540" y="258" font-size="124" font-weight="800" letter-spacing="-4">nudge</text>
    <text x="544" y="318" font-size="32" fill="$GREEN_DARK">a gentle nudge to keep your system fresh</text>
    <text x="544" y="382" font-size="24" fill="#55524C">Consent-first update manager for Linux desktops.</text>
    <text x="544" y="420" font-size="24" fill="#55524C">You pick what to update: system packages, Flatpak, Snap.</text>
    <text x="544" y="486" font-size="20" fill="#7A766E">apt · dnf · pacman · zypper · Flatpak · Snap · pure bash · BSD 3-Clause</text>
  </g>
</svg>
SVG
    } > "$file"
}

character "$OUT/bunny.svg" normal sit
character "$OUT/bunny-happy.svg" happy sit
character "$OUT/bunny-wide.svg" wide sit
character "$OUT/bunny-worried.svg" worried sit
character "$OUT/bunny-sleepy.svg" sleepy sit
character "$OUT/bunny-teary.svg" teary sit
character "$OUT/bunny-crying.svg" crying sit
character "$OUT/bunny-wave.svg" happy wave
icon "$ICON_OUT/nudge.svg"
sheet "$OUT/bunny-moods.svg"
social "$OUT/social-preview.svg"
echo "wrote: $OUT/bunny*.svg $ICON_OUT/nudge.svg $OUT/social-preview.svg"
