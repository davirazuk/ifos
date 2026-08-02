#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  fix-symlinks.sh — restore the symlinks an archiso profile depends on
#
#  This exists because it already went wrong once. If the profile is copied
#  with `cp -rL`, unpacked from a GitHub "Download ZIP", or moved across a
#  filesystem that cannot store symlinks, every link in airootfs/ is either
#  flattened into a copy of whatever the *host* had at that path, or silently
#  dropped when the target did not exist. The result builds, boots, and behaves
#  strangely for reasons that are very hard to find later.
#
#  build.sh runs this automatically. Running it by hand is always safe.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
A="$PROFILE/airootfs"
SYS="$A/etc/systemd/system"

changed=0
link() {   # link <target> <path-relative-to-airootfs>
    local target=$1 path="$A/$2"
    if [[ -L $path && "$(readlink "$path")" == "$target" ]]; then
        return 0
    fi
    mkdir -p "$(dirname "$path")"
    rm -rf "$path"
    ln -sfn "$target" "$path"
    printf '  restored  %-72s -> %s\n' "/$2" "$target"
    changed=1
}

link /usr/share/zoneinfo/UTC               etc/localtime
link /run/systemd/resolve/stub-resolv.conf etc/resolv.conf
link /dev/null                             etc/systemd/system-generators/systemd-gpt-auto-generator

link /usr/lib/systemd/system/ModemManager.service      etc/systemd/system/dbus-org.freedesktop.ModemManager1.service
link /usr/lib/systemd/system/systemd-resolved.service  etc/systemd/system/dbus-org.freedesktop.resolve1.service
link /usr/lib/systemd/system/systemd-timesyncd.service etc/systemd/system/dbus-org.freedesktop.timesync1.service

link /usr/lib/systemd/system/graphical.target etc/systemd/system/default.target
link /usr/lib/systemd/system/sddm.service     etc/systemd/system/display-manager.service

link ../choose-mirror.service                   etc/systemd/system/multi-user.target.wants/choose-mirror.service
link ../pacman-init.service                     etc/systemd/system/multi-user.target.wants/pacman-init.service
link /etc/systemd/system/livecd-talk.service    etc/systemd/system/multi-user.target.wants/livecd-talk.service
link ../ifos-fontcache.service                  etc/systemd/system/multi-user.target.wants/ifos-fontcache.service
for u in sshd.service ModemManager.service \
         hv_fcopy_daemon.service hv_kvp_daemon.service hv_vss_daemon.service \
         vboxservice.service vmtoolsd.service vmware-vmblock-fuse.service \
         systemd-resolved.service NetworkManager.service bluetooth.service \
         power-profiles-daemon.service; do
    link "/usr/lib/systemd/system/$u" "etc/systemd/system/multi-user.target.wants/$u"
done

link /usr/lib/systemd/system/NetworkManager-wait-online.service \
     etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service
link /usr/lib/systemd/system/pcscd.socket   etc/systemd/system/sockets.target.wants/pcscd.socket
link ../livecd-alsa-unmuter.service         etc/systemd/system/sound.target.wants/livecd-alsa-unmuter.service
link /usr/lib/systemd/system/systemd-timesyncd.service      etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service
link /usr/lib/systemd/system/systemd-time-wait-sync.service etc/systemd/system/sysinit.target.wants/systemd-time-wait-sync.service

# Executable bits do not survive a zip either.
chmod 755 "$A"/usr/local/bin/{install-ifos,ifos-software,ifos-welcome,ifos-post-install,ifos-theme,ifos-launcher,ifos-bigpicture,ifos-update,ifos-update-terminal,ifos-term,ifos-lock,ifos-gpu,ifos-controller,ifos-mouse,ifos-scale,install-yay,choose-mirror,Installation_guide,livecd-sound} 2>/dev/null || true
chmod 755 "$A"/usr/share/ifos/{post-install.sh,branding-sync.sh} 2>/dev/null || true
chmod 755 "$A"/etc/skel/.config/i3/scripts/*.sh "$A"/etc/skel/.config/picom/launch.sh "$A"/etc/skel/.config/polybar/launch.sh "$A"/etc/skel/.config/polybar/scripts/*.sh \
          "$A"/etc/skel/.config/rofi/*.sh "$A"/etc/skel/.xinitrc 2>/dev/null || true
chmod 755 "$A"/root/.automated_script.sh 2>/dev/null || true
# The build tooling itself needs to stay executable too.
chmod 755 "$PROFILE"/build.sh "$PROFILE"/tools/*.sh "$PROFILE"/tools/*.py 2>/dev/null || true
# NB: shadow/gshadow/sudoers stay world-readable *in the profile* - the build
# runs unprivileged and must be able to read them. profiledef.sh applies the
# real 0400/0440 modes inside the image.
chmod 644 "$A"/etc/shadow "$A"/etc/gshadow "$A"/etc/sudoers.d/10-ifos-live 2>/dev/null || true

if (( changed )); then
    echo "==> symlinks repaired"
else
    echo "==> symlinks are intact"
fi
