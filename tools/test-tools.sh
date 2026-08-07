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
    : > "$M/data/klog"

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

# The driver creates one of these per card it actually took. A machine with the
# module loaded and none of these is the failure that looked healthy for months:
# installed, loaded, drawing on the processor.
bound()      { mkdir -p "$M/proc/driver/nvidia/gpus/0000:01:00.0"
               : > "$M/proc/driver/nvidia/gpus/0000:01:00.0/information"; }
# What the driver itself said. Worth more than anything guessed from a model
# number, because it names the driver branch that would work, by number.
nvrm()       { printf '%s\n' "$@" > "$M/data/klog"; }
# A machine that has an /etc/mkinitcpio.conf.d at all, with whatever is given.
mkinitcpio_has() { mkdir -p "$M/etc/mkinitcpio.conf.d"
                   printf '%s\n' "$@" > "$M/etc/mkinitcpio.conf.d/ifos.conf"; }

# ── Running one ──────────────────────────────────────────────────────────────

OUT=""; RC=0
run_check() {
    OUT=$(IFOS_GPU_SYSROOT="$M" IFOS_GPU_KLOG="$M/data/klog" \
          PATH="$M/bin:/usr/bin:/bin" DISPLAY=:0 COLUMNS=200 \
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
bound
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
bound
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

# ── 14. The one that made NVIDIA look unfixable ──────────────────────────────
#  A GTX 1060 with the open modules on it. Everything about this machine reads
#  as correctly configured: the package is installed, the module is loaded, and
#  pacman is happy. The open modules do not support Pascal, so they bound no
#  card at all, and the desktop is being drawn by the processor. Every check
#  that only asked "is the module loaded" said yes, which is why this survived.
case_name "GTX 1060 com os módulos abertos — instala, carrega, não pega a placa"
new_machine nv-open-on-pascal 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB]"
packages nvidia-open-dkms dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
         linux-headers vulkan-icd-loader lib32-vulkan-icd-loader linux
loaded nvidia nvidia_drm nvidia_modeset
buildable nvidia
multilib
kernel_is 6.12.1-arch1-1 linux
version nvidia-utils 570.86.16-1
nvidia_running 570.86.16
drm_modeset Y
renderer "llvmpipe (LLVM 18.1.8, 256 bits)"
run_check
check "sai 1"                            rc_is 1
check "diz que o driver é o errado"      says "não funciona nesta placa"
check "nomeia a geração"                 says "Pascal"
check "manda para o driver fechado"      says "fechado"
check "não diz que está tudo certo"      not_says "tudo certo"

# ── 15. The same machine, with the driver's own words in the kernel log ──────
#  NVRM says it in one line. When it does, the diagnosis has to be the same
#  diagnosis - not a second one stacked on top of the first.
case_name "…e o próprio driver dizendo isso no log"
new_machine nv-open-nvrm 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB]"
packages nvidia-open-dkms dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
         linux-headers vulkan-icd-loader lib32-vulkan-icd-loader linux
loaded nvidia
buildable nvidia
multilib
kernel_is 6.12.1-arch1-1 linux
nvrm "NVRM: The NVIDIA GPU 0000:01:00.0 (PCI ID: 10de:1c03)" \
     "NVRM: installed in this system is not supported by the NVIDIA open kernel modules." \
     "NVRM: No NVIDIA devices probed."
renderer "llvmpipe (LLVM 18.1.8, 256 bits)"
run_check
check "sai 1"                          rc_is 1
check "aponta os módulos abertos"      says "abertos"
check "não repete o mesmo problema"    [ "$(grep -c 'módulos abertos' <<<"$OUT")" -le 2 ]

# ── 15b. The right driver, and it still took no card ─────────────────────────
#  An RTX with the open modules is the supported combination, so nothing about
#  the packages explains this - a failed GSP firmware load or a module built
#  against the wrong kernel does. There is nothing specific to say, and saying
#  the vague true thing is still better than the green tick this used to print.
case_name "Driver certo, placa não assumida, e nada no log"
new_machine nv-unbound 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation GA106 [GeForce RTX 3060]"
packages nvidia-open-dkms dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
         linux-headers vulkan-icd-loader lib32-vulkan-icd-loader linux
loaded nvidia nvidia_drm
buildable nvidia
multilib
kernel_is 6.12.1-arch1-1 linux
renderer "llvmpipe (LLVM 18.1.8, 256 bits)"
run_check
check "sai 1"                        rc_is 1
check "diz que não assumiu a placa"  says "não assumiu nenhuma placa"
check "não afirma que carregou tudo bem" not_says "com a placa nas mãos"

