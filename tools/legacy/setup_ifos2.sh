#!/usr/bin/env bash
# setup_ifos2.sh — Run from inside your ifos/ profile directory AFTER setup_ifos.sh
set -e
PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIROOTFS="$PROFILE/airootfs"
SKEL="$AIROOTFS/etc/skel"

echo ""
echo "  ██╗███████╗ ██████╗ ███████╗"
echo "  ██║██╔════╝██╔═══██╗██╔════╝"
echo "  ██║█████╗  ██║   ██║███████╗"
echo "  ██║██╔══╝  ██║   ██║╚════██║"
echo "  ██║██║     ╚██████╔╝███████║"
echo "  ╚═╝╚═╝      ╚═════╝ ╚══════╝"
echo "   IFOS setup2.sh — full build"
echo ""

# ─────────────────────────────────────────────
# 1. Additional packages
# ─────────────────────────────────────────────
echo "==> [1/11] Adding packages..."
ADDITIONS="
polybar
plymouth
python-gobject
noto-fonts
noto-fonts-emoji
ttf-font-awesome
xdg-user-dirs
adw-gtk3
qt5ct
kvantum
xsettingsd
pamixer
brightnessctl
playerctl
network-manager-applet
blueman
maim
xclip
xdotool
papirus-folders
"
for pkg in $ADDITIONS; do
    pkg="$(echo "$pkg" | tr -d '[:space:]')"
    [ -z "$pkg" ] && continue
    if ! grep -q "^${pkg}$" "$PROFILE/packages.x86_64" 2>/dev/null; then
        echo "$pkg" >> "$PROFILE/packages.x86_64"
        echo "    Added: $pkg"
    else
        echo "    Already present: $pkg"
    fi
done

# ─────────────────────────────────────────────
# 2. Trim rescue-only packages (keep desktop lean)
# ─────────────────────────────────────────────
echo "==> [2/11] Trimming rescue-only packages..."
RESCUE_BLOAT="clonezilla partclone partimage ddrescue fsarchiver gpart hdparm sdparm sg3_utils smartmontools testdisk dmraid mdadm bcachefs-tools nilfs-utils udftools jfsutils open-iscsi nbd mtools lsscsi lvm2 fatresize dosfstools exfatprogs f2fs-tools xfsprogs btrfs-progs e2fsprogs ntfs-3g"
for pkg in $RESCUE_BLOAT; do
    if grep -q "^${pkg}$" "$PROFILE/packages.x86_64" 2>/dev/null; then
        sed -i "/^${pkg}$/d" "$PROFILE/packages.x86_64"
        echo "    Removed rescue tool: $pkg"
    fi
done

# ─────────────────────────────────────────────
# 3. Generate wallpaper with Python
# ─────────────────────────────────────────────
echo "==> [3/11] Generating wallpaper..."
mkdir -p "$AIROOTFS/usr/share/backgrounds"
python3 << 'PYEOF'
import sys, math
try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    print("    PIL not available, skipping wallpaper generation")
    sys.exit(0)

import os
W, H = 1920, 1080

# Catppuccin Mocha palette
BG      = (30,  30,  46)   # base
CRUST   = (17,  17,  27)
MANTLE  = (24,  24,  37)
BLUE    = (137, 180, 250)
MAUVE   = (203, 166, 247)
LAVENDER= (180, 190, 254)
SURFACE = (49,  50,  68)

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

# Gradient background (top crust -> bottom base)
for y in range(H):
    t = y / H
    r = int(CRUST[0] + (BG[0]-CRUST[0]) * t)
    g = int(CRUST[1] + (BG[1]-CRUST[1]) * t)
    b = int(CRUST[2] + (BG[2]-CRUST[2]) * t)
    draw.line([(0,y),(W,y)], fill=(r,g,b))

# Grid lines (subtle)
GRID = (SURFACE[0], SURFACE[1], SURFACE[2])
for x in range(0, W, 60):
    draw.line([(x,0),(x,H)], fill=(*GRID, 30), width=1)
for y in range(0, H, 60):
    draw.line([(0,y),(W,y)], fill=(*GRID, 30), width=1)

