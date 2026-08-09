#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  build.sh — builds QobuzDL.apk, a thin WebView wrapper around the Qobuz-DL
#  server that termux-setup.sh installs on the phone.
#
#  Needs: java (javac), curl, unzip, rsvg-convert, keytool (part of the JDK).
#  Everything Android-specific (aapt2, d8, apksigner, android.jar) is fetched
#  into ./sdk/ on first run — no Android Studio, no Gradle.
#
#      ./build.sh            build build/QobuzDL.apk
#      ./build.sh install    build, then `adb install -r` it on a plugged-in phone
#
#  Signed with a throwaway local debug key generated on first run
#  (build/qobuzdl.keystore) — fine for side-loading, not for the Play Store.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

SDK="$HERE/sdk"
BUILD_TOOLS_VER=34.0.0
PLATFORM_VER=android-34
BT="$SDK/build-tools/$BUILD_TOOLS_VER"
PLAT="$SDK/platforms/$PLATFORM_VER/android.jar"
ICON_SVG="$HERE/../../airootfs/usr/share/icons/hicolor/scalable/apps/qobuz-dl-gui.svg"

mkdir -p build

if [[ ! -x "$BT/aapt2" || ! -f "$PLAT" ]]; then
    echo "==> Fetching Android command-line SDK (one-time, ~250 MB)"
    mkdir -p "$SDK"
    if [[ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]]; then
        curl -sL -o /tmp/cmdline-tools.zip \
            "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
        unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-tmp
        mkdir -p "$SDK/cmdline-tools"
        mv /tmp/cmdline-tools-tmp/cmdline-tools "$SDK/cmdline-tools/latest"
        rm -rf /tmp/cmdline-tools-tmp /tmp/cmdline-tools.zip
    fi
    yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" \
        "platforms;$PLATFORM_VER" "build-tools;$BUILD_TOOLS_VER" >/dev/null
fi

echo "==> Icon"
mkdir -p build/res/mipmap-xxxhdpi
rsvg-convert -w 192 -h 192 "$ICON_SVG" -o build/res/mipmap-xxxhdpi/ic_launcher.png

echo "==> Resources (aapt2)"
"$BT/aapt2" compile --dir build/res -o build/res.zip
"$BT/aapt2" link -o build/base.apk \
    -I "$PLAT" \
    --manifest AndroidManifest.xml \
    -R build/res.zip \
    --auto-add-overlay \
    --java build/gen

echo "==> Compiling"
rm -rf build/classes && mkdir -p build/classes
javac --release 8 -classpath "$PLAT" -d build/classes \
    $(find src build/gen -name "*.java")

echo "==> Dexing"
"$BT/d8" --output build/ --min-api 24 $(find build/classes -name "*.class")

echo "==> Packaging"
cp build/base.apk build/app-unsigned.apk
(cd build && zip -q -j app-unsigned.apk classes.dex)
"$BT/zipalign" -f 4 build/app-unsigned.apk build/app-aligned.apk

echo "==> Signing"
if [[ ! -f build/qobuzdl.keystore ]]; then
    keytool -genkeypair -v -keystore build/qobuzdl.keystore -alias qobuzdl \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass qobuzdlgui -keypass qobuzdlgui \
        -dname "CN=Qobuz-DL, OU=IFOS, O=IFOS, L=Dourados, S=MS, C=BR" >/dev/null 2>&1
fi
"$BT/apksigner" sign --ks build/qobuzdl.keystore --ks-pass pass:qobuzdlgui \
    --key-pass pass:qobuzdlgui --out build/QobuzDL.apk build/app-aligned.apk 2>&1 | grep -v WARNING || true

echo "==> build/QobuzDL.apk ready"

if [[ ${1:-} == install ]]; then
    adb install -r build/QobuzDL.apk
fi