# ── 15c. One sentence, for the notification at login ─────────────────────────
#  That notification said "a placa de vídeo não está funcionando direito" on
#  every machine and every fault alike. Everything needed to say *which* fault
#  was already being computed and thrown away.
case_name "O aviso de login diz qual é o problema"
why_run() {
    OUT=$(IFOS_GPU_SYSROOT="$M" IFOS_GPU_KLOG="$M/data/klog" \
          PATH="$M/bin:/usr/bin:/bin" DISPLAY=:0 COLUMNS=200 \
          bash "$GPU" --why 2>&1)
    RC=$?
}

new_machine why-broken 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB]"
packages nvidia-open-dkms dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
         linux-headers vulkan-icd-loader lib32-vulkan-icd-loader linux
loaded nvidia
buildable nvidia
multilib
kernel_is 6.12.1-arch1-1 linux
renderer "llvmpipe (LLVM 18.1.8, 256 bits)"
why_run
check "sai 1 quando há problema"    rc_is 1
check "e nomeia o problema"         says "não funciona nesta placa"
check "numa linha só"               [ "$(grep -c . <<<"$OUT")" = 1 ]

new_machine why-ok 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600]"
packages mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
         vulkan-icd-loader lib32-vulkan-icd-loader
loaded amdgpu
multilib
kernel_is 6.12.1-arch1-1 linux
renderer "AMD Radeon RX 6600 (radeonsi, navi23, LLVM 18.1.8)"
why_run
check "sai 0 numa máquina boa"      rc_is 0
check "e não diz nada"              [ -z "$OUT" ]

OUT=$(cat "$PROFILE/airootfs/etc/skel/.config/i3/scripts/gpu-watch.sh")
check "o aviso de login usa o --why" says -- "--why"

# ── 16. Kepler: no driver in the repositories at all ─────────────────────────
#  Offering an NVIDIA driver here is how the last version sent people in
#  circles - there is none to install. nouveau is the answer that works today,
#  and the AUR name is worth saying without pretending it is easy.
case_name "GTX 760 (Kepler) — nenhum driver da NVIDIA existe para ela"
new_machine nv-kepler 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation GK104 [GeForce GTX 760]"
packages mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader
loaded nouveau
multilib
kernel_is 6.12.1-arch1-1 linux
renderer "NVE4"
run_check
check "sai 0 — nouveau é o certo aqui"  rc_is 0
check "reconhece a geração"             says "Kepler"
check "nomeia o pacote do AUR"          says "nvidia-470xx-dkms"
check "não oferece um driver que não existe" not_says "sem o driver da NVIDIA"

# ── 17. The driver naming its own legacy branch ──────────────────────────────
#  This is ground truth and nothing else on the machine has it: the number in
#  the message is the driver series that would actually drive this card.
case_name "O driver dizendo qual série serve nesta placa"
new_machine nv-legacy-msg 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation GF119 [GeForce GT 610]"
packages nvidia-dkms dkms nvidia-utils lib32-nvidia-utils linux-headers \
         vulkan-icd-loader lib32-vulkan-icd-loader linux
loaded nvidia
buildable nvidia
multilib
kernel_is 6.12.1-arch1-1 linux
nvrm "NVRM: The NVIDIA GeForce GT 610 GPU installed in this system is" \
     "NVRM: supported through the NVIDIA 390.xx Legacy drivers."
renderer "llvmpipe (LLVM 18.1.8, 256 bits)"
run_check
check "sai 1"                    rc_is 1
check "repete o número da série" says "série 390"
check "aponta o nouveau"         says "nouveau"

# ── 18. Hardware failure, said as hardware failure ───────────────────────────
#  Nothing in the system configuration causes this and no amount of reinstalling
#  drivers fixes it. Saying so is the whole value.
case_name "RmInitAdapter — a placa não inicializa"
new_machine nv-rminit 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation TU106 [GeForce RTX 2060]"
packages nvidia-open-dkms dkms nvidia-utils lib32-nvidia-utils linux-headers \
         vulkan-icd-loader lib32-vulkan-icd-loader linux
loaded nvidia
buildable nvidia
multilib
kernel_is 6.12.1-arch1-1 linux
nvrm "NVRM: GPU 0000:01:00.0: RmInitAdapter failed! (0x26:0xffff:1477)"
renderer "llvmpipe (LLVM 18.1.8, 256 bits)"
run_check
check "sai 1"                    rc_is 1
check "chama de hardware"        says "hardware"
check "não manda trocar driver"  not_says "fechado"

# ── 19. The kms hook, which is why nouveau kept winning the race ─────────────
case_name "Módulos da NVIDIA fora da imagem de boot"
new_machine nv-nokms 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation AD107 [GeForce RTX 4060]"
packages nvidia-open-dkms dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
         linux-headers vulkan-icd-loader lib32-vulkan-icd-loader linux