# Glow circles
def draw_glow(draw, cx, cy, r, color, steps=12):
    for i in range(steps, 0, -1):
        alpha = int(8 * i / steps)
        rad = int(r + (steps - i) * 18)
        draw.ellipse([cx-rad, cy-rad, cx+rad, cy+rad],
                     fill=(*color, alpha))

overlay = Image.new("RGBA", (W, H), (0,0,0,0))
odraw = ImageDraw.Draw(overlay)
draw_glow(odraw, W//3, H//2, 80, BLUE)
draw_glow(odraw, 2*W//3, H//3, 60, MAUVE)
draw_glow(odraw, W//2, 3*H//4, 50, LAVENDER)

base_rgba = img.convert("RGBA")
base_rgba = Image.alpha_composite(base_rgba, overlay)
img = base_rgba.convert("RGB")
draw = ImageDraw.Draw(img)

# Decorative rings
def ring(draw, cx, cy, r, color, width=1):
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], outline=color, width=width)

ring(draw, W//2, H//2, 220, (*SURFACE, 60), 1)
ring(draw, W//2, H//2, 300, (*SURFACE, 40), 1)
ring(draw, W//2, H//2, 380, (*SURFACE, 25), 1)

# IFOS text — drawn as large block pixels (no font needed)
# We draw it using rectangles to spell out IFOS in a pixel-art style
def pixel_char(draw, char, ox, oy, scale, color):
    glyphs = {
        'I': [(1,0),(1,1),(1,2),(1,3),(1,4),(0,0),(2,0),(0,4),(2,4)],
        'F': [(0,0),(1,0),(2,0),(0,1),(0,2),(1,2),(0,3),(0,4)],
        'O': [(1,0),(2,0),(0,1),(3,1),(0,2),(3,2),(0,3),(3,3),(1,4),(2,4)],
        'S': [(1,0),(2,0),(3,0),(0,1),(1,2),(2,2),(3,3),(0,4),(1,4),(2,4)],
        ' ': [],
    }
    pixels = glyphs.get(char.upper(), [])
    for (px, py) in pixels:
        x0 = ox + px * scale
        y0 = oy + py * scale
        draw.rectangle([x0, y0, x0+scale-2, y0+scale-2], fill=color)

scale = 26
chars = "IFOS"
total_w = len(chars) * (4 * scale + 10) - 10
start_x = (W - total_w) // 2
start_y = H // 2 - 2 * scale

for i, c in enumerate(chars):
    cx = start_x + i * (4 * scale + 10)
    # Shadow
    pixel_char(draw, c, cx+3, start_y+3, scale, (10, 10, 20))
    # Main glyph
    color = [BLUE, MAUVE, LAVENDER, BLUE][i]
    pixel_char(draw, c, cx, start_y, scale, color)

# Tagline dots
for i, dot_color in enumerate([BLUE, MAUVE, LAVENDER, BLUE, MAUVE]):
    x = W//2 - 40 + i*20
    y = start_y + 6*scale + 10
    draw.ellipse([x-3, y-3, x+3, y+3], fill=dot_color)

# Subtle vignette
vignette = Image.new("RGBA", (W, H), (0,0,0,0))
vdraw = ImageDraw.Draw(vignette)
steps = 70
for s in range(steps):
    t = s / steps
    alpha = int(120 * (t ** 1.5))
    pad = s * 7
    if pad >= W//2 or pad >= H//2:
        break
    vdraw.rectangle([pad, pad, W-pad, H-pad], outline=(0,0,0,alpha), width=1)
img_rgba = img.convert("RGBA")
img_final = Image.alpha_composite(img_rgba, vignette).convert("RGB")

out = os.environ.get("WALLPAPER_OUT", "/tmp/ifos/airootfs/usr/share/backgrounds/ifos.png")
img_final.save(out, "PNG", optimize=True)
print(f"    Wallpaper saved to {out}")
PYEOF

# ─────────────────────────────────────────────
# 4. Fastfetch config
# ─────────────────────────────────────────────
echo "==> [4/11] Writing fastfetch config..."
mkdir -p "$SKEL/.config/fastfetch"
cat > "$SKEL/.config/fastfetch/config.jsonc" << 'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "builtin",
    "source": "arch",
    "color": {
      "1": "blue",
      "2": "cyan"
    },
    "padding": { "top": 1, "left": 2 }
  },
  "display": {
    "separator": "  ",
    "color": { "keys": "blue" }
  },
  "modules": [
    { "type": "title", "fqdn": false },
    "separator",
    { "type": "os",     "key": " OS",      "keyColor": "blue" },
    { "type": "kernel", "key": " Kernel",  "keyColor": "blue" },
    { "type": "uptime", "key": "󱑍 Uptime",  "keyColor": "blue" },
    { "type": "shell",  "key": " Shell",   "keyColor": "mauve" },
    { "type": "wm",     "key": " WM",      "keyColor": "mauve" },
    { "type": "terminal","key": " Term",   "keyColor": "mauve" },
    { "type": "cpu",    "key": " CPU",     "keyColor": "green" },
    { "type": "gpu",    "key": "󰍹 GPU",    "keyColor": "green" },
    { "type": "memory", "key": " RAM",     "keyColor": "green" },
    { "type": "disk",   "key": "󰋊 Disk",   "keyColor": "yellow",
      "folders": "/" },
    { "type": "localip","key": "󰩠 IP",     "keyColor": "yellow" },
    "separator",
    { "type": "colors", "symbol": "circle", "paddingLeft": 1 }
  ]
}
EOF

# Also apply to root user in live env
mkdir -p "$AIROOTFS/root/.config/fastfetch"
cp "$SKEL/.config/fastfetch/config.jsonc" "$AIROOTFS/root/.config/fastfetch/config.jsonc"

# ─────────────────────────────────────────────
# 5. Polybar config
# ─────────────────────────────────────────────
echo "==> [5/11] Writing polybar config..."
mkdir -p "$SKEL/.config/polybar"
cat > "$SKEL/.config/polybar/config.ini" << 'EOF'
[colors]
bg         = #1e1e2e
bg-alt     = #313244
fg         = #cdd6f4
fg-dim     = #6c7086
blue       = #89b4fa
mauve      = #cba6f7
green      = #a6e3a1
yellow     = #f9e2af
red        = #f38ba8
cyan       = #94e2d5
lavender   = #b4befe

[bar/main]
monitor        =
width          = 100%
height         = 28
offset-x       = 0
offset-y       = 0
radius         = 0
background     = ${colors.bg}
foreground     = ${colors.fg}
line-size      = 2
padding-left   = 2
padding-right  = 2
module-margin  = 1
separator      = │
separator-foreground = ${colors.bg-alt}
font-0         = JetBrainsMono Nerd Font:size=10;2
font-1         = Font Awesome 6 Free:style=Solid:size=10;2
font-2         = Font Awesome 6 Brands:size=10;2
modules-left   = i3
modules-center = date
modules-right  = network cpu memory volume bluetooth
tray-position  = right
tray-padding   = 4
cursor-click   = pointer
enable-ipc     = true
border-size    = 0

[module/i3]
type                 = internal/i3
format               = <label-state> <label-mode>
index-sort           = true
wrapping-scroll      = false
label-focused        = %index%
label-focused-foreground = ${colors.blue}
label-focused-underline  = ${colors.blue}
label-focused-padding    = 2
label-unfocused          = %index%
label-unfocused-foreground = ${colors.fg-dim}
label-unfocused-padding    = 2
label-visible            = %index%
label-visible-foreground = ${colors.fg-dim}
label-visible-padding    = 2
label-urgent             = %index%
label-urgent-foreground  = ${colors.red}
label-urgent-padding     = 2

[module/date]
type             = internal/date
interval         = 5
date             = %a %d %b
time             = %H:%M
format-prefix    = "  "
format-prefix-foreground = ${colors.mauve}
label            = %date%  %time%

[module/cpu]
type             = internal/cpu
interval         = 2
format-prefix    = " "
format-prefix-foreground = ${colors.green}
label            = %percentage:2%%

[module/memory]
type             = internal/memory
interval         = 3
format-prefix    = " "
format-prefix-foreground = ${colors.blue}
label            = %percentage_used:2%%

[module/network]
type             = internal/network
interface-type   = wireless
interval         = 3
format-connected-prefix    = "󰖩 "
format-connected-prefix-foreground = ${colors.cyan}
label-connected  = %essid%
format-disconnected-prefix = "󰖪 "
format-disconnected-prefix-foreground = ${colors.red}
label-disconnected = offline

[module/volume]
type             = internal/pulseaudio
format-volume-prefix    = "  "
format-volume-prefix-foreground = ${colors.yellow}
label-volume     = %percentage%%
format-muted-prefix     = "  "
format-muted-prefix-foreground = ${colors.fg-dim}
label-muted      = muted

[module/bluetooth]
type             = custom/script
exec             = bluetoothctl show | grep -q "Powered: yes" && echo "󰂯" || echo "󰂲"
interval         = 5
format-foreground = ${colors.mauve}
click-left       = blueman-manager
EOF

cat > "$SKEL/.config/polybar/launch.sh" << 'EOF'
#!/usr/bin/env bash
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.5; done
polybar main 2>&1 | tee -a /tmp/polybar.log & disown
EOF
chmod +x "$SKEL/.config/polybar/launch.sh"

# Update i3 config to use polybar instead of built-in bar
sed -i '/^bar {/,/^}/d' "$SKEL/.config/i3/config" 2>/dev/null || true
cat >> "$SKEL/.config/i3/config" << 'EOF'

# Launch polybar
exec_always --no-startup-id ~/.config/polybar/launch.sh
EOF

# ─────────────────────────────────────────────
# 6. GTK + Qt theming
# ─────────────────────────────────────────────
echo "==> [6/11] Setting up GTK/Qt theming..."
mkdir -p "$SKEL/.config/gtk-3.0"
mkdir -p "$SKEL/.config/gtk-4.0"

cat > "$SKEL/.config/gtk-3.0/settings.ini" << 'EOF'
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans 10
gtk-application-prefer-dark-theme=1
gtk-button-images=0
gtk-menu-images=0
gtk-enable-animations=1
EOF

cat > "$SKEL/.config/gtk-4.0/settings.ini" << 'EOF'
[Settings]
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans 10
gtk-application-prefer-dark-theme=1
EOF

# Qt5 theming via qt5ct
mkdir -p "$SKEL/.config/qt5ct"
cat > "$SKEL/.config/qt5ct/qt5ct.conf" << 'EOF'
[Appearance]
color_scheme_path=
custom_palette=false
icon_theme=Papirus-Dark
standard_dialogs=default
style=Fusion

[Fonts]
fixed=@Variant(\0\0\0@\0\0\0\x16JetBrainsMono Nerd Font\0\0\0\n\0\0\0\0\x32\x7f\0\0\x18)
general=@Variant(\0\0\0@\0\0\0\x12Noto Sans\0\0\0\n\0\0\0\0\x28\x7f\0\0\x14)
EOF

# Set QT_QPA_PLATFORMTHEME in fish
echo 'set -x QT_QPA_PLATFORMTHEME qt5ct' >> "$SKEL/.config/fish/config.fish"
echo 'set -x QT_STYLE_OVERRIDE Fusion' >> "$SKEL/.config/fish/config.fish"

# Also set in bash skeleton
cat >> "$SKEL/.bashrc" << 'EOF'
export QT_QPA_PLATFORMTHEME=qt5ct
export QT_STYLE_OVERRIDE=Fusion
EOF

# ─────────────────────────────────────────────
# 7. SDDM custom theme
# ─────────────────────────────────────────────
echo "==> [7/11] Creating SDDM theme..."
SDDM_THEME="$AIROOTFS/usr/share/sddm/themes/ifos"
mkdir -p "$SDDM_THEME"

# Theme metadata
cat > "$SDDM_THEME/metadata.desktop" << 'EOF'
[SddmGreeterTheme]
Name=IFOS
Description=IFOS Login Theme
Author=davirazuk
Version=1.0
License=MIT
Type=sddm-theme
EOF

# Copy wallpaper into theme
if [ -f "$AIROOTFS/usr/share/backgrounds/ifos.png" ]; then
    cp "$AIROOTFS/usr/share/backgrounds/ifos.png" "$SDDM_THEME/background.png"
fi

# Main QML
cat > "$SDDM_THEME/Main.qml" << 'EOF'
import QtQuick 2.15
import QtQuick.Controls 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    color: "#1e1e2e"

    // Background
    Image {
        anchors.fill: parent
        source: "background.png"
        fillMode: Image.PreserveAspectCrop
    }

    // Dim overlay
    Rectangle {
        anchors.fill: parent
        color: "#1e1e2e"
        opacity: 0.55
    }

    // Center login card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 360
        height: 340
        radius: 16
        color: "#1e1e2e"
        border.color: "#313244"
        border.width: 1

        Column {
            anchors.centerIn: parent
            spacing: 18
            width: parent.width - 60

            // Logo / distro name
            Text {
                text: "IFOS"
                font.pixelSize: 38
                font.bold: true
                color: "#89b4fa"
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: "JetBrainsMono Nerd Font"
            }

            Text {
                text: "Welcome back"
                font.pixelSize: 13
                color: "#6c7086"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Username field
            TextField {
                id: userField
                width: parent.width
                height: 42
                placeholderText: "Username"
                text: userModel.lastUser
                font.pixelSize: 13
                color: "#cdd6f4"
                background: Rectangle {
                    color: "#313244"
                    radius: 8
                    border.color: userField.activeFocus ? "#89b4fa" : "#45475a"
                    border.width: 1
                }
                leftPadding: 14
                KeyNavigation.tab: passField
                Keys.onReturnPressed: passField.forceActiveFocus()
            }

            // Password field
            TextField {
                id: passField
                width: parent.width
                height: 42
                placeholderText: "Password"
                echoMode: TextInput.Password
                font.pixelSize: 13
                color: "#cdd6f4"
                background: Rectangle {
                    color: "#313244"
                    radius: 8
                    border.color: passField.activeFocus ? "#89b4fa" : "#45475a"
                    border.width: 1
                }
                leftPadding: 14
                Keys.onReturnPressed: loginBtn.clicked()
            }

            // Login button
            Rectangle {
                id: loginBtn
                width: parent.width
                height: 42
                radius: 8
                color: loginMouse.pressed ? "#7ca9f0" : "#89b4fa"
                signal clicked()

                Text {
                    anchors.centerIn: parent
                    text: "Login"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#1e1e2e"
                }

                MouseArea {
                    id: loginMouse
                    anchors.fill: parent
                    onClicked: {
                        sddm.login(userField.text, passField.text, sessionIndex)
                    }
                }

                onClicked: {
                    sddm.login(userField.text, passField.text, sessionIndex)
                }
            }
        }
    }

    // Clock bottom center
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        spacing: 4

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: 42
            font.bold: true
            color: "#cdd6f4"
            font.family: "JetBrainsMono Nerd Font"
        }

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: 14
            color: "#6c7086"
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: {
                var now = new Date()
                timeText.text = Qt.formatTime(now, "hh:mm")
                dateText.text = Qt.formatDate(now, "dddd, MMMM d")
            }
        }

        Component.onCompleted: {
            var now = new Date()
            timeText.text = Qt.formatTime(now, "hh:mm")
            dateText.text = Qt.formatDate(now, "dddd, MMMM d")
        }
    }

    // Session selector (top right)
    ComboBox {
        id: sessionSelect
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        width: 140
        height: 32
        model: sessionModel
        currentIndex: sessionModel.lastIndex
        onCurrentIndexChanged: sessionIndex = currentIndex
        font.pixelSize: 11
        background: Rectangle {
            color: "#313244"
            radius: 6
        }
        contentItem: Text {
            leftPadding: 10
            text: sessionSelect.displayText
            color: "#cdd6f4"
            font: sessionSelect.font
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Power buttons (top left)
    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 16
        spacing: 8

        Rectangle {
            width: 36; height: 36; radius: 8
            color: shutMouse.pressed ? "#f38ba8" : "#313244"
            Text { anchors.centerIn: parent; text: "⏻"; color: "#f38ba8"; font.pixelSize: 16 }
            MouseArea { id: shutMouse; anchors.fill: parent; onClicked: sddm.powerOff() }
        }

        Rectangle {
            width: 36; height: 36; radius: 8
            color: rebootMouse.pressed ? "#f9e2af" : "#313244"
            Text { anchors.centerIn: parent; text: ""; color: "#f9e2af"; font.pixelSize: 14 }
            MouseArea { id: rebootMouse; anchors.fill: parent; onClicked: sddm.reboot() }
        }
    }

    Component.onCompleted: passField.forceActiveFocus()
}
EOF

