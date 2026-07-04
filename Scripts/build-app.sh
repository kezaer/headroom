#!/bin/bash
# Build Headroom.app as a real macOS app with an embedded WidgetKit extension.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG_INPUT="${1:-release}"
case "${CONFIG_INPUT}" in
  debug|Debug) XCODE_CONFIG="Debug" ;;
  release|Release) XCODE_CONFIG="Release" ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 64
    ;;
esac

APP="Headroom.app"
DERIVED_DATA=".xcode-derived"
BUILT_APP="${DERIVED_DATA}/Build/Products/${XCODE_CONFIG}/Headroom.app"
WIDGET_APPEX="${APP}/Contents/PlugIns/HeadroomWidgets.appex"
SIGNING_DIR="${DERIVED_DATA}/Signing"
APP_ENTITLEMENTS="${SIGNING_DIR}/HeadroomApp.entitlements"
WIDGET_ENTITLEMENTS="${SIGNING_DIR}/HeadroomWidgets.entitlements"
SPARKLE_VERSION="2.9.4"
SPARKLE_ARTIFACT_ZIP="${DERIVED_DATA}/SourcePackages/artifacts/sparkle/Sparkle-for-Swift-Package-Manager.zip"
SPARKLE_ARTIFACT_DIR="${DERIVED_DATA}/SourcePackages/artifacts/sparkle/Sparkle"
SPARKLE_ARTIFACT_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"
HEADROOM_CODESIGN_IDENTITY="${HEADROOM_CODESIGN_IDENTITY:-}"
HEADROOM_CODESIGN_OPTIONS="${HEADROOM_CODESIGN_OPTIONS:---timestamp=none}"
HEADROOM_APP_GROUP_IDENTIFIER="${HEADROOM_APP_GROUP_IDENTIFIER:-group.com.kylezantos.headroom}"
HEADROOM_SPARKLE_FEED_URL="${HEADROOM_SPARKLE_FEED_URL:-}"
HEADROOM_SPARKLE_PUBLIC_ED_KEY="${HEADROOM_SPARKLE_PUBLIC_ED_KEY:-VkSwNYbBn5WJUbqYFyhewIFZt4DIfCwiWmTNiGGDorM=}"
read -r -a CODESIGN_OPTIONS <<< "${HEADROOM_CODESIGN_OPTIONS}"