loaded nvidia nvidia_drm
buildable nvidia
bound
multilib
kernel_is 6.12.1-arch1-1 linux
version nvidia-utils 570.86.16-1
nvidia_running 570.86.16
drm_modeset Y
mkinitcpio_has 'HOOKS=(base udev plymouth autodetect microcode modconf kms keyboard block filesystems fsck)'
renderer "NVIDIA GeForce RTX 4060/PCIe/SSE2"
run_check
check "não chama isso de defeito"  rc_is 0
check "mas avisa"                  says "imagem de boot"

# ── 20. The table that decides which driver a card gets ──────────────────────
#  Every wrong answer here is a machine that installs a driver, loads it, and
#  draws on the processor. Checked by name, one card per generation.
case_name "Cada placa recebe o driver certo"
nv_expect() {   # nv_expect <lspci line> <expected package>
    new_machine nv-pick 6.12.1-arch1-1 >/dev/null
    cards "01:00.0 VGA compatible controller: NVIDIA Corporation $1"
    kernel_is 6.12.1-arch1-1 linux
    OUT=$(IFOS_GPU_SYSROOT="$M" IFOS_GPU_KLOG="$M/data/klog" \
          PATH="$M/bin:/usr/bin:/bin" bash "$GPU" --nvidia-pkg 2>&1)
    check "$1 → $2" [ "$OUT" = "$2" ]
}
nv_expect "GB203 [GeForce RTX 5080]"          nvidia-open-dkms
nv_expect "AD102 [GeForce RTX 4090]"          nvidia-open-dkms
nv_expect "GA106 [GeForce RTX 3060]"          nvidia-open-dkms
nv_expect "TU117M [GeForce GTX 1650 Mobile]"  nvidia-open-dkms
nv_expect "GP107 [GeForce GTX 1050 Ti]"       nvidia-dkms
nv_expect "GM206 [GeForce GTX 960]"           nvidia-dkms
nv_expect "GM107 [GeForce GTX 750 Ti]"        nvidia-dkms
nv_expect "GK107 [GeForce GT 640]"            nvidia-470xx-dkms
nv_expect "GF108 [GeForce GT 430]"            nvidia-390xx-dkms
# No codename in the string, only the number on the box.
nv_expect "Device 2882 [GeForce RTX 3050]"    nvidia-open-dkms
nv_expect "Device 1c81 [GeForce GTX 1050]"    nvidia-dkms
# And a card nothing recognises gets the driver that covers more hardware,
# because guessing wrong towards the open modules is the silent failure.
nv_expect "Device 9999 [GeForce Something]"   nvidia-dkms

# ── 21. The safety net: a machine with no driver at all must still get a desktop
case_name "O socorro antes da tela de login"
fallback_run() {
    IFOS_GPU_SYSROOT="$M" IFOS_GPU_KLOG="$M/data/klog" \
        PATH="$M/bin:/usr/bin:/bin" bash "$GPU" --fallback >/dev/null 2>&1
}
fake_modprobe() {
    cat > "$M/bin/modprobe" <<'EOF'
#!/bin/sh
echo "$@" >> "$IFOS_GPU_SYSROOT/data/modprobe"
EOF
    chmod +x "$M/bin/modprobe"
    : > "$M/data/modprobe"
}

# Desktop, NVIDIA only, driver installed, card unbound: no graphics at all.
new_machine fb-dead 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB]"
packages nvidia-open-dkms nvidia-utils
loaded nvidia
kernel_is 6.12.1-arch1-1 linux
fake_modprobe
fallback_run
check "carrega o nouveau quando não há vídeo nenhum" \
      grep -q nouveau "$M/data/modprobe"

# Same machine with the card bound: the driver works, leave it alone.
new_machine fb-ok 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: NVIDIA Corporation AD107 [GeForce RTX 4060]"
packages nvidia-open-dkms nvidia-utils
loaded nvidia
bound
kernel_is 6.12.1-arch1-1 linux
fake_modprobe
fallback_run
check "não mexe num driver que funciona" [ ! -s "$M/data/modprobe" ]

# Hybrid laptop: the integrated chip is drawing, the session is not at risk,
# and loading a second driver under a working machine is the worse trade.
new_machine fb-hybrid 6.12.1-arch1-1
cards "00:02.0 VGA compatible controller: Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics]" \
      "01:00.0 3D controller: NVIDIA Corporation GA107M [GeForce RTX 3050 Mobile]"
