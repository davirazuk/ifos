#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  IFOS post-install — re-apply IFOS defaults on an installed system.
#
#  install-ifos already does all of this during installation. Run this by hand
#  if you installed with `install-ifos --advanced` (plain archinstall), or to
#  restore the IFOS look after something overwrote it.
#
#  Run as your normal user, not root.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

c_reset=$'\033[0m'; c_blue=$'\033[1;34m'; c_grn=$'\033[1;32m'; c_yel=$'\033[1;33m'
info() { printf '%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$c_grn"  "$c_reset" "$*"; }
warn() { printf '%s  !%s %s\n' "$c_yel"  "$c_reset" "$*"; }

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user (it uses sudo where it needs to)." >&2
    exit 1
fi

info "IFOS post-install setup"

# ── IFOS branding into the system, then into this account ────────────────────
if [[ -x /usr/share/ifos/branding-sync.sh ]]; then
    sudo /usr/share/ifos/branding-sync.sh / && ok "System branding applied"
fi

if [[ -d /etc/skel ]]; then
    cp -rn /etc/skel/. "$HOME/" 2>/dev/null
    ok "Dotfiles copied from /etc/skel (existing files were kept)"
fi

xdg-user-dirs-update && ok "User directories created"

# ── Shell ────────────────────────────────────────────────────────────────────
if command -v fish >/dev/null && [[ $SHELL != *fish ]]; then
    if chsh -s "$(command -v fish)"; then
        ok "Default shell set to fish"
    else
        warn "Could not change the shell; run: chsh -s $(command -v fish)"
    fi
fi

# ── Services ─────────────────────────────────────────────────────────────────
info "Enabling services…"
for svc in NetworkManager bluetooth sddm systemd-timesyncd; do
    sudo systemctl enable "$svc" >/dev/null 2>&1 && ok "enabled $svc"
done
sudo systemctl enable fstrim.timer >/dev/null 2>&1

# ── Theming ──────────────────────────────────────────────────────────────────
if command -v papirus-folders >/dev/null; then
    sudo papirus-folders -C blue --theme Papirus-Dark >/dev/null 2>&1 \
        && ok "Papirus folder colour set"
fi

# ── Mirrors ──────────────────────────────────────────────────────────────────
if command -v reflector >/dev/null; then
    info "Ranking mirrors (this takes a moment)…"
    sudo reflector --latest 20 --sort rate --protocol https \
        --save /etc/pacman.d/mirrorlist >/dev/null 2>&1 \
        && ok "Mirror list updated" || warn "reflector failed; keeping current mirrors"
fi

cat <<EOF

${c_grn}✓ IFOS post-install complete${c_reset}

  Install applications   ifos-software      (or Mod+Shift+A)
  Enable AUR access      install-yay
  Keyboard shortcuts     Mod+F1

  Log out and back in for the shell and theme changes to take effect.

EOF
