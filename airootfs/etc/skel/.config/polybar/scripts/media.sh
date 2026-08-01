#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  What is playing, in the bar.
#
#      media.sh              print the current track (nothing if none)
#      media.sh toggle       play / pause
#      media.sh next|prev    skip
#
#  Silent whenever nothing is playing, so the bar does not carry a dead "no
#  music" label around all day - the module simply is not there until it has
#  something to say.
# ─────────────────────────────────────────────────────────────────────────────
set -u

MAX=38            # characters before the title is cut short

command -v playerctl >/dev/null 2>&1 || exit 0

case ${1:-show} in
    toggle) playerctl play-pause 2>/dev/null; exit 0 ;;
    next)   playerctl next       2>/dev/null; exit 0 ;;
    prev)   playerctl previous   2>/dev/null; exit 0 ;;
esac

status=$(playerctl status 2>/dev/null) || exit 0

case $status in
    Playing) icon="󰐊" ;;
    Paused)  icon="󰏤" ;;
    *)       exit 0  ;;   # Stopped, or no player at all
esac

# Artist is often missing on a video or a stream, so fall back to the title on
# its own rather than printing a stray dash.
text=$(playerctl metadata --format '{{artist}} — {{title}}' 2>/dev/null)
[[ -z ${text//[[:space:]—]/} ]] && text=$(playerctl metadata --format '{{title}}' 2>/dev/null)
text=${text# — }

# Some players report an empty title while they are still loading.
[[ -n ${text//[[:space:]]/} ]] || exit 0

# Trim on a character count, not a byte count: accented titles are common here
# and cutting mid-character would leave a broken glyph in the bar.
if (( ${#text} > MAX )); then
    text="${text:0:MAX-1}…"
fi

printf '%s %s\n' "$icon" "$text"