packages nvidia-open-dkms nvidia-utils
loaded nvidia i915
kernel_is 6.12.1-arch1-1 linux
fake_modprobe
fallback_run
check "não mexe num notebook híbrido que tem tela" [ ! -s "$M/data/modprobe" ]

# An AMD machine has nothing to do with any of this.
new_machine fb-amd 6.12.1-arch1-1
cards "01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600]"
loaded amdgpu
kernel_is 6.12.1-arch1-1 linux
fake_modprobe
fallback_run
check "não faz nada numa máquina AMD" [ ! -s "$M/data/modprobe" ]

# ── 22. Every entry point still works ────────────────────────────────────────
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

# ── 23. ifos-term, which is how --fix reaches the screen ─────────────────────
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
# --test needs the graphical session now, because that is where the buttons
# are: reading the device directly is what never worked.
OUT=$(IFOS_MOUSE_DEVICES="$M2/redragon" DISPLAY="" HOME="$M2/home" \
      bash "$MSE" --test 2>&1); RC=$?
check "--test sem X recusa e diz por quê"      says "sessão gráfica"
check "e sai diferente de zero"                rc_is 1

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
#  The first version of this read /dev/input directly and never detected
#  anything on a real machine: systemd grants a logged-in user access to an
#  input device only when it is a joystick, so a mouse's event node is
#  root-only. Everything goes through X now, which needs no privilege and sees
#  exactly what an application would - so the fake here is xinput's own
#  test-xi2 output, in the shape the real one prints it.
case_name "Um botão de DPI em software"
cat > "$M2/bin/xinput" <<'EOF'
#!/bin/bash
case "$1 $2" in
  "list --short")
    printf '\xe2\x8e\x9c   \xe2\x86\xb3 Redragon Gaming Mouse\tid=9\t[slave  pointer  (2)]\n'
    exit 0 ;;
  "test-xi2 --root")
    # An ordinary left click, which --learn must refuse, then the side button.
    printf 'EVENT type 15 (RawButtonPress)\n    device: 9 (9)\n    detail: 1\n'
    printf 'EVENT type 15 (RawButtonPress)\n    device: 9 (9)\n    detail: 9\n'
    exit 0 ;;
esac
case "$1" in
  list-props)
    printf 'Device "x":\n\tlibinput Accel Speed (300):\t%s\n\tlibinput Accel Profile Enabled (302):\t1, 0\n' \
        "$(cat "$RECORD.speed" 2>/dev/null || echo 0.000000)"
    exit 0 ;;
  set-prop)
    shift; id=$1; shift; prop=$1; shift
    printf '%s|%s|%s\n' "$id" "$prop" "$*" >> "$RECORD"
    [ "$prop" = "libinput Accel Speed" ] && printf '%s' "$*" > "$RECORD.speed"
    exit 0 ;;
esac
exit 1
EOF
chmod +x "$M2/bin/xinput"

M3="$M2/learned"; rm -rf "$M3"; mkdir -p "$M3"
learn_env() {
    IFOS_MOUSE_DEVICES="$M2/redragon" DISPLAY=:0 \
    PATH="$M2/bin:/usr/bin:/bin" RECORD="$M2/rec2" \
    XDG_RUNTIME_DIR="$M3" HOME="$M3" "$@"
}
rm -f "$M2/rec2" "$M2/rec2.speed"

OUT=$(learn_env timeout 20 bash "$MSE" --learn 2>&1); RC=$?
check "--learn aprende um botão"          rc_is 0
check "e nomeia qual foi"                 says "botão lateral"
OUT=$(cat "$M3/.config/ifos/mouse" 2>/dev/null)
check "guarda o número do X"              says "BUTTON=button:9"
check "recusando o clique esquerdo"       not_says "button:1$"

# The watcher: same stream, acts on the learned one.
rm -f "$M2/rec2" "$M2/rec2.speed"
learn_env timeout 15 bash "$MSE" --daemon >/dev/null 2>&1
check "--daemon termina sozinho, não gira" rc_is 0
OUT=$(cat "$M2/rec2" 2>/dev/null)
check "e mudou a sensibilidade"           says "libinput Accel Speed|0.30"

# Three levels, and back to the start.
rm -f "$M2/rec2" "$M2/rec2.speed"
printf 'SPEED=0\n' > "$M3/.config/ifos/mouse"
for _ in 1 2 3; do learn_env bash "$MSE" --cycle >/dev/null 2>&1; done
OUT=$(cat "$M2/rec2")
check "o ciclo passa por três e volta"    says "0.00"
check "sem parar no meio"                 says "0.60"

# A value left by the version that read /dev/input is a kernel code, from a
# device it could never open. Nothing was ever bound through it.
printf 'BUTTON=183\n' > "$M3/.config/ifos/mouse"
OUT=$(learn_env bash "$MSE" --daemon 2>&1); RC=$?
check "ignora o formato antigo"           rc_is 1

