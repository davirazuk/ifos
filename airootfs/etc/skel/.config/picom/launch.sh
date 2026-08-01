#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
#  Start picom with a backend the machine can actually use.
#
#  picom's glx backend needs a working GPU render node. Without one - a VM with
#  plain VGA, or a machine with no graphics driver - picom still starts, still
#  redirects every window offscreen, and then fails to paint them. The result is
#  a desktop where the wallpaper and the bar are visible and *every window is
#  invisible*: terminals, the launcher, everything. It looks exactly like the
#  applications are crashing when they are running perfectly well.
#
#  So: hardware GL when the render node is there, xrender otherwise. xrender is
#  software, slower, and works everywhere.
# ─────────────────────────────────────────────────────────────────────────────

#  The same test decides whether the desktop animates. Animations are drawn per
#  frame, so on the xrender path - where that work lands on the CPU - they cost
#  exactly the machines that can least afford it. Those get the still config.

CFG="${XDG_CONFIG_HOME:-$HOME/.config}/picom"

if [ -e /dev/dri/renderD128 ]; then
    if [ -f "$CFG/picom-animated.conf" ]; then
        exec picom -b --config "$CFG/picom-animated.conf"
    fi
    exec picom -b
else
    exec picom -b --backend xrender
fi
