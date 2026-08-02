#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  branding-sync.sh [target-root]
#
#  Copies everything that makes IFOS *IFOS* into a target root - the dotfiles,
#  wallpaper, login theme, boot splash, software catalog and the ifos-* tools.
#
#  The installer runs this against /mnt before creating the user account, so
#  useradd copies the IFOS /etc/skel instead of a stock one. Running it with no
#  argument re-applies the branding to the running system, which is handy after
#  an upgrade overwrites something.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

TARGET=${1:-/}
# Normally we copy from the running system. ifos-update sets IFOS_SOURCE to a
# fresh git checkout's airootfs, so the same code applies an update.
SRC="${IFOS_SOURCE:-/}"
SRC="${SRC%/}"
[[ -d $TARGET ]] || { echo "branding-sync: no such directory: $TARGET" >&2; exit 1; }

# Resolve to avoid copying a tree onto itself.
TARGET=$(realpath "$TARGET")
[[ $TARGET == / ]] && TARGET=""

copy() {    # copy <path> [mode]
    local path=$1 mode=${2:-}
    local from="$SRC$path" to="$TARGET$path"
    [[ -e $from ]] || return 0
    [[ $from -ef $to ]] && return 0
    install -d "$(dirname "$to")"
    if [[ -d $from ]]; then
        cp -a "$from/." "$to/" 2>/dev/null || return 1
    else
        cp -a "$from" "$to" 2>/dev/null || return 1
    fi
    [[ -n $mode ]] && chmod "$mode" "$to"
    return 0
}

echo "==> Applying IFOS branding to ${TARGET:-/}"

# Desktop defaults for every new account
copy /etc/skel

# Input. Tap-to-click, which libinput leaves off by default.
copy /etc/X11/xorg.conf.d/30-touchpad.conf

# Compressed swap in RAM, so machines installed before this reach it too.
copy /etc/systemd/zram-generator.conf

# Kernel tuning: vm.max_map_count for games under Proton, vm.swappiness for
# zram. This was only ever on the live ISO - nothing copied it to /mnt and
# nothing recreated it in the chroot - so every installed system ran with the
# stock 65530 map limit, and the games that need more failed to start with
# nothing to explain why.
copy /etc/sysctl.d/99-ifos.conf

# Bounds on the two things that otherwise grow to fill the disk: the journal,
# which systemd sizes at 10% of the filesystem, and the pacman cache, which
# keeps three versions of every package. Both hurt most on the small eMMC
# laptops, and neither was ever set on an installed system.
copy /etc/systemd/journald.conf.d/ifos-limits.conf
copy /etc/systemd/system/paccache.service.d/ifos-keep-one.conf

# Look and feel
copy /usr/share/backgrounds/ifos.png
copy /usr/share/backgrounds/ifos-ifms.png
copy /usr/share/backgrounds/ifos-mocha.png
copy /usr/share/ifos/lock
copy /usr/share/sddm/themes/ifos
copy /etc/sddm.conf.d/ifos.conf

# That file autologins the live user. `ifos` exists on the ISO and nowhere else,
# so on an installed system the greeter would try to log in as a user who is not
# there and never show the login screen. The installer strips those two lines
# after it runs; do it here too, or every ifos-update would put them back.
if [[ ! -d ${TARGET}/run/archiso && -f ${TARGET}/etc/sddm.conf.d/ifos.conf ]]; then
    sed -i '/^\[Autologin\]/,/^\[/{/^User=/d;/^Session=/d}' \
        "${TARGET}/etc/sddm.conf.d/ifos.conf" &&
        echo "    autologin removed from sddm.conf.d/ifos.conf (installed system)"
fi
copy /usr/share/plymouth/themes/ifos
copy /usr/share/grub/themes/ifos
copy /etc/plymouth/plymouthd.conf
copy /etc/systemd/system/ifos-fontcache.service
copy /etc/ifos/update.conf

# Distribution identity
copy /etc/os-release
copy /usr/share/ifos/apps.d
copy /usr/share/ifos/keybindings.txt
copy /usr/share/ifos/logo.txt
copy /usr/share/icons/hicolor/scalable/apps/ifos-logo.svg
copy /usr/share/ifos/escola.list
copy /usr/share/ifos/i3-bigpicture.config
copy /usr/share/xsessions/ifos-bigpicture.desktop
copy /usr/share/ifos/post-install.sh     0755
copy /usr/share/ifos/branding-sync.sh    0755
copy /usr/share/ifos/repair-dotfiles.sh  0755
copy /usr/share/ifos/archinstall-preset.json

# Tools
for t in ifos-software ifos-welcome ifos-post-install ifos-theme ifos-launcher \
         ifos-bigpicture ifos-update ifos-lock ifos-gpu ifos-scale install-yay; do
    copy "/usr/local/bin/$t" 0755
done

# Applications menu entries
copy /usr/share/applications/ifos-software.desktop
copy /usr/share/applications/ifos-welcome.desktop
copy /usr/share/applications/ifos-launcher.desktop

# ── Did any of that actually land? ───────────────────────────────────────────
# copy() hides cp's errors, so a copy that fails leaves no trace: a missing
# login theme just turns into SDDM quietly drawing its built-in greeter, with
# nothing on screen to say why. Name the ones worth checking.
missing=0
for p in /usr/share/sddm/themes/ifos/Main.qml \
         /usr/share/sddm/themes/ifos/metadata.desktop \
         /etc/skel/.config/rofi/ifos.rasi \
         /etc/skel/.config/i3/config \
         /usr/share/ifos/apps.d \
         /usr/local/bin/ifos-software; do
    [[ -e "$TARGET$p" ]] || { echo "  !! did not copy: $p" >&2; missing=$((missing + 1)); }
done
(( missing )) && echo "==> $missing expected file(s) are missing from ${TARGET:-/}" >&2

echo "==> Done"