# Point SDDM at our theme
mkdir -p "$AIROOTFS/etc/sddm.conf.d"
cat > "$AIROOTFS/etc/sddm.conf.d/ifos.conf" << 'EOF'
[Theme]
Current=ifos
CursorTheme=Adwaita
CursorSize=24

[Autologin]
Relogin=false
EOF

# ─────────────────────────────────────────────
# 8. Plymouth boot splash
# ─────────────────────────────────────────────
echo "==> [8/11] Configuring Plymouth..."
mkdir -p "$AIROOTFS/etc/plymouth"
cat > "$AIROOTFS/etc/plymouth/plymouthd.conf" << 'EOF'
[Daemon]
Theme=spinner
ShowDelay=0
EOF

# Add plymouth to mkinitcpio HOOKS
MKINIT="$AIROOTFS/etc/mkinitcpio.conf.d/archiso.conf"
if ! grep -q "plymouth" "$MKINIT" 2>/dev/null; then
    sed -i 's/udev/udev plymouth/' "$MKINIT" 2>/dev/null || true
    echo "    Added plymouth hook to mkinitcpio"
fi

# Add quiet splash to boot entries
for entry in "$PROFILE/efiboot/loader/entries/"*.conf; do
    if grep -q "options" "$entry" && ! grep -q "splash" "$entry"; then
        sed -i 's/options .*/& quiet splash plymouth.use-simpledrm=1/' "$entry"
        echo "    Updated boot entry: $(basename "$entry")"
    fi