OUT=$(learn_env bash "$MSE" --forget 2>&1); RC=$?
check "--forget sai 0"                    rc_is 0
OUT=$(learn_env bash "$MSE" --daemon 2>&1); RC=$?
check "e o daemon volta a sair calado"    rc_is 1

# ── 18c. The compositor gets out of the way of a fullscreen game ─────────────
#  picom defaults unredir-if-possible to false, so a fullscreen game went on
#  being composited: a frame of latency, a second vsync fighting the game's
#  own, and GPU time on a machine with none to spare. Invisible - the frame
#  rate simply reads low.
case_name "O picom sai da frente de um jogo em tela cheia"
PICOMCFG="$PROFILE/airootfs/etc/skel/.config/picom/picom.conf"
OUT=$(cat "$PICOMCFG")
check "unredir-if-possible ligado"        says "unredir-if-possible = true"
check "sombra não em tela cheia"          says "fullscreen"
if command -v picom >/dev/null 2>&1 && command -v Xvfb >/dev/null 2>&1; then
    pkill -f 'Xvfb :91' 2>/dev/null; (Xvfb :91 -screen 0 800x600x24 >/dev/null 2>&1 &)
    sleep 1.5
    OUT=$(DISPLAY=:91 timeout 4 picom --config "$PICOMCFG" 2>&1)
    # Not "no FATAL ERROR": tearing the display down under it produces one, and
    # that is this script's doing rather than the configuration's. The parser
    # is what is being checked.
    check "picom analisa a configuração"  not_says "Error when reading configuration"
    check "sem erro de sintaxe"           not_says "syntax error"
    pkill -f 'Xvfb :91' 2>/dev/null
fi

# ── 18d. Pointer acceleration off for mice, on for touchpads ─────────────────
#  libinput's adaptive profile is why a game camera feels wrong: the same hand
#  movement turns a different amount depending on how fast it was, and no
#  in-game sensitivity setting can undo it because the distortion happens
#  before the game sees the movement.
case_name "Aceleração desligada no mouse, ligada no touchpad"
OUT=$(cat "$PROFILE/airootfs/etc/X11/xorg.conf.d/31-mouse.conf")
check "perfil flat para ponteiros"        says 'Option "AccelProfile" "flat"'
check "e o touchpad fica de fora"         says 'MatchIsTouchpad "off"'
OUT=$(cat "$PROFILE/airootfs/etc/X11/xorg.conf.d/30-touchpad.conf")
check "o touchpad mantém o dele"          not_says "AccelProfile"

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

# ── "Instalar ao lado" could destroy the thing it promised to keep ───────────
#  The menu entry says "manter todo o resto" and the installer says "nenhuma
#  outra partição foi modificada" afterwards. sgdisk is a GPT tool: handed a
#  disk with an MBR table - every machine that came with Windows 7, and plenty
#  that came with 10 - it converts the table in place and the other operating
#  system stops booting. Nothing warned.
#
#  The decision is a pure function of six values precisely so it can be run
#  here, without a disk anywhere near it.
case_name "Instalar ao lado só onde dá para cumprir a promessa"
eval "$(awk '/^alongside_block_reason\(\)/,/^}/' "$PROFILE/airootfs/usr/local/bin/install-ifos")"

reason() { OUT=$(alongside_block_reason "$@"); }

reason gpt UEFI /dev/sda1 "" 60000 20480
check "GPT com EFI e espaço: pode"       [ -z "$OUT" ]

reason dos UEFI /dev/sda1 "" 60000 20480
check "MBR: recusa"                      [ -n "$OUT" ]
check "e diz que converteria a tabela"   says "converteria"
check "e que o outro sistema pararia"    says "parar de iniciar"

reason "" UEFI /dev/sda1 "" 60000 20480
check "sem tabela nenhuma: recusa"       [ -n "$OUT" ]

reason gpt UEFI "" "" 60000 20480
check "GPT sem partição EFI: recusa"     [ -n "$OUT" ]
check "e nomeia a partição EFI"          says "EFI"

# GRUB embeds itself into a BIOS boot partition on a GPT disk. Without one,
# grub-install refuses - at the very last step, after everything is downloaded
# and written. Refusing here costs nothing; refusing there costs the install.
reason gpt BIOS "" "" 60000 20480
check "GPT em BIOS sem ef02: recusa"     [ -n "$OUT" ]
check "e diz que falharia no final"      says "falharia no final"

reason gpt BIOS "" /dev/sda1 60000 20480
check "GPT em BIOS com ef02: pode"       [ -z "$OUT" ]

