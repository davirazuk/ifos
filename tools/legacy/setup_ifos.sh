#!/usr/bin/env bash
# Run this from inside your extracted ifos/ profile directory
# Usage: bash setup_ifos.sh

set -e
PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIROOTFS="$PROFILE/airootfs"

echo "==> IFOS setup script running in: $PROFILE"

# ─────────────────────────────────────────────
# 1. Fix os-release
# ─────────────────────────────────────────────
echo "==> [1/8] Fixing os-release..."
cat > "$AIROOTFS/etc/os-release" << 'EOF'
NAME=IFOS
PRETTY_NAME="IFOS Linux"
ID=ifos
ID_LIKE=arch
BUILD_ID=rolling
LOGO=archlinux-logo
HOME_URL="https://github.com/davirazuk"
DOCUMENTATION_URL="https://wiki.archlinux.org/"
SUPPORT_URL="https://bbs.archlinux.org/"
BUG_REPORT_URL="https://github.com/davirazuk/ifos/issues"
EOF

# ─────────────────────────────────────────────
# 2. Fix hostname
# ─────────────────────────────────────────────
echo "==> [2/8] Setting hostname to 'ifos'..."
echo "ifos" > "$AIROOTFS/etc/hostname"

# ─────────────────────────────────────────────
# 3. Add linux-headers for broadcom-wl (DKMS)
# ─────────────────────────────────────────────
echo "==> [3/8] Adding linux-headers to packages.x86_64 (needed by broadcom-wl DKMS)..."
if ! grep -q "^linux-headers$" "$PROFILE/packages.x86_64"; then
    sed -i '/^linux$/a linux-headers' "$PROFILE/packages.x86_64"
    echo "    Added linux-headers."
else
    echo "    Already present, skipping."
fi

# ─────────────────────────────────────────────
# 4. Remove bloat packages
# ─────────────────────────────────────────────
echo "==> [4/8] Removing bloat packages (cloud-init, livecd-talk, brltty, espeakup)..."
BLOAT="cloud-init brltty espeakup livecd-sounds"
for pkg in $BLOAT; do
    if grep -q "^${pkg}$" "$PROFILE/packages.x86_64"; then
        sed -i "/^${pkg}$/d" "$PROFILE/packages.x86_64"
        echo "    Removed: $pkg"
    fi
done

# ─────────────────────────────────────────────
# 5. Add useful missing packages
# ─────────────────────────────────────────────
echo "==> [5/8] Adding useful packages..."
ADDITIONS="
pipewire
pipewire-pulse
wireplumber
xorg-server
xorg-xinit
xorg-xrandr
xorg-xsetroot
xterm
dunst
picom
feh
rofi
polkit
networkmanager
nm-connection-editor
thunar
mousepad
ark
ttf-jetbrains-mono-nerd
papirus-icon-theme
"
for pkg in $ADDITIONS; do
    pkg="$(echo "$pkg" | tr -d '[:space:]')"
    [ -z "$pkg" ] && continue
    if ! grep -q "^${pkg}$" "$PROFILE/packages.x86_64"; then
        echo "$pkg" >> "$PROFILE/packages.x86_64"
        echo "    Added: $pkg"
    else
        echo "    Already present: $pkg"
    fi
done

# ─────────────────────────────────────────────
# 6. Set up live user skeleton dotfiles
# ─────────────────────────────────────────────
echo "==> [6/8] Creating skel dotfiles for live user..."

SKEL="$AIROOTFS/etc/skel"
mkdir -p "$SKEL/.config/i3"
mkdir -p "$SKEL/.config/i3status"
mkdir -p "$SKEL/.config/alacritty"
mkdir -p "$SKEL/.config/fish"
mkdir -p "$SKEL/.config/rofi"
mkdir -p "$SKEL/.config/dunst"

# i3 config
cat > "$SKEL/.config/i3/config" << 'EOF'
# IFOS i3 config

set $mod Mod4

font pango:JetBrainsMono Nerd Font 10