done

# ─────────────────────────────────────────────
# 9. Custom GRUB menu
# ─────────────────────────────────────────────
echo "==> [9/11] Updating GRUB/syslinux menu labels..."
if [ -f "$PROFILE/grub/grub.cfg" ]; then
    sed -i "s/Arch Linux/IFOS Linux/g" "$PROFILE/grub/grub.cfg"
    sed -i "s/Arch Linux/IFOS Linux/g" "$PROFILE/grub/loopback.cfg" 2>/dev/null || true
    echo "    GRUB labels updated"
fi
if [ -f "$PROFILE/syslinux/archiso_sys-linux.cfg" ]; then
    sed -i "s/Arch Linux/IFOS Linux/g" "$PROFILE/syslinux/"*.cfg 2>/dev/null || true
    echo "    Syslinux labels updated"
fi

# ─────────────────────────────────────────────
# 10. Archinstall preset
# ─────────────────────────────────────────────
echo "==> [10/11] Writing archinstall preset..."
mkdir -p "$AIROOTFS/usr/share/ifos"
cat > "$AIROOTFS/usr/share/ifos/archinstall-preset.json" << 'EOF'
{
  "additional-repositories": ["multilib"],
  "archinstall-language": "English",
  "audio_config": {
    "audio": "pipewire"
  },
  "bootloader": "Grub",
  "profile_config": {
    "profile": {
      "classtype": "WindowManager",
      "selected_profiles": ["i3"]
    },
    "gfx_driver": "All open-source (default)"
  },
  "packages": [
    "alacritty", "fish", "firefox", "polybar", "picom", "rofi",
    "dunst", "feh", "thunar", "fastfetch", "git", "vim",
    "networkmanager", "network-manager-applet", "bluez", "bluez-utils",
    "blueman", "pipewire", "pipewire-pulse", "wireplumber",
    "ttf-jetbrains-mono-nerd", "noto-fonts", "noto-fonts-emoji",
    "ttf-font-awesome", "papirus-icon-theme", "adw-gtk3",
    "steam", "xdg-user-dirs", "pamixer", "brightnessctl", "maim",
    "xclip", "reflector", "sudo"
  ],
  "services": [
    "NetworkManager", "bluetooth", "sddm", "reflector"
  ],
  "swap": true,
  "timezone": "UTC",
  "mirror_config": {
    "mirror_regions": {}
  }
}
EOF

