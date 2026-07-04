#!/bin/bash
# Build, Developer ID sign, notarize, staple, and package Headroom for website distribution.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Headroom.app"
DIST_DIR="dist"
WORK_DIR="${DIST_DIR}/release-work"
APP_ZIP="${WORK_DIR}/Headroom-app-notary.zip"
DEFAULT_SPARKLE_UPDATES_DIR="${DIST_DIR}/headroom.zantos.co"
LATEST_DMG_NAME="Headroom.dmg"
HEADROOM_DEVELOPER_ID_APPLICATION="${HEADROOM_DEVELOPER_ID_APPLICATION:-}"
HEADROOM_NOTARY_PROFILE="${HEADROOM_NOTARY_PROFILE:-}"
HEADROOM_APPLE_ID="${HEADROOM_APPLE_ID:-}"
HEADROOM_TEAM_ID="${HEADROOM_TEAM_ID:-}"
HEADROOM_APP_SPECIFIC_PASSWORD="${HEADROOM_APP_SPECIFIC_PASSWORD:-}"
HEADROOM_APP_GROUP_IDENTIFIER="${HEADROOM_APP_GROUP_IDENTIFIER:-}"
HEADROOM_SPARKLE_FEED_URL="${HEADROOM_SPARKLE_FEED_URL:-https://headroom.zantos.co/appcast.xml}"
HEADROOM_SPARKLE_PUBLIC_ED_KEY="${HEADROOM_SPARKLE_PUBLIC_ED_KEY:-VkSwNYbBn5WJUbqYFyhewIFZt4DIfCwiWmTNiGGDorM=}"
HEADROOM_SPARKLE_UPDATES_DIR="${HEADROOM_SPARKLE_UPDATES_DIR:-${DEFAULT_SPARKLE_UPDATES_DIR}}"
HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX="${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX:-}"

usage() {
  cat >&2 <<'EOF'
Usage: ./Scripts/release-app.sh

Required:
  - A Developer ID Application certificate installed in Keychain.
  - Notary credentials, provided either as:
      HEADROOM_NOTARY_PROFILE=<keychain-profile>
    or:
      HEADROOM_APPLE_ID=<apple-id>
      HEADROOM_TEAM_ID=<team-id>
      HEADROOM_APP_SPECIFIC_PASSWORD=<app-specific-password>

Optional:
  HEADROOM_DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)"
  HEADROOM_APP_GROUP_IDENTIFIER="TEAMID.com.kylezantos.headroom"
  HEADROOM_SPARKLE_UPDATES_DIR="dist/headroom.zantos.co"
  HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX="https://headroom.zantos.co/"

Defaults for public releases with in-app update prompts:
  HEADROOM_SPARKLE_FEED_URL="https://headroom.zantos.co/appcast.xml"
  HEADROOM_SPARKLE_PUBLIC_ED_KEY="<base64-public-key-from-Sparkle-generate_keys>"

One-time notary profile setup:
  xcrun notarytool store-credentials headroom-notary \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "<app-specific-password>"

Then:
  HEADROOM_NOTARY_PROFILE=headroom-notary ./Scripts/release-app.sh
EOF
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 69
  fi
}

find_sparkle_tool() {
  local tool="$1"
  local candidate
  candidate="$(find .xcode-derived/SourcePackages .build -path "*/bin/${tool}" -type f 2>/dev/null | head -n 1 || true)"
  if [[ -z "${candidate}" ]]; then
    echo "Missing Sparkle tool: ${tool}" >&2
    echo "Build once so SwiftPM resolves Sparkle, then rerun this script." >&2
    exit 69
  fi
  printf '%s\n' "${candidate}"
}

detach_dmg_mount() {
  hdiutil detach "${DMG_MOUNT_DIR}" -force >/dev/null 2>&1 || true
}

create_drag_install_dmg() {
  rm -f "${DMG_RW_PATH}" "${DMG_PATH}"
  rm -rf "${DMG_MOUNT_DIR}"
  mkdir -p "${DMG_MOUNT_DIR}"

  echo "→ creating writable installer image"
  hdiutil create \
    -volname "Headroom" \
    -srcfolder "${STAGING_DIR}" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "${DMG_RW_PATH}" >/dev/null

  echo "→ styling DMG install window"
  hdiutil attach "${DMG_RW_PATH}" \
    -mountpoint "${DMG_MOUNT_DIR}" \
    -readwrite \
    -noverify \
    -nobrowse >/dev/null
  trap detach_dmg_mount RETURN

  osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "Headroom"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 760, 460}

    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 13

    set position of item "Headroom.app" to {170, 165}
    set position of item "Applications" to {390, 165}

    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

  sync
  detach_dmg_mount
  trap - RETURN

  echo "→ compressing installer image"
  hdiutil convert "${DMG_RW_PATH}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG_PATH}" >/dev/null
  rm -f "${DMG_RW_PATH}"
}

select_developer_id_application() {
  if [[ -n "${HEADROOM_DEVELOPER_ID_APPLICATION}" ]]; then
    printf '%s\n' "${HEADROOM_DEVELOPER_ID_APPLICATION}"
    return
  fi

  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^.*"\(Developer ID Application:[^"]*\)".*$/\1/p' \
    | head -n 1
}

for tool in security codesign ditto hdiutil xcrun plutil; do
  require_tool "${tool}"
done

DEVELOPER_ID_APPLICATION="$(select_developer_id_application)"
if [[ -z "${DEVELOPER_ID_APPLICATION}" ]]; then
  echo "No Developer ID Application identity found in Keychain." >&2
  echo "Install one from your Apple Developer account, then rerun this script." >&2
  exit 65
