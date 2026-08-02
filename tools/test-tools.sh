#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  test-tools.sh — run the ifos-* shell tools against machines that do not exist
#
#  These tools exist to diagnose hardware that is broken or absent in specific
#  ways: an NVIDIA module built for the kernel that is not running, nouveau
#  holding the card the proprietary driver wanted, multilib switched off so
#  Steam's 32-bit libraries cannot even be installed, a DualSense the machine
#  running this has never seen. None of that can be reproduced here, and every
#  one of them is a student in front of a computer that will not open Steam or
#  will not read their controller.
#
#  So each case below builds a fake machine - an lspci that lists chosen cards,
#  a pacman that knows a chosen package list, a /proc/modules with chosen
#  modules in it, a /proc/bus/input/devices describing a chosen controller -
#  and checks that the tool says the right thing about it.
#
#  Covers ifos-gpu, ifos-term and ifos-controller.
#
#      ./tools/test-tools.sh
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GPU="$PROFILE/airootfs/usr/local/bin/ifos-gpu"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

c_reset=$'\033[0m'; c_grn=$'\033[1;32m'; c_red=$'\033[1;31m'; c_dim=$'\033[2m'
PASS=0; FAIL=0

# ── Building a machine ───────────────────────────────────────────────────────
#  M is the machine under construction. Each setter writes one fact about it.

new_machine() {   # new_machine <name> <kernel-release>
    M="$TMP/$1"
    KREL=$2
    rm -rf "$M"
    mkdir -p "$M"/{bin,data,proc,dev/dri,sys/module/nvidia_drm/parameters,etc}
    mkdir -p "$M/usr/lib/modules/$KREL"
    : > "$M/data/pkgs"
    : > "$M/data/lspci"
    : > "$M/proc/modules"
    : > "$M/data/modinfo"
    echo "$KREL" > "$M/data/krel"
    echo "BOOT_IMAGE=/vmlinuz-linux root=/dev/sda2 rw" > "$M/proc/cmdline"
    printf 'core\nextra\n' > "$M/data/repos"

    # A machine with a working driver has a render node; cases that need it
    # gone delete it again.
    : > "$M/dev/dri/renderD128"

    cat > "$M/bin/lspci"  <<'EOF'
#!/bin/sh
cat "$IFOS_GPU_SYSROOT/data/lspci"
EOF
    # Only the three forms ifos-gpu actually uses. Anything else is a bug in
    # the caller and should be loud rather than quietly answered.
    cat > "$M/bin/pacman" <<'EOF'
#!/bin/sh
case "$1" in
  -Qq) shift; [ "$1" = -- ] && shift
       grep -qx "$1" "$IFOS_GPU_SYSROOT/data/pkgs" ;;
  -Q)  shift; [ "$1" = -- ] && shift
       grep -m1 "^$1 " "$IFOS_GPU_SYSROOT/data/pkgs.versions" 2>/dev/null || exit 1 ;;
  *)   echo "fake pacman: unexpected $*" >&2; exit 99 ;;
esac
EOF
    cat > "$M/bin/pacman-conf" <<'EOF'
#!/bin/sh
[ "$1" = --repo-list ] && cat "$IFOS_GPU_SYSROOT/data/repos"
EOF
    cat > "$M/bin/modinfo" <<'EOF'
#!/bin/sh
# modinfo -k <release> <module>
grep -qx "$2 $3" "$IFOS_GPU_SYSROOT/data/modinfo"
EOF
    cat > "$M/bin/glxinfo" <<'EOF'
#!/bin/sh
cat "$IFOS_GPU_SYSROOT/data/glxinfo" 2>/dev/null
EOF
    cat > "$M/bin/uname" <<'EOF'
