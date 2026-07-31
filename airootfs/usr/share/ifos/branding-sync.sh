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
SRC=/                                  # where we are copying *from*
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

# Look and feel
copy /usr/share/backgrounds/ifos.png
copy /usr/share/sddm/themes/ifos
copy /etc/sddm.conf.d/ifos.conf
copy /usr/share/plymouth/themes/ifos
copy /etc/plymouth/plymouthd.conf

# Distribution identity
copy /etc/os-release
copy /usr/share/ifos/apps.d
copy /usr/share/ifos/keybindings.txt
copy /usr/share/ifos/post-install.sh   0755
copy /usr/share/ifos/branding-sync.sh  0755
copy /usr/share/ifos/archinstall-preset.json

# Tools
for t in ifos-software ifos-welcome ifos-post-install install-yay; do
    copy "/usr/local/bin/$t" 0755
done

# Applications menu entries
copy /usr/share/applications/ifos-software.desktop
copy /usr/share/applications/ifos-welcome.desktop

echo "==> Done"
