#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  termux-setup.sh — installs the Qobuz-DL backend inside Termux, so QobuzDL.apk
#  (a thin WebView wrapper, see build.sh) has something to point at.
#
#  Run this once, inside Termux, on the phone:
#
#      curl -sL https://raw.githubusercontent.com/davirazuk/ifos/main/mobile/qobuz-dl-android/termux-setup.sh | bash
#
#  It also installs a Termux:Boot script so the backend restarts automatically
#  after a reboot — install the Termux:Boot app too (F-Droid or GitHub
#  releases: github.com/termux/termux-boot) and open it once so Android grants
#  it the RECEIVE_BOOT_COMPLETED permission, or the boot script never runs.
#
#  Same story as the desktop qobuz-dl-gui launcher (usr/local/bin/qobuz-dl-gui):
#  pinned to a known-good upstream commit, patched with gtk-and-pwa.patch
#  (the GTK part is inert here — no window system in Termux, and gui_app.py's
#  QOBUZ_DL_GUI_BROWSER=1 path never imports pywebview in the first place).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_URL=https://github.com/peykc/qobuz-dl-gui.git
PIN_COMMIT=032c566ed61d2bb353a8d9bc7af24292f9dc0022
RAW_BASE=https://raw.githubusercontent.com/davirazuk/ifos/main/airootfs/usr/share/ifos/qobuz-dl-gui
INSTALL_DIR="$HOME/qobuz-dl-gui"

echo "==> Instalando pacotes"
pkg update -y
pkg install -y python git python-cryptography

echo "==> Clonando qobuz-dl-gui (commit fixo)"
rm -rf "$INSTALL_DIR"
git clone --quiet "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"
git checkout --quiet "$PIN_COMMIT"

echo "==> Aplicando o patch do IFOS (GTK/PWA/mobile)"
curl -sL "$RAW_BASE/gtk-and-pwa.patch" -o "$HOME/gtk-and-pwa.patch"
git apply "$HOME/gtk-and-pwa.patch"

mkdir -p qobuz_dl/gui/icons
curl -sL "$RAW_BASE/manifest.json" -o qobuz_dl/gui/manifest.json
curl -sL "$RAW_BASE/sw.js" -o qobuz_dl/gui/sw.js
for f in icon-192.png icon-512.png apple-touch-icon.png favicon-32.png; do
    curl -sL "$RAW_BASE/icons/$f" -o "qobuz_dl/gui/icons/$f"
done

echo "==> Instalando dependências Python"
pip install --quiet -r requirements.txt

echo "==> Configurando início automático (Termux:Boot)"
mkdir -p "$HOME/.termux/boot"
cat > "$HOME/.termux/boot/start-qobuz-dl.sh" << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
cd "$HOME/qobuz-dl-gui"
QOBUZ_DL_GUI_BROWSER=1 QOBUZ_DL_GUI_PORT=8765 nohup python -m qobuz_dl.gui_app > "$HOME/qobuz-dl.log" 2>&1 &
BOOTEOF
chmod +x "$HOME/.termux/boot/start-qobuz-dl.sh"

echo "==> Iniciando agora"
bash "$HOME/.termux/boot/start-qobuz-dl.sh"
sleep 2
echo "==> Pronto. Instale QobuzDL.apk (build.sh) e abra o app — ele já aponta para http://127.0.0.1:8765/."
