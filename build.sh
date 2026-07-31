#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  build.sh — build the IFOS ISO
#
#  archiso only runs on Arch, so this runs mkarchiso inside a rootless podman
#  container. Works from any distribution; no sudo required.
#
#      ./build.sh              build the ISO into ./out
#      ./build.sh --clean      throw away the work directory first
#      ./build.sh --shell      drop into the build container to poke around
#
#  Expect roughly 15 GB of scratch space and a long first run while packages
#  download. Subsequent builds reuse the pacman cache in ./work.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${IFOS_WORK:-$PROFILE/work}"
OUT="${IFOS_OUT:-$PROFILE/out}"
IMAGE="${IFOS_IMAGE:-ifos-builder}"

c_reset=$'\033[0m'; c_blue=$'\033[1;34m'; c_grn=$'\033[1;32m'; c_red=$'\033[1;31m'
info() { printf '%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }
die()  { printf '%s==> ERROR:%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

MODE=build
case ${1:-} in
    --clean) MODE=clean ;;
    --shell) MODE=shell ;;
    -h|--help) sed -n '3,14p' "$0" | sed 's/^# \?//'; exit 0 ;;
    "") ;;
    *) die "Unknown option: $1" ;;
esac

command -v podman >/dev/null || die "podman is not installed."

# ── The profile depends on symlinks; make sure they survived transport ───────
info "Checking profile integrity…"
"$PROFILE/tools/fix-symlinks.sh"

# ── Build environment ────────────────────────────────────────────────────────
if ! podman image exists "$IMAGE"; then
    info "Building the $IMAGE container image (one time)…"
    podman build -t "$IMAGE" -f "$PROFILE/tools/Containerfile" "$PROFILE/tools"
fi

# ── Resolve every package name before spending 30 minutes on the build ──────
if [[ ${IFOS_SKIP_PKG_CHECK:-0} != 1 ]]; then
    info "Verifying package names against the repositories…"
    "$PROFILE/tools/check-packages.sh" || die "Fix the package names above, or set IFOS_SKIP_PKG_CHECK=1 to build anyway."
fi

if [[ $MODE == clean ]]; then
    info "Removing $WORK…"
    podman run --rm --privileged -v "$PROFILE":/profile:z "$IMAGE" \
        rm -rf /profile/work 2>/dev/null || rm -rf "$WORK"
fi

mkdir -p "$WORK" "$OUT"

if [[ $MODE == shell ]]; then
    exec podman run --rm -it --privileged \
        -v "$PROFILE":/profile:z -v "$WORK":/work:z,dev,suid,exec -v "$OUT":/out:z \
        "$IMAGE" bash
fi

# ── Build ────────────────────────────────────────────────────────────────────
info "Running mkarchiso (this takes a while)…"
start=$SECONDS

podman run --rm --privileged \
    -v "$PROFILE":/profile:z \
    -v "$WORK":/work:z,dev,suid,exec \
    -v "$OUT":/out:z \
    "$IMAGE" \
    build-entrypoint

elapsed=$(( SECONDS - start ))
iso=$(find "$OUT" -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

printf '\n%s  IFOS built in %dm%02ds%s\n\n' "$c_grn" $((elapsed/60)) $((elapsed%60)) "$c_reset"
if [[ -n ${iso:-} ]]; then
    printf '    %s\n    %s\n\n' "$iso" "$(du -h "$iso" | cut -f1)"
    printf '  Write it to a USB stick with:\n'
    printf '    sudo dd if=%s of=/dev/sdX bs=4M status=progress oflag=sync\n\n' "$iso"
    printf '  Or test it first without a USB stick:\n'
    printf '    qemu-system-x86_64 -m 4G -enable-kvm -cdrom %s\n\n' "$iso"
fi