reason gpt UEFI /dev/sda1 "" 10000 20480
check "espaço insuficiente: recusa"      [ -n "$OUT" ]
check "e diz quanto falta"               says "20 GiB"

OUT=$(cat "$PROFILE/airootfs/usr/local/bin/install-ifos")
check "o instalador consulta a tabela"   says "lsblk -dno PTTYPE"
check "e diz por que não deu, em vez de sumir com a opção" says "As outras opções continuam"

# ── Nothing may be destroyed before the last thing that can refuse ───────────
#  The "partition" mode reuses an existing EFI partition rather than creating
#  one, and the check that there *was* one lived after mkfs. On a UEFI machine
#  whose disk had no ESP the installer formatted the partition the student
#  chose - destroying whatever was on it - and only then gave up, saying it had
#  nowhere to put the bootloader. Nothing was gained by the formatting and
#  there was no way back.
#
#  So the invariant, checked by line number: every refusal comes before the
#  first command that writes to a disk.
case_name "O instalador recusa antes de escrever, nunca depois"
INST="$PROFILE/airootfs/usr/local/bin/install-ifos"

FIRST_WRITE=$(grep -nE '^[[:space:]]*(wipefs -af|sgdisk (--zap-all|-n )|mkfs\.(ext4|btrfs|vfat) )' \
              "$INST" | head -1 | cut -d: -f1)
ESP_CHECK=$(grep -n 'não tem partição de sistema EFI' "$INST" | head -1 | cut -d: -f1)
ESP_IS_TARGET=$(grep -n 'é a partição de sistema EFI do disco' "$INST" | head -1 | cut -d: -f1)
ALONGSIDE_CHECK=$(grep -n 'Não dá para instalar ao lado:' "$INST" | head -1 | cut -d: -f1)
OUT="primeira escrita em disco: linha $FIRST_WRITE
falta de EFI:              linha $ESP_CHECK
EFI escolhida como alvo:   linha $ESP_IS_TARGET
instalar ao lado:          linha $ALONGSIDE_CHECK"

check "existe uma primeira escrita para comparar" [ -n "$FIRST_WRITE" ]
check "a falta de partição EFI é recusada antes" \
      [ "${ESP_CHECK:-999999}" -lt "$FIRST_WRITE" ]
check "formatar a própria EFI é recusado antes" \
      [ "${ESP_IS_TARGET:-999999}" -lt "$FIRST_WRITE" ]
check "instalar ao lado é recusado antes" \
      [ "${ALONGSIDE_CHECK:-999999}" -lt "$FIRST_WRITE" ]

OUT=$(cat "$INST")
check "e as recusas dizem que nada foi alterado" \
      [ "$(grep -c 'Nada foi alterado no disco' "$INST")" -ge 2 ]

# ── The installer's first step used to stop on a working network ─────────────
#  ICMP is blocked on a great many school and campus networks. A single ping
#  as the connectivity test meant the installer refused to start on a machine
#  whose network was fine, with a message telling the student to connect to a
#  network they were already on, and nothing on screen suggesting a way past it.
case_name "O instalador testa a rede como o pacstrap vai testar"
INST="$PROFILE/airootfs/usr/local/bin/install-ifos"
OUT=$(cat "$INST")
check "tenta HTTPS de verdade"        says "curl -fsS --max-time 8"
check "com o ping só como reserva"    says "have_network"
check "e explica o portal de login"   says "login numa página"
check "o ping não é mais a única prova" \
      [ "$(grep -c 'ping -c1 -W3' "$INST")" = 1 ]

# ── The repair has to happen without being asked for ─────────────────────────
#  A fix that needs a second command is a fix most people never run. The whole
#  point of the graphics doctor is lost if somebody has to know it exists.
case_name "O ifos-update conserta o vídeo sozinho"
UPD="$PROFILE/airootfs/usr/local/bin/ifos-update"
GPUBIN="$PROFILE/airootfs/usr/local/bin/ifos-gpu"
OUT=$(cat "$UPD")
check "o ifos-update chama o conserto"     says "repair_graphics"
check "sem perguntar nada"                 says -- "--fix --yes"
check "e só quando há algo quebrado"       says -- "ifos-gpu --why >/dev/null"
check "não mexe no pendrive"               says "/run/archiso"
# The order matters: repairing before the packages and services have been
# brought up to date would repair things that were about to fix themselves.
check "conserta depois de configurar" \
      [ "$(grep -n '^configure_nvidia$\|^repair_graphics$' "$UPD" | tail -1 | cut -d: -f2)" = "repair_graphics" ]

