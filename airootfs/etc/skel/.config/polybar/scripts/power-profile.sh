#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  The power profile, in the bar. Click it to move to the next one.
#
#  Switching by hand means knowing the command and remembering the profile
#  names, which is no way to ask someone to save their battery on the way to a
#  lecture. This shows the current profile and cycles on a click.
#
#  Silent on machines with no power profiles at all, the same way battery.sh is
#  silent on a desktop - polybar simply shows nothing rather than an error.
#
#  The list of profiles is read from the daemon rather than hardcoded: what is
#  offered depends on the hardware. A laptop on the intel_pstate or amd_pstate
#  driver usually has all three, while one falling back to the placeholder
#  driver has only balanced and power-saver, and cycling through a profile that
#  does not exist would fail silently.
# ─────────────────────────────────────────────────────────────────────────────
set -u

command -v powerprofilesctl >/dev/null 2>&1 || exit 0

# Profile lines look like "* balanced:" or "  power-saver:" - a name on its own
# followed by a colon. The indented detail lines underneath ("PlatformDriver:
# placeholder") carry a value after the colon, so anchoring at end of line is
# what separates them.
profiles() {
    powerprofilesctl list 2>/dev/null |
        sed -n 's/^[ *]*\([a-z][a-z-]*\):[[:space:]]*$/\1/p'
}

label_for() {
    case $1 in
        power-saver) printf '󰌪 Economia'    ;;
        balanced)    printf '󰾅 Equilibrado' ;;
        performance) printf '󰓅 Desempenho'  ;;
        *)           printf '󰾆 %s' "$1"     ;;
    esac
}

if [[ ${1:-} == --cycle ]]; then
    current=$(powerprofilesctl get 2>/dev/null) || exit 0
    mapfile -t all < <(profiles)
    (( ${#all[@]} )) || exit 0

    next=${all[0]}
    for i in "${!all[@]}"; do
        if [[ ${all[i]} == "$current" ]]; then
            next=${all[(i + 1) % ${#all[@]}]}
            break
        fi
    done

    powerprofilesctl set "$next" 2>/dev/null || exit 0
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a IFOS -t 2000 "Energia" "$(label_for "$next")"
    fi
    exit 0
fi

current=$(powerprofilesctl get 2>/dev/null) || exit 0
[[ -n $current ]] || exit 0
label_for "$current"
printf '\n'