exec --no-startup-id dunst
exec --no-startup-id picom -b
exec --no-startup-id feh --bg-scale /usr/share/backgrounds/ifos.png
exec --no-startup-id nm-applet

# Terminal
bindsym $mod+Return exec alacritty
# Launcher
bindsym $mod+d exec rofi -show drun
# Kill window
bindsym $mod+Shift+q kill
# Reload config
bindsym $mod+Shift+r reload
# Restart i3
bindsym $mod+Shift+e exec i3-msg exit

# Focus
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

# Move
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right

# Splits
bindsym $mod+b split h
bindsym $mod+v split v

# Layouts
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+e layout toggle split
bindsym $mod+f fullscreen toggle

# Floating
bindsym $mod+Shift+space floating toggle
bindsym $mod+space focus mode_toggle
floating_modifier $mod

# Workspaces
set $ws1 "1"
set $ws2 "2"
set $ws3 "3"
set $ws4 "4"
set $ws5 "5"

bindsym $mod+1 workspace number $ws1
bindsym $mod+2 workspace number $ws2
bindsym $mod+3 workspace number $ws3
bindsym $mod+4 workspace number $ws4
bindsym $mod+5 workspace number $ws5

bindsym $mod+Shift+1 move container to workspace number $ws1
bindsym $mod+Shift+2 move container to workspace number $ws2
bindsym $mod+Shift+3 move container to workspace number $ws3
bindsym $mod+Shift+4 move container to workspace number $ws4
bindsym $mod+Shift+5 move container to workspace number $ws5

