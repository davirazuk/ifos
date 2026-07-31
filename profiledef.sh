#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="ifos"
iso_label="IFOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="IFOS <https://github.com/davirazuk/ifos>"
iso_application="IFOS Live/Install Medium"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

# Modes are applied after airootfs is copied into the image. A trailing slash
# means "recursively". This is what guarantees the scripts stay executable and
# sudoers stays 0440 even if the profile travels as a zip, which strips modes.
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-ifos-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/install-ifos"]="0:0:755"
  ["/usr/local/bin/ifos-software"]="0:0:755"
  ["/usr/local/bin/ifos-welcome"]="0:0:755"
  ["/usr/local/bin/ifos-post-install"]="0:0:755"
  ["/usr/local/bin/install-yay"]="0:0:755"
  ["/usr/share/ifos/post-install.sh"]="0:0:755"
  ["/usr/share/ifos/branding-sync.sh"]="0:0:755"
  ["/etc/skel/.config/polybar/launch.sh"]="0:0:755"
  ["/etc/skel/.config/rofi/powermenu.sh"]="0:0:755"
  ["/etc/skel/.xinitrc"]="0:0:755"
  ["/usr/local/bin/ifos-theme"]="0:0:755"
  ["/usr/local/bin/ifos-launcher"]="0:0:755"
  ["/usr/local/bin/ifos-bigpicture"]="0:0:755"
  ["/etc/skel/.config/polybar/scripts/network.sh"]="0:0:755"
  ["/etc/skel/.config/polybar/scripts/battery.sh"]="0:0:755"
  ["/etc/skel/.config/polybar/scripts/bluetooth.sh"]="0:0:755"
)
