#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Avisa quando a bateria fica baixa, quando fica crítica, e — o caso que
#  ninguém espera — quando ela está CAINDO com o carregador conectado.
#
#  A polybar mostra o nível, mas nada avisava enquanto você olhava para outra
#  coisa. Sai na hora em máquina sem bateria.
#
#  POR QUE O TERCEIRO AVISO EXISTE. Este script só olhava para
#  `status == Discharging`. Aconteceu numa máquina de verdade: a bateria caiu
#  de 100% para 3% ao longo de uma madrugada INTEIRA com o carregador na
#  tomada, e o `status` dizia "Charging" o tempo todo — carregando a 1,8W,
#  menos do que a máquina gastava. Nesse estado o script não avisava nada em
#  nenhum momento, nem a 3%, porque o ramo do `else` tratava "não está
#  descarregando" como "está tudo bem" e ainda REARMAVA os dois avisos a cada
#  volta. A máquina desligou sozinha no meio de um trabalho longo.
#
#  O sinal certo não é o `status`, que depende de o firmware dizer a verdade:
#  é o nível cair ao longo do tempo. Se está caindo e o carregador está
#  conectado, isso é defeito e merece nome próprio — carregador fraco, cabo
#  ruim, bateria no fim ou o controlador embarcado travado.
# ─────────────────────────────────────────────────────────────────────────────
set -u

# Injetáveis pelo teste: uma /sys de mentira, um intervalo curto e um número
# de voltas, para o teste não precisar esperar horas nem ter bateria.
PS_ROOT=${IFOS_BATTERY_PS_ROOT:-/sys/class/power_supply}
INTERVAL=${IFOS_BATTERY_INTERVAL:-60}
MAX_TICKS=${IFOS_BATTERY_MAX_TICKS:-0}       # 0 = para sempre

# Quanto o nível precisa cair, e por quanto tempo, antes de acusar defeito de
# carregamento. Uma bateria cheia oscila 1% para lá e para cá enquanto o
# firmware calibra; gritar nisso seria pior que não avisar.
DROP_PCT=${IFOS_BATTERY_DROP_PCT:-5}
DROP_SECS=${IFOS_BATTERY_DROP_SECS:-900}

BAT=$(ls -d "$PS_ROOT"/BAT* 2>/dev/null | head -1)
[[ -n $BAT ]] || exit 0

warned_low=0
warned_critical=0
warned_fault=0
ref_cap=""      # nível de referência para medir queda
ref_time=0
ticks=0

now_s() { printf '%s' "${EPOCHSECONDS:-$(date +%s)}"; }

on_ac() {
    local f
    for f in "$PS_ROOT"/A{C,DP}*/online "$PS_ROOT"/*/online; do
        [[ -r $f ]] || continue
        [[ $(<"$f") == 1 ]] && return 0
    done
    return 1
}

notify() {   # notify <urgência> <título> <corpo>
    notify-send --app-name=IFOS --urgency="$1" \
        --hint=string:x-dunst-stack-tag:ifos-battery "$2" "$3" 2>/dev/null
}

while :; do
    capacity=$(cat "$BAT/capacity" 2>/dev/null) || exit 0
    # `status` não é lido de propósito. Era a única entrada deste script e foi
    # exatamente ela que mentiu: "Charging" durante uma queda de 100% para 3%.
    # O nível ao longo do tempo é medido, o status é declarado — e só um dos
    # dois é verificável daqui.

    # Um capacity ilegível ou vazio viraria 0 dentro de (( )) e dispararia um
    # aviso crítico de "0%" numa bateria perfeitamente saudável.
    if [[ ! $capacity =~ ^[0-9]+$ ]]; then
        sleep "$INTERVAL"
        (( MAX_TICKS )) && { (( ++ticks >= MAX_TICKS )) && break; }
        continue
    fi

    t=$(now_s)
    [[ -n $ref_cap ]] || { ref_cap=$capacity; ref_time=$t; }

    # Subiu de verdade: a máquina está ganhando carga. Rearma tudo e move a
    # referência. É o ÚNICO sinal que prova que o carregamento funciona —
    # `status` não prova, foi exatamente ele que mentiu.
    if (( capacity > ref_cap )); then
        ref_cap=$capacity; ref_time=$t
        warned_low=0; warned_critical=0; warned_fault=0
    elif (( capacity < ref_cap )); then
        # Caindo. Se está na tomada, isto é defeito, e o aviso diz isso em
        # vez de mandar conectar um carregador que já está conectado.
        if on_ac && (( ! warned_fault )) \
           && (( ref_cap - capacity >= DROP_PCT )) \
           && (( t - ref_time >= DROP_SECS )); then
            notify critical "󰚥  A bateria está caindo na tomada — ${capacity}%" \
                "Caiu ${DROP_PCT}% ou mais com o carregador conectado. Confira o carregador, o cabo e o encaixe; se estiver fazendo trabalho longo, salve agora."
            warned_fault=1
        fi
    fi

    # Os avisos de nível NÃO dependem mais do status dizer "Discharging". O
    # que importa é estar baixo e não estar subindo — foi por depender do
    # status que a máquina chegou a 3% em silêncio.
    if (( capacity <= ref_cap )); then
        if (( capacity <= 10 )) && (( ! warned_critical )); then
            if on_ac; then
                notify critical "󰁺  Bateria crítica — ${capacity}%" \
                    "Está na tomada e mesmo assim caiu até aqui. Salve o que estiver aberto."
            else
                notify critical "󰁺  Bateria crítica — ${capacity}%" "Conecte o carregador agora."
            fi
            warned_critical=1
            # Cruzar o crítico significa que o baixo também foi cruzado, tenha
            # aquele aviso saído ou não. Sem isto, uma bateria que passa pelos
            # dois limites dentro da mesma volta — ou uma sessão que começa já
            # crítica — mostrava "crítica" e, um minuto depois, o mais suave
            # "baixa" no mesmo percentual, que lê como se tivesse melhorado.
            warned_low=1
        elif (( capacity <= 20 )) && (( ! warned_low )); then
            notify normal "󰁻  Bateria baixa — ${capacity}%" \
                "Convém conectar o carregador."
            warned_low=1
        fi
    fi

    sleep "$INTERVAL"
    if (( MAX_TICKS )); then
        (( ++ticks >= MAX_TICKS )) && break
    fi
done