OUT=$(cat "$GPUBIN")
check "o --fix aceita --yes"               says -- "-y|--yes|--auto"
check "que passa --noconfirm ao pacman"    says "noconfirm"
# pacman's answer to "remove the conflicting package?" defaults to *no*, so
# --noconfirm declines it and the unattended repair fails on the one machine it
# exists for. The open modules have to be removed by name first.
check "e tira os módulos abertos pelo nome" says "pacman -Rdd --noconfirm"

# ── The NVIDIA plumbing nobody can see until a machine boots ─────────────────
#  None of this can be tested by running anything: it is files that only mean
#  something to systemd, mkinitcpio and pacman at boot. What can be checked is
#  that they say what they are supposed to say, which is the difference between
#  a fix that shipped and a fix that was written.
case_name "A configuração de NVIDIA está ligada em todo lugar"
INST="$PROFILE/airootfs/usr/local/bin/install-ifos"
GPUBIN="$PROFILE/airootfs/usr/local/bin/ifos-gpu"
SVC="$PROFILE/airootfs/etc/systemd/system/ifos-gpu-fallback.service"

OUT=$(cat "$SVC" 2>/dev/null)
check "existe o serviço de socorro"        [ -f "$SVC" ]
check "roda antes da tela de login"        says "Before=display-manager.service"
check "e chama o ifos-gpu --fallback"      says -- "--fallback"

OUT=$(cat "$PROFILE/airootfs/usr/share/ifos/branding-sync.sh")
check "o branding-sync copia o serviço"    says "ifos-gpu-fallback.service"

OUT=$(cat "$INST")
check "o instalador liga o serviço"        says "systemctl enable ifos-gpu-fallback.service"
check "escreve a configuração da NVIDIA"   says -- "--write-nvidia-config"
check "liga a suspensão da NVIDIA"         says "nvidia-suspend.service"
check "pergunta ao ifos-gpu qual driver"   says -- "--nvidia-pkg"
check "e não manda mais escolher nouveau numa GTX 10xx" \
      not_says "GTX 900 ou 1000 — escolha o nouveau"
check "tem entrada de recuperação no menu de boot" says "recuperação de vídeo"

# The NVIDIA drop-in restates HOOKS in full, minus kms. That is a copy of the
# installer's line, and a copy silently goes stale: add a hook to install-ifos
# and an NVIDIA machine quietly stops getting it. The two have to differ by
# exactly one word, and that word has to be kms.
HOOKS_INST=$(grep -o 'HOOKS=([^)]*)' "$INST" | head -1 | sed 's/HOOKS=(//; s/)//')
HOOKS_NV=$(grep -o 'HOOKS=([^)]*)' "$GPUBIN" | head -1 | sed 's/HOOKS=(//; s/)//')
OUT="instalador: $HOOKS_INST
nvidia:     $HOOKS_NV"
check "as duas listas de hooks foram encontradas" [ -n "$HOOKS_INST" ] 
check "e a da NVIDIA também"                      [ -n "$HOOKS_NV" ]
check "e diferem só pelo kms" \
      [ "$(printf '%s\n' $HOOKS_INST | grep -vx kms | tr '\n' ' ')" = "$(printf '%s\n' $HOOKS_NV | tr '\n' ' ')" ]

# mkinitcpio sources /etc/mkinitcpio.conf.d/*.conf in sorted order and the last
# HOOKS assignment wins. The installer writes ifos.conf with the kms hook in
# it; the NVIDIA drop-in has to sort *after* that or it is silently overridden
# and the whole fix does nothing. "ifos-nvidia.conf" would have lost.
OUT=$(printf 'ifos.conf\nnvidia.conf\n' | sort | tail -1)
check "o arquivo da NVIDIA vence o do IFOS" [ "$OUT" = "nvidia.conf" ]
OUT=$(cat "$GPUBIN")
check "e é esse o nome escrito"             says "mkinitcpio.conf.d/nvidia.conf"
check "com os módulos da NVIDIA dentro"     says "MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)"
check "sem o hook kms junto"                [ "$(grep -c 'HOOKS=(.*modconf kms' "$GPUBIN")" = 0 ]
check "e um hook do pacman para a imagem de boot" says "pacman.d/hooks"

