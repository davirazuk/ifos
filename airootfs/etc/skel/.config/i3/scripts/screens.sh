#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Re-detect the screens (Mod+P).
#
#  autorandr's udev rule handles a projector being plugged in on its own. This
#  is the manual one, for when it does not fire - a dock that presents the
#  output late, a cable swapped mid-class, or a machine where the rule never
#  installed - and it is bound to a key because "nothing happened when I
#  plugged it in" needs an answer someone can be told over the phone.
#
#  There is a plain xrandr fallback so that the key does something useful even
#  if autorandr is missing.
#
#  The bar is restarted afterwards either way: it draws one instance per
#  output, so a screen that appears while it is running has no bar until it is.
# ─────────────────────────────────────────────────────────────────────────────
set -u

notify() {
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -a IFOS -t 3000 "Telas" "$1"
}

if command -v autorandr >/dev/null 2>&1; then
    # --skip-options gamma: gammastep owns the colour temperature, and letting
    # autorandr restore a saved gamma undoes the night warmth every time a
    # screen changes.
    autorandr --change --default horizontal --skip-options gamma >/dev/null 2>&1
else
    # No autorandr: enable every connected output, left to right, in the order
    # xrandr lists them, with the first one primary.
    mapfile -t connected < <(
        xrandr --query 2>/dev/null | sed -n 's/^\([^ ]*\) connected.*/\1/p'
    )
    (( ${#connected[@]} )) || { notify "Nenhuma tela detectada."; exit 0; }

    args=(--output "${connected[0]}" --auto --primary)
    previous=${connected[0]}
    for out in "${connected[@]:1}"; do
        args+=(--output "$out" --auto --right-of "$previous")
        previous=$out
    done
    # Anything connected earlier and now gone must be switched off, or its
    # workspaces stay on a screen that is not there.
    mapfile -t known < <(xrandr --query 2>/dev/null | sed -n 's/^\([^ ]*\) \(dis\)\?connected.*/\1/p')
    for out in "${known[@]}"; do
        found=0
        for live in "${connected[@]}"; do [[ $out == "$live" ]] && found=1; done
        (( found )) || args+=(--output "$out" --off)
    done
    xrandr "${args[@]}" 2>/dev/null
fi

count=$(xrandr --query 2>/dev/null | grep -c ' connected')
notify "$count tela(s) em uso."

# One bar per output, so the bars have to be restarted once the outputs settle.
[[ -x $HOME/.config/polybar/launch.sh ]] && "$HOME/.config/polybar/launch.sh"