fi

DEVELOPER_ID_TEAM_ID="$(printf '%s\n' "${DEVELOPER_ID_APPLICATION}" | sed -n 's/.*(\([A-Z0-9][A-Z0-9]*\))$/\1/p')"
if [[ -z "${DEVELOPER_ID_TEAM_ID}" ]]; then
  echo "Couldn't derive Team ID from Developer ID Application identity:" >&2
  echo "  ${DEVELOPER_ID_APPLICATION}" >&2
  echo "Set HEADROOM_APP_GROUP_IDENTIFIER explicitly and rerun." >&2
  exit 65
fi
if [[ -z "${HEADROOM_APP_GROUP_IDENTIFIER}" ]]; then
  HEADROOM_APP_GROUP_IDENTIFIER="${DEVELOPER_ID_TEAM_ID}.com.kylezantos.headroom"
fi
if [[ -z "${HEADROOM_SPARKLE_FEED_URL}" || -z "${HEADROOM_SPARKLE_PUBLIC_ED_KEY}" ]]; then
  echo "Sparkle release configuration is required before building a public DMG." >&2
  echo "Set HEADROOM_SPARKLE_FEED_URL, then rerun." >&2
  exit 64
fi
if [[ -z "${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX}" ]]; then
  HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX="${HEADROOM_SPARKLE_FEED_URL%/*}/"
fi

notary_args=()
if [[ -n "${HEADROOM_NOTARY_PROFILE}" ]]; then
  notary_args=(--keychain-profile "${HEADROOM_NOTARY_PROFILE}")
elif [[ -n "${HEADROOM_APPLE_ID}" && -n "${HEADROOM_TEAM_ID}" && -n "${HEADROOM_APP_SPECIFIC_PASSWORD}" ]]; then
  notary_args=(
    --apple-id "${HEADROOM_APPLE_ID}"
    --team-id "${HEADROOM_TEAM_ID}"
    --password "${HEADROOM_APP_SPECIFIC_PASSWORD}"
  )
else
  usage
  exit 64
fi

echo "→ building Developer ID signed app"
HEADROOM_CODESIGN_IDENTITY="${DEVELOPER_ID_APPLICATION}" \
HEADROOM_CODESIGN_OPTIONS="--timestamp --options runtime" \
HEADROOM_APP_GROUP_IDENTIFIER="${HEADROOM_APP_GROUP_IDENTIFIER}" \
HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1 \
HEADROOM_SPARKLE_FEED_URL="${HEADROOM_SPARKLE_FEED_URL}" \
HEADROOM_SPARKLE_PUBLIC_ED_KEY="${HEADROOM_SPARKLE_PUBLIC_ED_KEY}" \
  ./Scripts/build-app.sh release

echo "→ verifying signed app bundle"
codesign --verify --deep --strict --verbose=2 "${APP}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Contents/Info.plist")"
DMG_NAME="Headroom-${VERSION}-${BUILD}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
DMG_RW_PATH="${WORK_DIR}/Headroom-${VERSION}-${BUILD}-rw.dmg"
DMG_MOUNT_DIR="${WORK_DIR}/dmg-mount"
STAGING_DIR="${WORK_DIR}/dmg-root"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${STAGING_DIR}" "${DIST_DIR}"

echo "→ creating app notarization archive"
ditto -c -k --keepParent "${APP}" "${APP_ZIP}"

echo "→ notarizing app bundle archive"
xcrun notarytool submit "${APP_ZIP}" "${notary_args[@]}" --wait

echo "→ stapling app bundle"
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"
spctl -a -vvv -t open --context context:primary-signature "${APP}"

echo "→ assembling DMG"
ditto "${APP}" "${STAGING_DIR}/${APP}"
ln -s /Applications "${STAGING_DIR}/Applications"
create_drag_install_dmg

echo "→ signing DMG"
codesign --force --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"

echo "→ notarizing DMG"
xcrun notarytool submit "${DMG_PATH}" "${notary_args[@]}" --wait

echo "→ stapling DMG"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
spctl -a -vvv -t open --context context:primary-signature "${DMG_PATH}"

echo "→ signing Sparkle update archive"
SPARKLE_SIGN_UPDATE="$(find_sparkle_tool sign_update)"
"${SPARKLE_SIGN_UPDATE}" "${DMG_PATH}" > "${DMG_PATH}.sparkle-signature.txt"

if [[ -n "${HEADROOM_SPARKLE_UPDATES_DIR}" ]]; then
  echo "→ updating Sparkle appcast"
  SPARKLE_GENERATE_APPCAST="$(find_sparkle_tool generate_appcast)"
  LATEST_DMG_PATH="${HEADROOM_SPARKLE_UPDATES_DIR}/${LATEST_DMG_NAME}"
  mkdir -p "${HEADROOM_SPARKLE_UPDATES_DIR}"
  rm -f "${LATEST_DMG_PATH}"
  ditto "${DMG_PATH}" "${HEADROOM_SPARKLE_UPDATES_DIR}/${DMG_NAME}"
  "${SPARKLE_GENERATE_APPCAST}" \
    --download-url-prefix "${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX}" \
    "${HEADROOM_SPARKLE_UPDATES_DIR}"
  ditto "${DMG_PATH}" "${LATEST_DMG_PATH}"
fi

echo "✓ Release artifact ready: ${DMG_PATH}"
echo "  Website assets: ${HEADROOM_SPARKLE_UPDATES_DIR}"
echo "  Download link: https://headroom.zantos.co/${LATEST_DMG_NAME}"
echo "  Sparkle signature: ${DMG_PATH}.sparkle-signature.txt"
