#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  The power profile, in the bar. Click it to move to the next one.
#
#  Event-driven. This used to be polled every thirty seconds, which meant that
#  after clicking to change profile the bar went on showing the old one for up
#  to half a minute - long enough to click again thinking it had not worked.
#  power-profiles-daemon emits PropertiesChanged the moment the profile
#  changes, and that signal carries the new value with it, so the bar updates
#  as fast as the click and nothing is polled at all.
#
#  Reading goes over D-Bus rather than through powerprofilesctl, which is a
#  Python script: starting an interpreter to read one word was the reason
#  polling it was expensive in the first place. Setting still goes through
#  powerprofilesctl, because that happens once per click and it is the
#  supported interface.
#
#  Silent on machines with no power profiles, the same way battery.sh is silent
#  on a desktop.
# ─────────────────────────────────────────────────────────────────────────────
set -u

# The daemon renamed its bus from net.hadess to org.freedesktop.UPower in 0.20
# and still answers to both, but an older one only knows the first and a newer
# one may eventually drop it. Ask for whichever replies.
BUS=""
for candidate in org.freedesktop.UPower.PowerProfiles net.hadess.PowerProfiles; do
    if busctl --system status "$candidate" >/dev/null 2>&1; then
        BUS=$candidate
        break
    fi
done
PATHNAME="/${BUS//.//}"

label_for() {
    case $1 in
        power-saver) printf '%%{F#7ed957}󰌪%%{F#7fa392} Economia'    ;;
        balanced)    printf '%%{F#7ed957}󰾅%%{F#7fa392} Equilibrado' ;;
        performance) printf '%%{F#7ed957}󰓅%%{F#7fa392} Desempenho'  ;;
        *)           printf '%%{F#7ed957}󰾆%%{F#7fa392} %s' "$1"     ;;
    esac
}

current_profile() {
    [[ -n $BUS ]] || return 1
    busctl --system get-property "$BUS" "$PATHNAME" "$BUS" ActiveProfile 2>/dev/null |
        sed -n 's/^s "\(.*\)"$/\1/p'
}

# ── Click: move to the next profile ──────────────────────────────────────────
if [[ ${1:-} == --cycle ]]; then
    command -v powerprofilesctl >/dev/null 2>&1 || exit 0
    current=$(powerprofilesctl get 2>/dev/null) || exit 0

    # Read the list from the daemon rather than hardcoding three: what a machine
    # offers depends on its hardware, and a laptop on the placeholder driver has
    # only balanced and power-saver.
    mapfile -t all < <(powerprofilesctl list 2>/dev/null |
        sed -n 's/^[ *]*\([a-z][a-z-]*\):[[:space:]]*$/\1/p')
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

# ── Display: print now, then on every change ─────────────────────────────────
[[ -n $BUS ]] || exit 0

last=""
emit() {
    [[ -n ${1:-} ]] || return 0
    [[ $1 == "$last" ]] && return 0     # the daemon owns two bus names and
    last=$1                             # signals each, so changes arrive twice
    label_for "$1"
    printf '\n'
}

emit "$(current_profile)"

# Without gdbus there is nothing to listen with; print the one value and let
# polybar's interval take over.
command -v gdbus >/dev/null 2>&1 || exit 0

gdbus monitor --system --dest "$BUS" 2>/dev/null |
while IFS= read -r line; do
    [[ $line == *ActiveProfile* ]] || continue
    emit "$(sed -n "s/.*'ActiveProfile': <'\([a-z-]*\)'>.*/\1/p" <<<"$line")"
done
