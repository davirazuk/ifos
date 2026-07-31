#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  flash-usb.sh — write the IFOS ISO to a USB stick, with the guards that a
#  bare `dd` does not have.
#
#      sudo ./tools/flash-usb.sh /dev/sdX [image.iso]
#      sudo ./tools/flash-usb.sh --list
#
#  It refuses to write to:
#    * the disk holding / or /home  (the single most expensive dd mistake)
#    * any disk that is not removable, unless --force
#    * a partition rather than a whole disk
#
#  and then verifies the written bytes against the image instead of trusting
#  that dd succeeded.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

c_reset=$'\033[0m'; c_b=$'\033[1m'; c_grn=$'\033[1;32m'
c_blue=$'\033[1;34m'; c_yel=$'\033[1;33m'; c_red=$'\033[1;31m'
info() { printf '%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$c_grn"  "$c_reset" "$*"; }
warn() { printf '%s  !%s %s\n' "$c_yel"  "$c_reset" "$*"; }
die()  { printf '\n%s==> ERROR:%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORCE=0
ASSUME_YES=0
TARGET=""
IMAGE=""

list_devices() {
    printf '\n%s  Removable devices%s\n\n' "$c_b" "$c_reset"
    local found=0 d name rm size model
    for d in /sys/block/*; do
        name=$(basename "$d")
        case $name in loop*|ram*|zram*|dm-*|sr*) continue ;; esac
        rm=$(cat "$d/removable" 2>/dev/null)
        [[ $rm == 1 ]] || continue
        size=$(lsblk -dno SIZE "/dev/$name" 2>/dev/null)
        model=$(cat "$d/device/model" 2>/dev/null | xargs)
        printf '    /dev/%-10s %-9s %s\n' "$name" "$size" "$model"
        found=1
    done
    (( found )) || printf '    (none found)\n'
    printf '\n'
}

for arg in "$@"; do
    case $arg in
        -h|--help) sed -n '3,17p' "$0" | sed 's/^# \?//'; exit 0 ;;
        --list)    list_devices; exit 0 ;;
        --force)   FORCE=1 ;;
        --yes)     ASSUME_YES=1 ;;
        /dev/*)    TARGET=$arg ;;
        *.iso)     IMAGE=$arg ;;
        *) die "unknown argument '$arg'" ;;
    esac
done

[[ $EUID -eq 0 ]] || die "Needs root:  sudo $0 $*"
[[ -n $TARGET ]]  || { list_devices; die "Give a target device, e.g. sudo $0 /dev/sdb"; }

# Newest ISO in out/ unless one was named.
if [[ -z $IMAGE ]]; then
    IMAGE=$(find "$PROFILE/out" -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' 2>/dev/null |
            sort -rn | head -1 | cut -d' ' -f2-)
fi
[[ -f $IMAGE ]] || die "No ISO found. Run ./build.sh first, or pass one as an argument."

# ── Guards ───────────────────────────────────────────────────────────────────
[[ -b $TARGET ]] || die "$TARGET is not a block device."

DEV=$(basename "$TARGET")
[[ -d /sys/block/$DEV ]] || die "$TARGET looks like a partition. Give the whole disk (e.g. /dev/sdb, not /dev/sdb1)."

# The disk that carries the running system, whatever it is called.
system_disks=$(
    for mp in / /home /boot /boot/efi; do
        src=$(findmnt -no SOURCE "$mp" 2>/dev/null | sed 's/\[.*\]//') || continue
        [[ -n $src ]] || continue
        lsblk -npo PKNAME "$src" 2>/dev/null | head -1
    done | sort -u
)
while read -r disk; do
    [[ -n $disk ]] || continue
    if [[ $disk == "$TARGET" ]]; then
        die "$TARGET carries the running system ($(echo "$system_disks" | tr '\n' ' ')). Refusing."
    fi
done <<<"$system_disks"

REMOVABLE=$(cat "/sys/block/$DEV/removable" 2>/dev/null)
if [[ $REMOVABLE != 1 ]] && (( ! FORCE )); then
    die "$TARGET is not removable. If you are certain, re-run with --force."
fi

SIZE_BYTES=$(blockdev --getsize64 "$TARGET")
IMAGE_BYTES=$(stat -c%s "$IMAGE")
(( SIZE_BYTES >= IMAGE_BYTES )) || die "$TARGET is smaller than the image."

# ── Confirm ──────────────────────────────────────────────────────────────────
printf '\n%s  About to write:%s\n\n' "$c_b" "$c_reset"
printf '    image   %s  (%s)\n' "$IMAGE" "$(numfmt --to=iec "$IMAGE_BYTES")"
printf '    target  %s  (%s, %s)\n' "$TARGET" "$(numfmt --to=iec "$SIZE_BYTES")" \
       "$(cat "/sys/block/$DEV/device/model" 2>/dev/null | xargs)"
printf '\n'
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$TARGET" 2>/dev/null
printf '\n%s  Everything on %s will be destroyed.%s\n\n' "$c_yel" "$TARGET" "$c_reset"

if (( ! ASSUME_YES )); then
    read -rp "  Type ERASE to continue: " reply
    [[ $reply == ERASE ]] || die "Not confirmed - nothing was written."
fi

# ── Write ────────────────────────────────────────────────────────────────────
info "Unmounting anything on $TARGET…"
while read -r part; do
    [[ -n $part ]] || continue
    umount "$part" 2>/dev/null && ok "unmounted $part"
done < <(lsblk -nplo NAME "$TARGET" | tail -n +2)

info "Writing… (this takes a few minutes)"
if ! dd if="$IMAGE" of="$TARGET" bs=4M status=progress oflag=direct conv=fsync; then
    die "dd failed. The stick is now in an inconsistent state - re-run before using it."
fi
sync
ok "Written"

# ── Verify ───────────────────────────────────────────────────────────────────
info "Verifying what actually landed on the stick…"
blockdev --flushbufs "$TARGET" 2>/dev/null
expected=$(sha256sum "$IMAGE" | cut -d' ' -f1)
actual=$(head -c "$IMAGE_BYTES" "$TARGET" | sha256sum | cut -d' ' -f1)

if [[ $expected == "$actual" ]]; then
    ok "Verified - the stick matches the image byte for byte"
    printf '\n%s  Done. Boot from it and pick IFOS in your firmware boot menu.%s\n\n' "$c_grn" "$c_reset"
else
    die "Verification FAILED. Expected $expected, got $actual. Do not boot this stick."
fi