#!/bin/sh
[ "$1" = -r ] && cat "$IFOS_GPU_SYSROOT/data/krel"
EOF
    chmod +x "$M"/bin/*
    : > "$M/data/pkgs.versions"
}

cards()    { printf '%s\n' "$@" > "$M/data/lspci"; }
packages() { printf '%s\n' "$@" > "$M/data/pkgs"; }
version()  { printf '%s %s\n' "$1" "$2" >> "$M/data/pkgs.versions"; }
loaded()   { local m; for m in "$@"; do printf '%s 1 0 - Live 0x0\n' "$m" >> "$M/proc/modules"; done; }
buildable() { local m; for m in "$@"; do printf '%s %s\n' "$KREL" "$m" >> "$M/data/modinfo"; done; }
renderer() { printf 'OpenGL renderer string: %s\n' "$1" > "$M/data/glxinfo"; }
multilib() { printf 'core\nextra\nmultilib\n' > "$M/data/repos"; }
kernel_is() { mkdir -p "$M/usr/lib/modules/$1"; printf '%s\n' "$2" > "$M/usr/lib/modules/$1/pkgbase"; }
nvidia_running() { mkdir -p "$M/proc/driver/nvidia"
                   printf 'NVRM version: NVIDIA UNIX x86_64 Kernel Module  %s  Mon\n' "$1" \
                      > "$M/proc/driver/nvidia/version"; }
drm_modeset() { printf '%s\n' "$1" > "$M/sys/module/nvidia_drm/parameters/modeset"; }

# ── Running one ──────────────────────────────────────────────────────────────

OUT=""; RC=0
run_check() {
    OUT=$(IFOS_GPU_SYSROOT="$M" PATH="$M/bin:/usr/bin:/bin" DISPLAY=:0 COLUMNS=200 \
          bash "$GPU" --check 2>&1)
    RC=$?
}

case_name() { printf '\n  %s%s%s\n' "$c_dim" "$1" "$c_reset"; }

check() {   # check <description> <test...>
    local desc=$1; shift
    if "$@"; then
        PASS=$((PASS+1)); printf '    %s✓%s %s\n' "$c_grn" "$c_reset" "$desc"
    else
        FAIL=$((FAIL+1)); printf '    %s✗%s %s\n' "$c_red" "$c_reset" "$desc"
        printf '%s\n' "$OUT" | sed 's/^/        /'
    fi
}

says()     { grep -qi -- "$1" <<<"$OUT"; }
not_says() { ! grep -qi -- "$1" <<<"$OUT"; }
rc_is()    { [[ $RC == "$1" ]]; }

# ═════════════════════════════════════════════════════════════════════════════

printf '\n  ifos-gpu — máquinas de mentira\n'

# ── 1. A healthy AMD desktop. This is Rogério's machine. ──────────────────────
case_name "AMD desktop, tudo instalado"
new_machine amd-ok 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600]"
packages mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
         vulkan-icd-loader lib32-vulkan-icd-loader
loaded amdgpu
multilib
kernel_is 6.12.1-arch1-1 linux
renderer "AMD Radeon RX 6600 (radeonsi, navi23, LLVM 18.1.8)"
run_check
check "sai 0"                    rc_is 0
check "diz que está tudo certo"  says "tudo certo"
check "não inventa problema"     not_says "✗"

# ── 2. The same AMD machine as it actually arrives: no 32-bit anything ────────
case_name "AMD sem multilib — o Steam não abre"
new_machine amd-broken 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600]"
packages mesa vulkan-radeon vulkan-icd-loader
loaded amdgpu
kernel_is 6.12.1-arch1-1 linux
renderer "AMD Radeon RX 6600 (radeonsi, navi23, LLVM 18.1.8)"
run_check
check "sai 1"                       rc_is 1
check "aponta o multilib"           says "multilib"
check "cita o Steam"                says "Steam"
check "pede lib32-mesa"             says "lib32-mesa"
check "pede lib32-vulkan-radeon"    says "lib32-vulkan-radeon"

# ── 3. The reported failure: NVIDIA driver, no module for the running kernel ──
#  nvidia-open is prebuilt against `linux`. This machine booted linux-lts, so
#  there is no nvidia module at all and X fell back to software rendering.
case_name "NVIDIA híbrido no kernel LTS — driver pré-compilado, sem módulo"
new_machine nv-lts 6.6.63-1-lts
cards "00:02.0 VGA compatible controller: Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics]" \
      "01:00.0 3D controller: NVIDIA Corporation GA107M [GeForce RTX 3050 Mobile]"
packages mesa lib32-mesa vulkan-intel lib32-vulkan-intel \
         vulkan-icd-loader lib32-vulkan-icd-loader \
         nvidia-open nvidia-utils steam linux linux-lts
loaded i915
multilib
kernel_is 6.6.63-1-lts linux-lts
kernel_is 6.12.1-arch1-1 linux
renderer "llvmpipe (LLVM 18.1.8, 256 bits)"
run_check
check "sai 1"                          rc_is 1
check "diz que não há módulo nvidia"   says "não existe módulo nvidia"
check "nomeia o kernel que está rodando" says "6.6.63-1-lts"
check "aponta o driver pré-compilado"  says "pré-compilada"
check "conta os dois kernels"          says "2 kernels"
check "diz que é o processador desenhando" says "processador"
check "pede lib32-nvidia-utils"        says "lib32-nvidia-utils"
check "pede nvidia-prime (híbrido)"    says "nvidia-prime"

# ── 4. Driver updated, machine not rebooted ──────────────────────────────────
case_name "NVIDIA atualizada sem reiniciar"
new_machine nv-stale 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation AD104 [GeForce RTX 4070]"
packages nvidia-open-dkms dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
         linux-headers vulkan-icd-loader lib32-vulkan-icd-loader linux
loaded nvidia nvidia_drm nvidia_modeset
buildable nvidia
multilib
kernel_is 6.12.1-arch1-1 linux
version nvidia-utils 570.86.16-1
nvidia_running 565.77
drm_modeset Y
renderer "NVIDIA GeForce RTX 4070/PCIe/SSE2"
run_check
check "sai 1"                    rc_is 1
check "aponta a diferença"       says "565.77"
check "manda reiniciar"          says "reiniciar"

# ── 5. nouveau took the card first ───────────────────────────────────────────
case_name "NVIDIA com o nouveau ocupando a placa"
new_machine nv-nouveau 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation TU117 [GeForce GTX 1650]"
packages nvidia-open-dkms dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
         linux-headers vulkan-icd-loader lib32-vulkan-icd-loader linux
loaded nouveau
buildable nvidia
multilib
kernel_is 6.12.1-arch1-1 linux
renderer "llvmpipe (LLVM 18.1.8, 256 bits)"
run_check
check "sai 1"            rc_is 1
check "culpa o nouveau"  says "nouveau"

# ── 6. Intel-only laptop, nothing wrong with it ──────────────────────────────
case_name "Notebook só com Intel"
new_machine intel-ok 6.12.1-arch1-1
cards "00:02.0 VGA compatible controller: Intel Corporation TigerLake-LP GT2 [Iris Xe Graphics]"
packages mesa lib32-mesa vulkan-intel lib32-vulkan-intel \
         vulkan-icd-loader lib32-vulkan-icd-loader
loaded i915
multilib
kernel_is 6.12.1-arch1-1 linux
renderer "Mesa Intel(R) Xe Graphics (TGL GT2)"
run_check
check "sai 0"                   rc_is 0
check "não pede nada da NVIDIA" not_says "nvidia"

# ── 7. An old NVIDIA card on nouveau, which is the right answer for it ────────
#  Nobody gets dragged onto a driver that does not support their card.
case_name "GTX 750 no nouveau — é o certo, não é defeito"
new_machine nv-old 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation GM107 [GeForce GTX 750 Ti]"
packages mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader
loaded nouveau
multilib
kernel_is 6.12.1-arch1-1 linux
renderer "NV117"
run_check
check "sai 0"                        rc_is 0
check "reconhece que é o certo"      says "nouveau"
check "não manda instalar a NVIDIA"  not_says "sem o driver da NVIDIA"

# ── 8. Modern NVIDIA, no driver installed at all ─────────────────────────────
case_name "RTX sem driver nenhum"
new_machine nv-none 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation GA106 [GeForce RTX 3060]"
packages mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader
multilib
kernel_is 6.12.1-arch1-1 linux
renderer "llvmpipe (LLVM 18.1.8, 256 bits)"
run_check
check "sai 1"                     rc_is 1
check "diz que falta o driver"    says "sem o driver da NVIDIA"

# ── 9. No pciutils: cannot even look ─────────────────────────────────────────
case_name "Sem lspci"
new_machine no-lspci 6.12.1-arch1-1
rm -f "$M/bin/lspci"
kernel_is 6.12.1-arch1-1 linux
run_check
check "sai 1"             rc_is 1
check "pede o pciutils"   says "pciutils"

# ── 10. Working NVIDIA with nvidia_drm modeset off ───────────────────────────
case_name "NVIDIA sem modeset"
new_machine nv-nomodeset 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation AD107 [GeForce RTX 4060]"
packages nvidia-open-dkms dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
         linux-headers vulkan-icd-loader lib32-vulkan-icd-loader linux
loaded nvidia nvidia_drm
buildable nvidia
multilib
kernel_is 6.12.1-arch1-1 linux
version nvidia-utils 570.86.16-1
nvidia_running 570.86.16
drm_modeset N
renderer "NVIDIA GeForce RTX 4060/PCIe/SSE2"
run_check
check "sai 1"           rc_is 1
check "aponta o modeset" says "modeset"

# ── 11. DKMS driver installed but the headers for this kernel are not ─────────
case_name "DKMS sem os headers do kernel que está rodando"
new_machine nv-noheaders 6.6.63-1-lts
cards "01:00.0 VGA compatible controller: NVIDIA Corporation GA106 [GeForce RTX 3060]"
packages nvidia-open-dkms dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
         linux-headers vulkan-icd-loader lib32-vulkan-icd-loader linux linux-lts
multilib
kernel_is 6.6.63-1-lts linux-lts
renderer "llvmpipe (LLVM 18.1.8, 256 bits)"
run_check
check "sai 1"                          rc_is 1
check "pede linux-lts-headers"         says "linux-lts-headers"
check "não pede linux-headers de novo" not_says " linux-headers"

# ── 12. Booted with nomodeset ────────────────────────────────────────────────
case_name "Iniciado com nomodeset"
new_machine nv-cmdline 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation GA106 [GeForce RTX 3060]"
packages nvidia-open-dkms dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
         linux-headers vulkan-icd-loader lib32-vulkan-icd-loader linux
buildable nvidia
multilib
kernel_is 6.12.1-arch1-1 linux
echo "BOOT_IMAGE=/vmlinuz-linux root=/dev/sda2 rw nomodeset" > "$M/proc/cmdline"
renderer "llvmpipe (LLVM 18.1.8, 256 bits)"
run_check
check "sai 1"              rc_is 1
check "aponta o nomodeset" says "nomodeset"

# ── 13. Healthy, but with no glxinfo to confirm it ───────────────────────────
#  Every machine installed before the doctor existed is in this state. It is
#  not a fault and must not raise the notification at login - but --fix should
#  still pick the package up, so the next check is a complete one.
case_name "Sem o glxinfo — falta, mas não é defeito"
new_machine no-glxinfo 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600]"
packages mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
         vulkan-icd-loader lib32-vulkan-icd-loader
loaded amdgpu
multilib
kernel_is 6.12.1-arch1-1 linux
rm -f "$M/bin/glxinfo"
run_check
check "sai 0 — nada quebrado"      rc_is 0
check "pede o mesa-utils mesmo assim" says "mesa-utils"
check "não chama isso de problema"    not_says "✗"

# ── 14. Every entry point still works ────────────────────────────────────────
case_name "As outras opções"
new_machine flags 6.12.1-arch1-1
cards "00:02.0 VGA compatible controller: Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics]" \
      "01:00.0 3D controller: NVIDIA Corporation GA107M [GeForce RTX 3050 Mobile]"
kernel_is 6.12.1-arch1-1 linux
env_run() { IFOS_GPU_SYSROOT="$M" PATH="$M/bin:/usr/bin:/bin" COLUMNS=200 bash "$GPU" "$@"; }
env_run --has-dgpu >/dev/null 2>&1
check "--has-dgpu acha a dedicada" [ $? = 0 ]
OUT=$(env_run --help 2>&1); RC=$?
check "--help sai 0"       rc_is 0
check "--help lista --fix" says -- "--fix"
OUT=$(env_run --nonsense 2>&1); RC=$?
check "opção inválida sai 2" rc_is 2

new_machine flags-single 6.12.1-arch1-1
cards "00:02.0 VGA compatible controller: Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics]"
kernel_is 6.12.1-arch1-1 linux
IFOS_GPU_SYSROOT="$M" PATH="$M/bin:/usr/bin:/bin" bash "$GPU" --has-dgpu >/dev/null 2>&1
check "--has-dgpu recusa uma placa só" [ $? = 1 ]

# `run` has to reach the program even with no prime-run installed.
OUT=$(IFOS_GPU_SYSROOT="$M" PATH="$M/bin:/usr/bin:/bin" \
      bash "$GPU" run sh -c 'echo "$__GLX_VENDOR_LIBRARY_NAME"' 2>&1); RC=$?
check "run exporta as variáveis do offload" says "nvidia"

# ── 15. ifos-term, which is how --fix reaches the screen ─────────────────────
#  The launcher's repair tile is `ifos-term 'Vídeo e jogos' ifos-gpu --fix`,
#  handed to /bin/sh -c as one string. Three things have to survive that: the
#  accented title, the split between title and command, and the arguments -
#  and none of them is visible until somebody clicks the tile.
case_name "ifos-term leva o comando até o terminal"
T="$TMP/term"; mkdir -p "$T/bin"
cat > "$T/bin/xfce4-terminal" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$RECORD"
shift 3           # -T <title> -x
"$@" </dev/null
EOF
printf '#!/bin/sh\necho "GPU-ARGS:$*"\n'  > "$T/bin/ifos-gpu"
printf '#!/bin/sh\nexec "$@"\n'           > "$T/bin/setsid"
chmod +x "$T"/bin/*

OUT=$(RECORD="$T/record" PATH="$T/bin:/usr/bin:/bin" \
      bash "$PROFILE/airootfs/usr/local/bin/ifos-term" \
           'Vídeo e jogos' ifos-gpu --fix </dev/null 2>&1)
RC=$?
check "o comando chega inteiro"        says "GPU-ARGS:--fix"
REC=$(cat "$T/record" 2>/dev/null); OUT=$REC
check "o título acentuado sobrevive"   says "Vídeo e jogos"
check "usa -x, não -e, no xfce4-terminal" says -- "-x"

OUT=$(PATH="/usr/bin:/bin" bash "$PROFILE/airootfs/usr/local/bin/ifos-term" 2>&1); RC=$?
check "sem comando, recusa"            rc_is 2

# ── 16. ifos-controller, against controllers this machine does not have ──────
#  /proc/bus/input/devices is the kernel's own list and the same shape on every
#  machine, so a file describing a DualSense is a DualSense as far as the tool
#  can tell. The one thing worth checking is that it recognises the families by
#  their ids rather than by anything in the name, because the name is whatever
#  the driver felt like calling it.
case_name "ifos-controller reconhece os controles"
CTL="$PROFILE/airootfs/usr/local/bin/ifos-controller"
DEV="$TMP/devices"

pads() { printf '%s\n' "$@" > "$DEV"; }
run_ctl() { OUT=$(IFOS_CONTROLLER_DEVICES="$DEV" bash "$CTL" "$@" 2>&1); RC=$?; }

# What the kernel prints for a DualSense on USB, cut down to the lines read.
pads 'I: Bus=0003 Vendor=054c Product=0ce6 Version=8111' \
     'N: Name="Sony Interactive Entertainment DualSense Wireless Controller"' \
     'H: Handlers=event4 js0 ' \
     '' \
     'I: Bus=0011 Vendor=0001 Product=0001 Version=ab41' \
     'N: Name="AT Translated Set 2 keyboard"' \
     'H: Handlers=sysrq kbd event0 '
run_ctl
check "acha o DualSense"                says "DualSense (PS5)"
check "não confunde o teclado com um controle" not_says "AT Translated"
check "diz onde ele está"               says "js0"

pads 'I: Bus=0005 Vendor=057e Product=2009 Version=0001' \
     'N: Name="Pro Controller"' \
     'H: Handlers=event7 js0 '
run_ctl
check "acha o Switch Pro"               says "Switch Pro"

pads 'I: Bus=0003 Vendor=045e Product=0b12 Version=0407' \
     'N: Name="Microsoft Xbox Series S|X Controller"' \
     'H: Handlers=event6 js1 '
run_ctl
check "acha o controle do Xbox"         says "controle do Xbox"

pads 'I: Bus=0011 Vendor=0001 Product=0001 Version=ab41' \
     'N: Name="AT Translated Set 2 keyboard"' \
     'H: Handlers=sysrq kbd event0 '
run_ctl
check "sem controle, diz que não há"    says "Nenhum controle conectado"
check "e manda parear"                  says "--pair"

run_ctl --pair
check "--pair explica o DualSense"      says "Create"
check "--pair explica o Xbox"           says "Pair"
run_ctl --nonsense
check "opção inválida sai 2"            rc_is 2

# ── 17. ifos-mouse, against a mouse this machine does not have ───────────────
#  The reason this is tested rather than eyeballed: the first version parsed
#  `xinput list --short` with a literal space between the name and the id, and
#  xinput uses a tab. It matched nothing at all on a real machine while looking
#  entirely reasonable, and there is no way to notice that without running it
#  against xinput's actual output.
case_name "ifos-mouse fala com o xinput de verdade"
MSE="$PROFILE/airootfs/usr/local/bin/ifos-mouse"
M2="$TMP/mouse"; mkdir -p "$M2/bin" "$M2/home"
cat > "$M2/devices" <<'EOF'
I: Bus=0003 Vendor=046d Product=c539 Version=0111
N: Name="Logitech G502 HERO Gaming Mouse"
H: Handlers=sysrq kbd mouse0 event3 

I: Bus=0018 Vendor=06cb Product=ce44 Version=0100
N: Name="SYNA8004:00 06CB:CE44 Touchpad"
H: Handlers=mouse1 event7 
EOF
# xinput's real output: box-drawing characters, and a TAB before id=.
cat > "$M2/bin/xinput" <<'EOF'
#!/bin/bash
case "$1 $2" in
  "list --short")
    printf 'â¡ Virtual core pointer          	id=2	[master pointer  (3)]
'
    printf 'â   â³ Logitech G502 HERO Gaming Mouse	id=9	[slave  pointer  (2)]
'
    printf 'â   â³ SYNA8004:00 06CB:CE44 Touchpad	id=11	[slave  pointer  (2)]
'
    exit 0 ;;
esac
case "$1" in
  list-props)
    printf 'Device "x":
	libinput Accel Speed (300):	%s
	libinput Accel Profile Enabled (302):	1, 0
' \
        "$(cat "$RECORD.speed" 2>/dev/null || echo 0.000000)"
    exit 0 ;;
  set-prop)
    shift; id=$1; shift; prop=$1; shift
    printf '%s|%s|%s
' "$id" "$prop" "$*" >> "$RECORD"
    [ "$prop" = "libinput Accel Speed" ] && printf '%s' "$*" > "$RECORD.speed"
    exit 0 ;;
esac
exit 1
EOF
chmod +x "$M2/bin/xinput"
rm -f "$M2/record" "$M2/record.speed"

run_mouse() {
    OUT=$(IFOS_MOUSE_DEVICES="$M2/devices" DISPLAY=:0 PATH="$M2/bin:/usr/bin:/bin" \
          RECORD="$M2/record" HOME="$M2/home" bash "$MSE" "$@" 2>&1)
    RC=$?
}

run_mouse
check "lista o mouse"                says "G502"
check "marca o touchpad como tal"    says "touchpad"
check "explica o botão de DPI"       says "dentro do próprio"

run_mouse --speed 4
check "aceita a velocidade"          rc_is 0
OUT=$(cat "$M2/record")
check "traduz 4 para o 0.40 do libinput" says "libinput Accel Speed|0.40"
check "não mexe no touchpad"         not_says "^11|"

OUT=$(cat "$M2/home/.config/ifos/mouse")
check "salva a escolha"              says "SPEED=4"

run_mouse --faster
OUT=$(cat "$M2/home/.config/ifos/mouse")
check "--faster anda dois passos"    says "SPEED=6"

rm -f "$M2/record"
run_mouse --apply
OUT=$(cat "$M2/record")
check "--apply devolve o que foi salvo" says "libinput Accel Speed|0.60"

run_mouse --speed abacaxi
check "recusa uma velocidade que não é número" rc_is 2

run_mouse --flat
check "--flat sai 0 quando funciona"  rc_is 0
OUT=$(cat "$M2/record")
check "--flat desliga a aceleração"   says "Accel Profile Enabled|0 1"

# No xinput at all: every setting has to refuse rather than claim success.
OUT=$(IFOS_MOUSE_DEVICES="$M2/devices" DISPLAY=:0 PATH="/usr/bin:/bin" \
      HOME="$M2/home" bash "$MSE" --flat 2>&1); RC=$?
check "sem xinput, --flat sai 1"      rc_is 1

run_mouse --nonsense
check "opção inválida sai 2"         rc_is 2

# A generic gaming mouse presents itself as two or three devices: the pointer,
# and one or two the kernel treats as keyboards, which is where the extra
# buttons send their keycodes. --test listened to the first one only, so a DPI
# button that *does* reach the computer looked exactly like one that does not.
cat > "$M2/redragon" <<'EOF'
I: Bus=0003 Vendor=258a Product=1007 Version=0111
N: Name="SINOWEALTH Wired Gaming Mouse"
H: Handlers=mouse0 event4 

I: Bus=0003 Vendor=258a Product=1007 Version=0111
N: Name="SINOWEALTH Wired Gaming Mouse Keyboard"
H: Handlers=sysrq kbd event5 

I: Bus=0003 Vendor=046d Product=c31c Version=0111
N: Name="Some other keyboard entirely"
H: Handlers=sysrq kbd event0 
EOF
OUT=$(IFOS_MOUSE_DEVICES="$M2/redragon" DISPLAY="" HOME="$M2/home" \
      bash "$MSE" --test 2>&1); RC=$?
check "--test pega os dois nós do mesmo mouse" says "event4 event5"
check "e não pega o teclado de verdade"        not_says "event0"

OUT=$(IFOS_MOUSE_DEVICES="$M2/redragon" DISPLAY=:0 PATH="$M2/bin:/usr/bin:/bin" \
      RECORD="$M2/record" HOME="$M2/home" bash "$MSE" 2>&1)
check "avisa que o Piper não cobre esse mouse" says "provavelmente não vai reconhecer"
check "o nome sai limpo, sem os ids colados"   not_says "258a:1007"

OUT=$(IFOS_MOUSE_DEVICES="$M2/devices" DISPLAY=:0 PATH="$M2/bin:/usr/bin:/bin" \
      RECORD="$M2/record" HOME="$M2/home" bash "$MSE" 2>&1)
check "e que num Logitech vale tentar"         says "costuma reconhecer"

# ── 18. ifos-software tells the truth about what it installed ────────────────
#  A catalog entry naming a package that is not in the AUR shipped, and the
#  install ended with a green "Pronto." under yay's own "no package found for
#  targets". The person went looking for a program that had never been
#  installed. Whatever the reason a package does not arrive, the last line has
#  to say so.
case_name "ifos-software não diz Pronto depois de falhar"
SW="$PROFILE/airootfs/usr/local/bin/ifos-software"
SWD="$TMP/sw"; mkdir -p "$SWD/bin" "$SWD/apps.d"
printf 'Bom|Existe|pacote-bom|repo\nRuim|Não existe no AUR|pacote-ruim|aur\n' \
    > "$SWD/apps.d/10-teste.list"
printf '#!/bin/sh\nexec "$@"\n'                       > "$SWD/bin/sudo"
printf '#!/bin/sh\nexit 0\n'                          > "$SWD/bin/pacman"
printf '#!/bin/sh\necho "no package found for targets" >&2\nexit 1\n' > "$SWD/bin/yay"
printf '#!/bin/sh\nexit 0\n'                          > "$SWD/bin/pacman-conf"
chmod +x "$SWD"/bin/*

run_sw() {
    OUT=$(IFOS_CATALOG_DIR="$SWD/apps.d" PATH="$SWD/bin:/usr/bin:/bin" \
          bash "$SW" -i "$1" </dev/null 2>&1)
    RC=$?
}

run_sw Ruim
check "não termina com Pronto"      not_says "Pronto."
check "diz que faltou instalar"     says "não foram instalados"
check "nomeia o pacote"             says "pacote-ruim"
check "explica o 'no package found'" says "esse pacote não existe"
check "sai diferente de zero"       [ "$RC" != 0 ]

run_sw Bom
check "quando dá certo, diz Pronto" says "Pronto."
check "e sai zero"                  rc_is 0

# ── 18b. A DPI button in software ────────────────────────────────────────────
#  What the DPI button was being pressed for, done where the computer can see
#  it. The whole point is the mouse whose DPI button is deaf but whose side
#  button is not, so the fixtures are exactly that: an ordinary click on the
#  pointer node, and a keycode on the keyboard-looking sibling.
case_name "Um botão de DPI em software"
FAKEIN="$M2/input"; mkdir -p "$FAKEIN"
python3 - "$FAKEIN" <<'PYEV'
import struct, sys, pathlib
SIZE = struct.calcsize("llHHi")
def ev(kind, code, value):
    return struct.pack("llHHi", 0, 0, kind, code, value)
root = pathlib.Path(sys.argv[1])
# the pointer half: an ordinary left click, which must be ignored
(root / "event4").write_bytes(ev(1, 0x110, 1) + ev(1, 0x110, 0))
# the keyboard half: a side button sending keycode 183
(root / "event5").write_bytes(ev(1, 183, 1) + ev(1, 183, 0))
PYEV

M3="$M2/learned"; mkdir -p "$M3"
learn_env() {
    IFOS_MOUSE_DEVICES="$M2/redragon" IFOS_MOUSE_INPUT_DIR="$FAKEIN" DISPLAY=:0 \
    PATH="$M2/bin:/usr/bin:/bin" RECORD="$M2/rec2" \
    XDG_RUNTIME_DIR="$M3" HOME="$M3" "$@"
}
rm -f "$M2/rec2" "$M2/rec2.speed"

OUT=$(learn_env timeout 20 bash "$MSE" --learn 2>&1); RC=$?
check "--learn aprende um botão"        rc_is 0
OUT=$(cat "$M3/.config/ifos/mouse" 2>/dev/null)
check "e guarda o código certo"         says "BUTTON=183"
check "ignorando o clique esquerdo"     not_says "BUTTON=272"

# The daemon: sees that code and steps the speed. It also has to *end* when the
# devices go away rather than spinning on a descriptor that returns nothing,
# which is what reaching the end of these files stands in for.
rm -f "$M2/rec2" "$M2/rec2.speed"
learn_env timeout 15 bash "$MSE" --daemon >/dev/null 2>&1
RC=$?
check "--daemon termina sozinho, não gira" rc_is 0
OUT=$(cat "$M2/rec2" 2>/dev/null)
check "e mudou a sensibilidade"         says "libinput Accel Speed|0.30"

# Three levels, and back to the start.
rm -f "$M2/rec2" "$M2/rec2.speed"
printf 'SPEED=0\n' > "$M3/.config/ifos/mouse"
for _ in 1 2 3; do learn_env bash "$MSE" --cycle >/dev/null 2>&1; done
OUT=$(cat "$M2/rec2")
check "o ciclo passa por três e volta"  says "0.00"
check "sem parar no meio"               says "0.60"

OUT=$(learn_env bash "$MSE" --forget 2>&1); RC=$?
check "--forget sai 0"                  rc_is 0
OUT=$(learn_env bash "$MSE" --daemon 2>&1); RC=$?
check "e o daemon volta a sair calado"  rc_is 1

# ── 19. The system files that are not scripts ────────────────────────────────
#  udev refuses a whole rules file over one bad line and says so only in the
#  journal, at boot, on a machine nobody is watching. Two of these decide
#  whether a controller rumbles and whether a spinning disk freezes the desktop.
case_name "As regras do udev e o earlyoom estão válidos"
if command -v udevadm >/dev/null 2>&1; then
    OUT=$(udevadm verify "$PROFILE"/airootfs/etc/udev/rules.d/*.rules 2>&1); RC=$?
    check "udevadm aceita todas as regras" rc_is 0
    check "e não reprova nenhuma"          says "Fail:    0"
else
    printf '    %s·%s udevadm não está aqui; regras não verificadas\n' "$c_dim" "$c_reset"
fi

# systemd splits $EARLYOOM_ARGS at whitespace and does *not* remove quotes, so
# a pattern written as '...' arrives with the quote characters still in it and
# matches nothing, silently. No argument may contain one.
OUT=$(grep '^EARLYOOM_ARGS=' "$PROFILE/airootfs/etc/default/earlyoom" || true)
check "earlyoom tem argumentos"        says "EARLYOOM_ARGS="
check "e nenhuma aspa neles"           not_says "'"

# ── 20. The catalog is well formed ───────────────────────────────────────────
#  Four fields, and a source ifos-software knows what to do with. A fifth pipe
#  or a typo in the source silently drops the line, or sends it to pacman when
#  it belongs to the AUR.
case_name "O catálogo está bem formado"
BAD=$(awk -F'|' '!/^#/ && NF>1 && NF!=4 {print FILENAME": "$0}' \
      "$PROFILE"/airootfs/usr/share/ifos/apps.d/*.list)
OUT=$BAD
check "toda linha tem quatro campos" [ -z "$BAD" ]

BAD=$(awk -F'|' '!/^#/ && NF==4 && $4!="repo" && $4!="multilib" && $4!="aur" && $4!="flatpak" \
      {print FILENAME": "$4}' "$PROFILE"/airootfs/usr/share/ifos/apps.d/*.list)
OUT=$BAD
check "toda origem é conhecida"      [ -z "$BAD" ]

BAD=$(awk -F'|' '!/^#/ && NF==4 && $3 !~ /^[a-zA-Z0-9@._+-]+( [a-zA-Z0-9@._+-]+)*$/ \
      {print FILENAME": "$3}' "$PROFILE"/airootfs/usr/share/ifos/apps.d/*.list)
OUT=$BAD
check "todo nome de pacote é plausível" [ -z "$BAD" ]

# ═════════════════════════════════════════════════════════════════════════════
printf '\n  %s%d passaram%s' "$c_grn" "$PASS" "$c_reset"
(( FAIL )) && printf ', %s%d falharam%s' "$c_red" "$FAIL" "$c_reset"
printf '\n\n'
(( FAIL == 0 ))
