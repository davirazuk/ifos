#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  build.sh — build the IFOS ISO
#
#  archiso only runs on Arch, so this runs mkarchiso inside a rootless podman
#  container. Works from any distribution; no sudo required.
#
#      ./build.sh              build the ISO into ./out
#      ./build.sh --clean      also discard the cached packages
#      ./build.sh --shell      drop into the build container to poke around
#
#  Expect roughly 15 GB of scratch space and a long first run while packages
#  download. Later builds reuse the package cache in ./.pkgcache, so they only
#  re-download what actually changed upstream.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${IFOS_WORK:-$PROFILE/work}"
OUT="${IFOS_OUT:-$PROFILE/out}"
# Kept outside WORK so wiping the work directory does not throw away ~2.5 GB of
# downloaded packages.
CACHE="${IFOS_CACHE:-$PROFILE/.pkgcache}"
IMAGE="${IFOS_IMAGE:-ifos-builder}"

# The build runs as an unprivileged user inside the container, so parts of the
# work directory end up owned by mapped subordinate uids that the host user
# cannot delete. Removing it has to happen as root *inside* a container.
wipe_work() {
    [[ -e $WORK ]] || return 0
    podman run --rm --privileged -v "$PROFILE":/profile:z "$IMAGE" \
        rm -rf /profile/work >/dev/null 2>&1 || true
    rm -rf "$WORK" 2>/dev/null || true
    if [[ -e $WORK ]]; then
        die "Could not remove $WORK. Try: podman unshare rm -rf '$WORK'"
    fi
}

c_reset=$'\033[0m'; c_blue=$'\033[1;34m'; c_grn=$'\033[1;32m'; c_red=$'\033[1;31m'
info() { printf '%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }
die()  { printf '%s==> ERROR:%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

MODE=build
case ${1:-} in
    --clean) MODE=clean ;;
    --shell) MODE=shell ;;
    -h|--help) sed -n '3,15p' "$0" | sed 's/^# \?//'; exit 0 ;;
    "") ;;
    *) die "Unknown option: $1" ;;
esac

command -v podman >/dev/null || die "podman is not installed."

# ── The profile depends on symlinks; make sure they survived transport ───────
info "Checking profile integrity…"
"$PROFILE/tools/fix-symlinks.sh"

# Icons that are a space rather than a glyph. This has shipped three times -
# the whole bar, most of fastfetch, and every on-screen display - because "  "
# and " " are indistinguishable in a diff and nothing errors. Cheap to check,
# invisible otherwise.
if command -v python3 >/dev/null; then
    python3 "$PROFILE/tools/check-icons.py" ||
        die "Icons are missing above. Fix them, or edit tools/check-icons.py if a file legitimately changed shape."
fi

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

# mkarchiso tracks completed stages with marker files in the work directory, so
# a leftover tree from an earlier run makes pacstrap collide with a root that is
# already populated. Always start from a clean one; the package cache survives.
info "Preparing a clean work directory…"
wipe_work

if [[ $MODE == clean ]]; then
    info "Discarding the package cache too…"
    rm -rf "$CACHE"
fi

mkdir -p "$WORK" "$OUT" "$CACHE"

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
    -v "$CACHE":/var/cache/pacman/pkg:z,dev,suid,exec \
    -v "$PROFILE/tools/build-entrypoint.sh":/usr/local/bin/build-entrypoint:ro,z \
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
