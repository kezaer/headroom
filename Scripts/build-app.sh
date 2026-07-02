#!/bin/bash
# Build UsageBar.app — a menu bar (LSUIElement) app bundle around the SwiftPM binary.
# For local personal use. Finalize signing/notarization in Xcode for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="UsageBar.app"
BIN=".build/${CONFIG}/UsageBar"

echo "→ swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

echo "→ assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
cp "${BIN}" "${APP}/Contents/MacOS/UsageBar"

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>UsageBar</string>
    <key>CFBundleIdentifier</key><string>com.kylezantos.usagebar</string>
    <key>CFBundleName</key><string>UsageBar</string>
    <key>CFBundleDisplayName</key><string>UsageBar</string>
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

# Ad-hoc sign so it launches locally. For persistent Keychain grants across rebuilds,
# re-sign in Xcode with a stable Apple Development identity (see README).
codesign --force --sign - "${APP}" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ Built ${APP}"
echo "  Launch:  open ${APP}    (look for the gauge icon in the menu bar)"
echo "  Quit:    click the icon → Quit"