# The prebuilt driver serves one kernel, and IFOS installs two. Offering it in
# the catalog was offering a machine that loses its graphics on the LTS kernel.
OUT=$(cat "$PROFILE"/airootfs/usr/share/ifos/apps.d/*.list)
check "o catálogo não oferece mais o driver pré-compilado" not_says "|nvidia-open nvidia-utils"
check "e oferece o fechado para as placas antigas"         says "nvidia-dkms dkms nvidia-utils"

# ── GameMode was installed and doing almost nothing ──────────────────────────
#  The launcher wraps every game in gamemoderun. GameMode's own defaults are
#  renice=0 and ioprio=0, both of which mean "change nothing", so the only
#  thing that ever happened was the CPU governor. A config file with zeroes in
#  it would be the same bug written down.
case_name "GameMode realmente prioriza o jogo"
GM="$PROFILE/airootfs/etc/gamemode.ini"
OUT=$(cat "$GM" 2>/dev/null)
check "existe o /etc/gamemode.ini"       [ -f "$GM" ]
check "governador de desempenho"         says "desiredgov=performance"
check "prioridade de processador"        [ "$(sed -n 's/^renice=//p' "$GM")" != 0 ]
check "e prioridade de disco"            [ "$(sed -n 's/^ioprio=//p' "$GM")" != 0 ]
check "sem SCHED_ISO, que não existe no kernel do IFOS" says "softrealtime=off"

OUT=$(cat "$PROFILE/airootfs/usr/local/bin/install-ifos")
check "o instalador põe o usuário no grupo gamemode" says "usermod -aG gamemode"
check "mas não no useradd, que falharia inteiro"     not_says "wheel,audio,video,input,storage,network,lp,gamemode"
OUT=$(cat "$PROFILE/airootfs/usr/share/ifos/branding-sync.sh")
check "o branding-sync copia o gamemode.ini"         says "/etc/gamemode.ini"
OUT=$(cat "$PROFILE/airootfs/usr/local/bin/ifos-update")
check "e o ifos-update alcança quem já instalou"     says "configure_gamemode"

# ── Qt programs were coming up light in a dark desktop ───────────────────────
#  qt5ct.conf shipped with custom_palette=false, which means "use the style's
#  own palette", and Fusion's is light. And QT_QPA_PLATFORMTHEME=qt5ct names a
#  plugin that only exists for Qt5, so every Qt6 program - VLC, qBittorrent,
#  OBS - ignored the qt6ct configuration sitting right next to it.
case_name "Programas Qt seguem a paleta do IFOS"
for v in 5 6; do
    SCHEME="$PROFILE/airootfs/usr/share/qt${v}ct/colors/ifos.conf"
    CONF="$PROFILE/airootfs/etc/skel/.config/qt${v}ct/qt${v}ct.conf"
    OUT=$(cat "$SCHEME" 2>/dev/null)
    check "qt${v}ct tem a paleta do IFOS"  [ -f "$SCHEME" ]
    check "com os três estados"            [ "$(grep -c '^[a-z]*_colors=' "$SCHEME")" = 3 ]
    # 21 QPalette roles per state. A short row is silently accepted by qt5ct and
    # leaves the missing roles at the style's own - light - defaults.
    BAD=$(awk -F'=' '/_colors=/ { n = split($2, a, ","); if (n != 21) print $1" tem "n }' "$SCHEME")
    OUT=$BAD
    check "e 21 cores em cada"             [ -z "$BAD" ]
    # Every colour has to come from the IFOS palette, or ifos-theme will leave
    # it behind when the palette changes and it will sit there in the wrong hue.
    BAD=$(grep -oE '#ff[0-9a-f]{6}' "$SCHEME" | sort -u |
          grep -vE '#ff(10241d|1b3a2e|24503f|04150f|e8f5e9|b9d4c6|7fa392|00a86b|7ed957|00c47d)')
    OUT=$BAD
    check "só cores da paleta"             [ -z "$BAD" ]
    OUT=$(cat "$CONF" 2>/dev/null)
    check "qt${v}ct usa a paleta"          says "custom_palette=true"
    check "e aponta para o arquivo"        says "/usr/share/qt${v}ct/colors/ifos.conf"
done

OUT=$(cat "$PROFILE/airootfs/usr/local/bin/ifos-theme")
check "o ifos-theme repinta as duas"       [ "$(grep -c 'qt[56]ct/colors/ifos.conf' "$PROFILE/airootfs/usr/local/bin/ifos-theme")" = 2 ]
OUT=$(cat "$PROFILE/airootfs/usr/share/ifos/branding-sync.sh")
check "e o branding-sync copia as duas"    [ "$(grep -c 'qt[56]ct/colors/ifos.conf' "$PROFILE/airootfs/usr/share/ifos/branding-sync.sh")" = 2 ]

# All three places that export the variable have to agree, and each has to fall
# back to what it did before rather than naming a plugin that might not be there.
for f in .xprofile .bashrc .config/fish/conf.d/ifos.fish; do
    OUT=$(cat "$PROFILE/airootfs/etc/skel/$f")
    check "$f procura o plugin antes de nomeá-lo" says "libqgtk3.so"
    check "$f tem o caminho de volta"             says "qt5ct"
done

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
