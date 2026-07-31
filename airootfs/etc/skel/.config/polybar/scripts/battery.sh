#!/usr/bin/env bash
# Silent on machines without a battery.
set -u

bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1) || exit 0
[ -n "$bat" ] || exit 0

cap=$(cat "$bat/capacity" 2>/dev/null) || exit 0
status=$(cat "$bat/status" 2>/dev/null)

case "$status" in
    Charging) icon="󰂄" ;;
    Full)     icon="󰁹" ;;
    *)
        if   [ "$cap" -ge 90 ]; then icon="󰁹"
        elif [ "$cap" -ge 70 ]; then icon="󰂀"
        elif [ "$cap" -ge 40 ]; then icon="󰁾"
        elif [ "$cap" -ge 15 ]; then icon="󰁻"
        else                         icon="󰁺"
        fi
        ;;
esac

printf '%s %s%%\n' "$icon" "$cap"
