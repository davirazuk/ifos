#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  On-screen display for the hardware keys.
#
#  The volume and brightness keys used to work silently - you pressed them and
#  nothing on screen acknowledged it. This adjusts the value and then replaces
#  a single stacked notification with a progress bar, the way a desktop
#  environment does.
# ─────────────────────────────────────────────────────────────────────────────
set -u

notify() {   # notify <tag> <icon> <label> [value]
    local tag=$1 icon=$2 label=$3 value=${4:-}
    local -a args=(
        --app-name=IFOS
        --urgency=low
        --hint="string:x-dunst-stack-tag:$tag"
        --expire-time=2500
    )
    [[ -n $value ]] && args+=(--hint="int:value:$value")
    notify-send "${args[@]}" "$icon  $label"
}

volume_icon() {
    local v=$1 muted=$2
    if [[ $muted == true ]]; then printf ''
    elif   (( v == 0 )); then printf ''
    elif   (( v < 34 )); then printf ''
    elif   (( v < 67 )); then printf ''
    else                      printf ''
    fi
}

case ${1:-} in
    vol-up)    pamixer --allow-boost -i 5 ;;
    vol-down)  pamixer --allow-boost -d 5 ;;
    vol-mute)  pamixer -t ;;
    mic-mute)  pamixer --default-source -t ;;
    bright-up)   brightnessctl -q set 5%+ ;;
    bright-down) brightnessctl -q set 5%- ;;
    *) echo "usage: osd.sh {vol-up|vol-down|vol-mute|mic-mute|bright-up|bright-down}" >&2
       exit 1 ;;
esac

case ${1} in
    vol-*|mic-mute)
        if [[ $1 == mic-mute ]]; then
            muted=$(pamixer --default-source --get-mute 2>/dev/null || echo false)
            if [[ $muted == true ]]; then
                notify ifos-osd-mic "" "Microfone mudo"
            else
                notify ifos-osd-mic "" "Microfone ligado"
            fi
            exit 0
        fi
        vol=$(pamixer --get-volume 2>/dev/null || echo 0)
        muted=$(pamixer --get-mute 2>/dev/null || echo false)
        if [[ $muted == true ]]; then
            notify ifos-osd-vol "$(volume_icon "$vol" true)" "Som mudo" 0
        else
            notify ifos-osd-vol "$(volume_icon "$vol" false)" "Volume  ${vol}%" "$vol"
        fi
        ;;
    bright-*)
        # brightnessctl reports raw values; turn them into a percentage.
        cur=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')
        [[ -z $cur ]] && cur=0
        notify ifos-osd-bright "" "Brilho  ${cur}%" "$cur"
        ;;
esac
