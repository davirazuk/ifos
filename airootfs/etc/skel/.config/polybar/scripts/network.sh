#!/usr/bin/env bash
# Report the active connection, preferring wireless when both are up.
set -u

for dev in /sys/class/net/*; do
    iface=${dev##*/}
    [ "$iface" = lo ] && continue
    [ "$(cat "$dev/operstate" 2>/dev/null)" = up ] || continue

    if [ -d "$dev/wireless" ]; then
        ssid=$(iw dev "$iface" link 2>/dev/null | sed -n 's/^\s*SSID: //p')
        printf '󰖩 %s\n' "${ssid:-$iface}"
        exit 0
    fi
    wired=$iface
done

if [ -n "${wired:-}" ]; then
    printf '󰈀 %s\n' "$wired"
else
    printf '󰖪 offline\n'
fi
