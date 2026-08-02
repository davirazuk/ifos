#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Start the bar - one per connected screen.
#
#  This used to run a single `polybar main` with no monitor set, which means
#  polybar picks whatever it considers primary and draws there. Plug a
#  projector into a laptop, which is most of what a second screen is for here,
#  and the second screen got no bar at all: no clock, no workspaces, no way
#  back to the launcher. `pin-workspaces` in the config only means anything
#  once there is a bar per output for it to divide the workspaces between.
#
#  The log went to a fixed /tmp/polybar.log. On a machine with more than one
#  account that is the first user's file and everybody else's tee fails, and it
#  grew without bound because the mode was append. It goes to the per-user
#  runtime directory now, truncated at each start.
# ─────────────────────────────────────────────────────────────────────────────
set -u

killall -q polybar
while pgrep -u "$UID" -x polybar >/dev/null; do sleep 0.5; done

LOG="${XDG_RUNTIME_DIR:-/tmp}/polybar-$UID.log"
: >"$LOG"

# polybar -m lists connected outputs as "NAME: WxH+X+Y", one per line. If it
# tells us nothing - no RandR, or a display polybar cannot read - fall back to
# the single bar this always started, which is still better than none.
mapfile -t outputs < <(polybar -m 2>/dev/null | sed -n 's/^\([^:]*\):.*/\1/p')

if (( ${#outputs[@]} )); then
    for m in "${outputs[@]}"; do
        MONITOR="$m" polybar main >>"$LOG" 2>&1 &
        disown
    done
else
    polybar main >>"$LOG" 2>&1 &
    disown
fi