# Resize mode
mode "resize" {
    bindsym h resize shrink width 10 px or 10 ppt
    bindsym j resize grow height 10 px or 10 ppt
    bindsym k resize shrink height 10 px or 10 ppt
    bindsym l resize grow width 10 px or 10 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

# Bar
bar {
    status_command i3status
    position top
    colors {
        background #1e1e2e
        statusline #cdd6f4
        focused_workspace  #89b4fa #89b4fa #1e1e2e
        active_workspace   #313244 #313244 #cdd6f4
        inactive_workspace #1e1e2e #1e1e2e #6c7086
    }
}

# Gaps
gaps inner 8
gaps outer 4
smart_gaps on

# Borders
default_border pixel 2
client.focused          #89b4fa #89b4fa #1e1e2e #89b4fa #89b4fa
client.unfocused        #313244 #1e1e2e #6c7086 #313244 #313244
EOF

# i3status config
cat > "$SKEL/.config/i3status/config" << 'EOF'
general {
    colors = true
    interval = 5
    color_good = "#a6e3a1"
    color_bad = "#f38ba8"
    color_degraded = "#f9e2af"
}

order += "wireless _first_"
order += "ethernet _first_"
order += "memory"
order += "disk /"
order += "cpu_usage"
order += "volume master"
order += "tztime local"

wireless _first_ {
    format_up = " %essid %quality"
    format_down = " down"
}

ethernet _first_ {
    format_up = " %speed"
    format_down = " down"
}

memory {
    format = " %used / %total"
    threshold_degraded = "1G"
    threshold_critical = "200M"
}

disk "/" {
    format = " %avail"
}

cpu_usage {
    format = " %usage"
}

volume master {
    format = "  %volume"
    format_muted = "  muted"
    device = "default"
    mixer = "Master"
}

tztime local {
    format = " %Y-%m-%d %H:%M"
}
EOF

# Alacritty config
cat > "$SKEL/.config/alacritty/alacritty.toml" << 'EOF'
[window]
padding = { x = 12, y = 10 }
opacity = 0.92
decorations = "full"

[font]
normal = { family = "JetBrainsMono Nerd Font", style = "Regular" }
size = 11.0

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"

[colors.normal]
black   = "#45475a"
red     = "#f38ba8"
green   = "#a6e3a1"
yellow  = "#f9e2af"
blue    = "#89b4fa"
magenta = "#f5c2e7"
cyan    = "#94e2d5"
white   = "#bac2de"

[colors.bright]
black   = "#585b70"
red     = "#f38ba8"
green   = "#a6e3a1"
yellow  = "#f9e2af"
blue    = "#89b4fa"
magenta = "#f5c2e7"
cyan    = "#94e2d5"
white   = "#a6adc8"
EOF

# Fish config
cat > "$SKEL/.config/fish/config.fish" << 'EOF'
# IFOS fish config

set fish_greeting ""

# Prompt
function fish_prompt
    set_color blue
    echo -n (prompt_pwd)
    set_color normal
    echo -n " λ "
end

# Aliases
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias update='sudo pacman -Syu'
alias install='sudo pacman -S'
alias search='pacman -Ss'

# Editor
set -x EDITOR vim
set -x VISUAL vim
EOF

# Rofi config
cat > "$SKEL/.config/rofi/config.rasi" << 'EOF'
configuration {
    modi: "drun,run,window";
    show-icons: true;
    font: "JetBrainsMono Nerd Font 11";
}

@theme "catppuccin-mocha"
EOF

# Dunst config
cat > "$SKEL/.config/dunst/dunstrc" << 'EOF'
[global]
    monitor = 0
    follow = mouse
    width = 300
    height = 100
    origin = top-right
    offset = 10x10
    separator_height = 2
    padding = 10
    horizontal_padding = 10
    frame_width = 2
    frame_color = "#89b4fa"
    font = JetBrainsMono Nerd Font 10
    format = "<b>%s</b>\n%b"
    corner_radius = 6

[urgency_low]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    timeout = 5

[urgency_normal]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    timeout = 8

[urgency_critical]
    background = "#f38ba8"
    foreground = "#1e1e2e"
    timeout = 0
EOF

echo "    Skel dotfiles written."

# ─────────────────────────────────────────────
# 7. Fix /etc/motd with IFOS branding
# ─────────────────────────────────────────────
echo "==> [7/8] Writing custom motd..."
cat > "$AIROOTFS/etc/motd" << 'EOF'

  ██╗███████╗ ██████╗ ███████╗
  ██║██╔════╝██╔═══██╗██╔════╝
  ██║█████╗  ██║   ██║███████╗
  ██║██╔══╝  ██║   ██║╚════██║
  ██║██║     ╚██████╔╝███████║
  ╚═╝╚═╝      ╚═════╝ ╚══════╝
       IFOS Linux — rolling

  Welcome to the IFOS live environment.
  • Connect to Wi-Fi:    iwctl
  • Install IFOS:        archinstall
  • System info:         fastfetch

EOF

# ─────────────────────────────────────────────
# 8. Enable NetworkManager instead of systemd-networkd
#    (better UX for a desktop distro with nm-applet)
# ─────────────────────────────────────────────
echo "==> [8/8] Enabling NetworkManager..."
WANTS="$AIROOTFS/etc/systemd/system/multi-user.target.wants"
mkdir -p "$WANTS"

# Disable systemd-networkd if symlinked
for svc in systemd-networkd.service systemd-resolved.service; do
    if [ -L "$WANTS/$svc" ]; then
        rm "$WANTS/$svc"
        echo "    Removed: $svc"
    fi
done

# Enable NetworkManager
NM_SRC="/usr/lib/systemd/system/NetworkManager.service"
if [ ! -L "$WANTS/NetworkManager.service" ]; then
    ln -sf "$NM_SRC" "$WANTS/NetworkManager.service"
    echo "    Enabled: NetworkManager.service"
fi

# Add NetworkManager to packages if missing
if ! grep -q "^networkmanager$" "$PROFILE/packages.x86_64"; then
    echo "networkmanager" >> "$PROFILE/packages.x86_64"
fi

# ─────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────
echo ""
echo "✓ IFOS profile setup complete."
echo ""
echo "  To build your ISO, run on an Arch host:"
echo "  sudo mkarchiso -v -w /tmp/ifos-work -o /tmp/ifos-out $PROFILE"
echo ""