select_codesign_identity() {
  if [[ -n "${HEADROOM_CODESIGN_IDENTITY}" ]]; then
    printf '%s\n' "${HEADROOM_CODESIGN_IDENTITY}"
    return
  fi

  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  local identity
  identity="$(printf '%s\n' "${identities}" | sed -n 's/^.*"\(Apple Development:[^"]*\)".*$/\1/p' | head -n 1)"
  if [[ -z "${identity}" ]]; then
    identity="$(printf '%s\n' "${identities}" | sed -n 's/^.*"\(Developer ID Application:[^"]*\)".*$/\1/p' | head -n 1)"
  fi

  printf '%s\n' "${identity:--}"
}

sign_path() {
  local path="$1"
  shift
  codesign --force --sign "${CODESIGN_IDENTITY}" "${CODESIGN_OPTIONS[@]}" "$@" "${path}"
}

prepare_sparkle_artifact() {
  if [[ -d "${SPARKLE_ARTIFACT_DIR}/Sparkle.xcframework" ]]; then
    return
  fi

  echo "→ fetching Sparkle ${SPARKLE_VERSION}"
  mkdir -p "$(dirname "${SPARKLE_ARTIFACT_ZIP}")" "${SPARKLE_ARTIFACT_DIR}"
  curl -L --fail --show-error --silent \
    -o "${SPARKLE_ARTIFACT_ZIP}" \
    "${SPARKLE_ARTIFACT_URL}"
  ditto -x -k "${SPARKLE_ARTIFACT_ZIP}" "${SPARKLE_ARTIFACT_DIR}"
}

prepare_entitlements() {
  mkdir -p "${SIGNING_DIR}"
  cp Sources/HeadroomApp/HeadroomApp.entitlements "${APP_ENTITLEMENTS}"
  cp Sources/HeadroomWidgets/HeadroomWidgets.entitlements "${WIDGET_ENTITLEMENTS}"
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 ${HEADROOM_APP_GROUP_IDENTIFIER}" "${APP_ENTITLEMENTS}"
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 ${HEADROOM_APP_GROUP_IDENTIFIER}" "${WIDGET_ENTITLEMENTS}"
}

stamp_app_group_info() {
  for plist in \
    "${APP}/Contents/Info.plist" \
    "${WIDGET_APPEX}/Contents/Info.plist"
  do
    /usr/libexec/PlistBuddy -c "Set :HeadroomAppGroupIdentifier ${HEADROOM_APP_GROUP_IDENTIFIER}" "${plist}" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :HeadroomAppGroupIdentifier string ${HEADROOM_APP_GROUP_IDENTIFIER}" "${plist}"
  done
}

stamp_sparkle_info() {
  local plist="${APP}/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL ${HEADROOM_SPARKLE_FEED_URL}" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${HEADROOM_SPARKLE_FEED_URL}" "${plist}"
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${HEADROOM_SPARKLE_PUBLIC_ED_KEY}" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${HEADROOM_SPARKLE_PUBLIC_ED_KEY}" "${plist}"
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks true" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "${plist}"
  /usr/libexec/PlistBuddy -c "Set :SUAllowsAutomaticUpdates false" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUAllowsAutomaticUpdates bool false" "${plist}"
}

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to build the WidgetKit-discoverable app bundle." >&2
  echo "Install with: brew install xcodegen" >&2
  exit 69
fi

CODESIGN_IDENTITY="$(select_codesign_identity)"
prepare_sparkle_artifact

echo "→ xcodegen generate"
xcodegen generate

echo "→ xcodebuild Headroom (${XCODE_CONFIG}, unsigned product)"
xcodebuild \
  -project Headroom.xcodeproj \
  -scheme Headroom \
  -configuration "${XCODE_CONFIG}" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  HEADROOM_APP_GROUP_IDENTIFIER="${HEADROOM_APP_GROUP_IDENTIFIER}" \
  HEADROOM_SPARKLE_FEED_URL="${HEADROOM_SPARKLE_FEED_URL}" \
  HEADROOM_SPARKLE_PUBLIC_ED_KEY="${HEADROOM_SPARKLE_PUBLIC_ED_KEY}" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "→ assembling ${APP}"
rm -rf "${APP}"
ditto "${BUILT_APP}" "${APP}"
prepare_entitlements
stamp_app_group_info
stamp_sparkle_info

# Interrupted codesign runs can leave temporary files inside the bundle. Remove them
# before sealing, or codesign treats the temp file as a malformed nested component.
find "${APP}" -name '*.cstemp' -delete

if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
  echo "→ codesign ad-hoc (set HEADROOM_CODESIGN_IDENTITY to use an Apple certificate)"
else
  echo "→ codesign with ${CODESIGN_IDENTITY}"
fi
echo "→ codesign options: ${HEADROOM_CODESIGN_OPTIONS}"
echo "→ app group: ${HEADROOM_APP_GROUP_IDENTIFIER}"

while IFS= read -r dylib; do
  sign_path "${dylib}"
done < <(find "${APP}" -type f -name '*.dylib')

while IFS= read -r framework; do
  sign_path "${framework}" --deep
done < <(find "${APP}/Contents/Frameworks" -maxdepth 1 -type d -name '*.framework' 2>/dev/null)

sign_path "${WIDGET_APPEX}" --entitlements "${WIDGET_ENTITLEMENTS}"
sign_path "${APP}" --entitlements "${APP_ENTITLEMENTS}"
codesign --verify --deep --strict --verbose=2 "${APP}"

echo "✓ Built ${APP}"
echo "  Launch:  open ${APP}    (look for the vessel icon in the menu bar)"
echo "  Quit:    click the icon → Quit"
