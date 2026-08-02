#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  test-gpu.sh — run ifos-gpu --check against machines that do not exist
#
#  The graphics doctor exists to diagnose machines that are broken in specific
#  ways: an NVIDIA module built for the kernel that is not running, nouveau
#  holding the card the proprietary driver wanted, multilib switched off so
#  Steam's 32-bit libraries cannot even be installed. None of those can be
#  reproduced on the machine this is developed on, and every one of them is a
#  student sitting in front of a computer that will not open Steam.
#
#  So each case below builds a fake machine - an lspci that lists chosen cards,
#  a pacman that knows a chosen package list, a /proc/modules with chosen
#  modules in it - and checks that the doctor says the right thing about it.
#
#      ./tools/test-gpu.sh
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

# ── 13. Every entry point still works ────────────────────────────────────────
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

# ═════════════════════════════════════════════════════════════════════════════
printf '\n  %s%d passaram%s' "$c_grn" "$PASS" "$c_reset"
(( FAIL )) && printf ', %s%d falharam%s' "$c_red" "$FAIL" "$c_reset"
printf '\n\n'
(( FAIL == 0 ))