# Script to launch archinstall with preset
cat > "$AIROOTFS/usr/local/bin/install-ifos" << 'EOF'
#!/usr/bin/env bash
echo ""
echo "  Starting IFOS installer..."
echo "  Using preset: /usr/share/ifos/archinstall-preset.json"
echo ""
archinstall --config /usr/share/ifos/archinstall-preset.json
EOF
chmod +x "$AIROOTFS/usr/local/bin/install-ifos"

# Update motd to mention install-ifos
sed -i 's/archinstall/install-ifos/' "$AIROOTFS/etc/motd" 2>/dev/null || true

# ─────────────────────────────────────────────
# 11. Post-install script + yay installer
# ─────────────────────────────────────────────
echo "==> [11/11] Writing post-install and yay scripts..."
mkdir -p "$AIROOTFS/usr/share/ifos"

# yay installer (run as normal user)
cat > "$AIROOTFS/usr/local/bin/install-yay" << 'EOF'
#!/usr/bin/env bash
set -e
if command -v yay &>/dev/null; then
    echo "yay is already installed."
    exit 0
fi
echo "==> Installing yay (AUR helper)..."
sudo pacman -S --needed git base-devel
cd /tmp
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
cd /
rm -rf /tmp/yay-bin
echo "✓ yay installed. Use 'yay -S <package>' to install AUR packages."
EOF
chmod +x "$AIROOTFS/usr/local/bin/install-yay"

