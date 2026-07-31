#!/usr/bin/env bash
# IFOS power menu — replaces i3's unconfirmed "$mod+Shift+e kills your session".
set -u

lock="  Lock"
logout="  Log out"
suspend="  Suspend"
reboot="  Restart"
shutdown="  Shut down"

chosen=$(printf '%s\n' "$lock" "$logout" "$suspend" "$reboot" "$shutdown" |
    rofi -dmenu -i -p "power" -theme-str 'listview { lines: 5; } window { width: 300px; }')

case "$chosen" in
    "$lock")     i3lock -c 1e1e2e -e -f ;;
    "$logout")   i3-msg exit ;;
    "$suspend")  systemctl suspend ;;
    "$reboot")   systemctl reboot ;;
    "$shutdown") systemctl poweroff ;;
esac
