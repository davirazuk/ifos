#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Lock the screen against the IFOS wallpaper rather than a flat colour.
#
#  i3lock does not scale images, so a 1920x1080 wallpaper on any other screen
#  would sit in a corner. The wallpaper is rendered to the current resolution
#  once and cached; the flat colour is the fallback when that is not possible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

BG=/usr/share/backgrounds/ifos.png
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ifos"
COLOR=10241d

geometry=$(xrandr --current 2>/dev/null | awk '/\*/ {print $1; exit}')
[[ -z $geometry ]] && exec i3lock -c "$COLOR" -e -f

# Pre-rendered at build time for the common resolutions - no image tooling
# needed on the machine.
PRERENDERED="/usr/share/ifos/lock/ifos-$geometry.png"
[[ -f $PRERENDERED ]] && exec i3lock -i "$PRERENDERED" -e -f

CACHE="$CACHE_DIR/lock-$geometry.png"

if [[ ! -f $CACHE && -f $BG ]]; then
    mkdir -p "$CACHE_DIR"
    if command -v magick >/dev/null; then
        magick "$BG" -resize "${geometry}^" -gravity center -extent "$geometry" \
               -fill black -colorize 35% "$CACHE" 2>/dev/null
    elif command -v convert >/dev/null; then
        convert "$BG" -resize "${geometry}^" -gravity center -extent "$geometry" \
                -fill black -colorize 35% "$CACHE" 2>/dev/null
    elif command -v ffmpeg >/dev/null; then
        ffmpeg -loglevel quiet -y -i "$BG" \
               -vf "scale=${geometry/x/:}:force_original_aspect_ratio=increase,crop=${geometry/x/:},eq=brightness=-0.25" \
               "$CACHE" 2>/dev/null
    fi
fi

if [[ -f $CACHE ]]; then
    exec i3lock -i "$CACHE" -e -f
fi
exec i3lock -c "$COLOR" -e -f
