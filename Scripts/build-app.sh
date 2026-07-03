#!/bin/bash
# Build Headroom.app — a menu bar (LSUIElement) app bundle around the SwiftPM binary.
# For local personal use. Finalize signing/notarization in Xcode for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="Headroom.app"
BIN=".build/${CONFIG}/Headroom"
WIDGET_BIN=".build/${CONFIG}/HeadroomWidgets"
RESOURCE_BUNDLE=".build/${CONFIG}/Headroom_HeadroomApp.bundle"
WIDGET_APPEX="${APP}/Contents/PlugIns/HeadroomWidgets.appex"

echo "→ swift build -c ${CONFIG}"
swift build -c "${CONFIG}"
echo "→ swift build -c ${CONFIG} --product HeadroomWidgets"
swift build -c "${CONFIG}" --product HeadroomWidgets

echo "→ assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
mkdir -p "${WIDGET_APPEX}/Contents/MacOS"
cp "${BIN}" "${APP}/Contents/MacOS/Headroom"
cp "${WIDGET_BIN}" "${WIDGET_APPEX}/Contents/MacOS/HeadroomWidgets"
if [[ -d "${RESOURCE_BUNDLE}" ]]; then
  find "${RESOURCE_BUNDLE}" -maxdepth 1 -type f \( -name '*.svg' -o -name 'SOURCES.md' \) -exec cp {} "${APP}/Contents/Resources/" \;
fi

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Headroom</string>
    <key>CFBundleIdentifier</key><string>com.kylezantos.headroom</string>
    <key>CFBundleName</key><string>Headroom</string>
    <key>CFBundleDisplayName</key><string>Headroom</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <!-- Menu bar only: no Dock icon, no app-switcher entry. -->
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Personal use</string>
</dict>
</plist>
PLIST

cat > "${WIDGET_APPEX}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>HeadroomWidgets</string>
    <key>CFBundleIdentifier</key><string>com.kylezantos.headroom.widgets</string>
    <key>CFBundleName</key><string>HeadroomWidgets</string>
    <key>CFBundleDisplayName</key><string>Headroom</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

# Ad-hoc sign so it launches locally. For persistent Keychain grants across rebuilds,
# re-sign in Xcode with a stable Apple Development identity (see README).
codesign --force --sign - --entitlements Sources/HeadroomWidgets/HeadroomWidgets.entitlements "${WIDGET_APPEX}" >/dev/null 2>&1 || echo "  (widget codesign skipped)"
codesign --force --sign - --entitlements Sources/HeadroomApp/HeadroomApp.entitlements "${APP}" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ Built ${APP}"
echo "  Launch:  open ${APP}    (look for the gauge icon in the menu bar)"
echo "  Quit:    click the icon → Quit"