# Post-install script (run after archinstall, inside new system)
cat > "$AIROOTFS/usr/share/ifos/post-install.sh" << 'POSTEOF'
#!/usr/bin/env bash
# IFOS post-install script
# Run this after archinstall as your normal user (not root)
set -e

echo "==> IFOS post-install setup..."

# xdg dirs
xdg-user-dirs-update

# Set fish as default shell
if command -v fish &>/dev/null; then
    chsh -s "$(which fish)"
    echo "    Default shell set to fish"
fi

# Set up dotfiles
CONFIG="$HOME/.config"
mkdir -p "$CONFIG/i3" "$CONFIG/polybar" "$CONFIG/alacritty" \
         "$CONFIG/fish" "$CONFIG/rofi" "$CONFIG/dunst" "$CONFIG/fastfetch"

# Pull IFOS dotfiles if they exist on github, else copy from skel
if [ -d /etc/skel/.config ]; then
    cp -rn /etc/skel/.config/. "$CONFIG/"
    echo "    Dotfiles copied from /etc/skel"
fi

# Enable services
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
sudo systemctl enable --now sddm
echo "    Services enabled"

# Set up papirus folder colors
if command -v papirus-folders &>/dev/null; then
    papirus-folders -C blue --theme Papirus-Dark
    echo "    Papirus folder colors set"
