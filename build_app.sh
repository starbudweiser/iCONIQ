#!/bin/bash
# Compile iCONIQ.app (release), avec son icône, ses langues et la signature stable, et l'installe dans
# ~/Applications/Applications Personnelles. Usage : ./build_app.sh   (NO_INSTALL=1 : ne pas installer ; VERSION=x.y.z)
set -euo pipefail
cd "$(dirname "$0")"

TOOLS=/Volumes/SKYRIM/TOOLS
DEST="${ICONIQ_INSTALL_DIR:-$HOME/Applications/Applications Personnelles}"
VERSION="${VERSION:-1.0.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# Socle et modules communs : copies reprises à chaque build.
[ -f "$TOOLS/DESIGN/Socle/swift/Socle.swift" ] && cp "$TOOLS/DESIGN/Socle/swift/Socle.swift" Sources/iCONIQ/Socle.swift
[ -f "$TOOLS/MAC/_tools/shared/Updater.swift" ] && cp "$TOOLS/MAC/_tools/shared/Updater.swift" "$TOOLS/MAC/_tools/shared/UpdaterView.swift" Sources/iCONIQ/

if [ ! -f assets/iCONIQ.icns ]; then
    TMP="$(mktemp -d)"
    swift scripts/make_icon.swift assets/iCONIQ.png
    mkdir "$TMP/i.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s assets/iCONIQ.png --out "$TMP/i.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) assets/iCONIQ.png --out "$TMP/i.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$TMP/i.iconset" -o assets/iCONIQ.icns
    rm -rf "$TMP"
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/iCONIQ"

APP=iCONIQ.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/iCONIQ"
cp assets/iCONIQ.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>iCONIQ</string>
    <key>CFBundleDisplayName</key><string>iCONIQ</string>
    <key>CFBundleIdentifier</key><string>fr.stephan.iconiq</string>
    <key>CFBundleExecutable</key><string>iCONIQ</string>
    <key>CFBundleIconFile</key><string>iCONIQ</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string><string>es</string><string>it</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Starbudweiser</string>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
    <key>NSRemovableVolumesUsageDescription</key><string>iCONIQ importe vos bibliothèques d'icônes depuis vos disques externes.</string>
    <key>CFBundleURLTypes</key><array><dict>
        <key>CFBundleURLName</key><string>fr.stephan.iconiq</string>
        <key>CFBundleURLSchemes</key><array><string>iconiq</string></array>
    </dict></array>
    <key>CFBundleDocumentTypes</key><array><dict>
        <key>CFBundleTypeName</key><string>IconJar</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>CFBundleTypeExtensions</key><array><string>iconjar</string><string>ijlibrary</string><string>iconjarlibrary</string></array>
        <key>LSTypeIsPackage</key><true/>
        <key>LSHandlerRank</key><string>Alternate</string>
    </dict></array>
</dict>
</plist>
PLIST

if [ -x "$TOOLS/MAC/_tools/sign_app.sh" ]; then
    "$TOOLS/MAC/_tools/sign_app.sh" "$APP"
else
    codesign --force --deep --sign - "$APP"   # signature ad hoc hors de ma machine
fi

if [ "${NO_INSTALL:-0}" != 1 ]; then
    mkdir -p "$DEST"
    osascript -e 'tell application id "fr.stephan.iconiq" to quit' 2>/dev/null || true
    rm -rf "$DEST/$APP"
    cp -R "$APP" "$DEST/"
    echo "Installé : $DEST/$APP"
fi
