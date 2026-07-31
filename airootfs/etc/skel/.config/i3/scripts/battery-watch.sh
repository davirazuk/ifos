#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Warn once when the battery gets low, and again when it gets critical.
#
#  polybar shows the level, but nothing told you about it while you were looking
#  at something else. Exits immediately on machines with no battery.
# ─────────────────────────────────────────────────────────────────────────────
set -u

BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
[[ -n $BAT ]] || exit 0

warned_low=0
warned_critical=0

while :; do
    capacity=$(cat "$BAT/capacity" 2>/dev/null) || exit 0
    status=$(cat "$BAT/status" 2>/dev/null)

    if [[ $status == Discharging ]]; then
        if (( capacity <= 10 )) && (( ! warned_critical )); then
            notify-send --app-name=IFOS --urgency=critical \
                --hint=string:x-dunst-stack-tag:ifos-battery \
                "󰁺  Bateria crítica — ${capacity}%" \
                "Conecte o carregador agora."
            warned_critical=1
        elif (( capacity <= 20 )) && (( ! warned_low )); then
            notify-send --app-name=IFOS --urgency=normal \
                --hint=string:x-dunst-stack-tag:ifos-battery \
                "󰁻  Bateria baixa — ${capacity}%" \
                "Convém conectar o carregador."
            warned_low=1
        fi
    else
        # Charging again: re-arm both warnings.
        warned_low=0
        warned_critical=0
    fi

    sleep 60
done