fi

# Reflector (update mirrors)
echo "    Updating mirrors with reflector..."
sudo reflector --latest 20 --sort rate --protocol https \
    --save /etc/pacman.d/mirrorlist

echo ""
echo "✓ IFOS post-install complete!"
echo "  Install yay with:  install-yay"
echo "  Then reboot."
POSTEOF
chmod +x "$AIROOTFS/usr/share/ifos/post-install.sh"

# Make post-install accessible from PATH in live env
cp "$AIROOTFS/usr/share/ifos/post-install.sh" "$AIROOTFS/usr/local/bin/ifos-post-install"
chmod +x "$AIROOTFS/usr/local/bin/ifos-post-install"

# ─────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────
echo ""
echo "✓ IFOS full setup complete!"
echo ""
echo "  Summary of what was done:"
echo "  [1] Added polybar, plymouth, fonts, GTK/Qt tools, blueman, maim"
echo "  [2] Trimmed ~18 rescue-only packages (btrfs-progs, clonezilla, etc.)"
echo "  [3] Generated Catppuccin wallpaper → airootfs/usr/share/backgrounds/ifos.png"
echo "  [4] Fastfetch config with Nerd Font icons"
echo "  [5] Polybar with i3 workspaces, cpu/ram/net/vol/bt/clock"
echo "  [6] GTK3/4 dark theme (adw-gtk3-dark) + Papirus-Dark icons + Qt5 theming"
echo "  [7] Custom SDDM theme (ifos) with clock, session picker, power buttons"
echo "  [8] Plymouth boot splash configured (spinner theme)"
echo "  [9] GRUB/syslinux menus renamed to 'IFOS Linux'"
echo " [10] archinstall preset + 'install-ifos' command"
echo " [11] 'install-yay' + 'ifos-post-install' scripts"
echo ""
echo "  To build:"
echo "  sudo mkarchiso -v -w /tmp/ifos-work -o /tmp/ifos-out $PROFILE"
echo ""
