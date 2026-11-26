#!/bin/bash
# Build Pacemark.app as a real macOS app.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/macos-compatibility.sh
source Scripts/codesign-identity.sh

CONFIG_INPUT="${1:-release}"
# `--deps-only` prepares the vendored dependencies the Xcode project expects on disk
# and stops there. `-resolvePackageDependencies` does not unpack the Sparkle
# XCFramework, so a fresh checkout can't build the PacemarkAppTests scheme until this
# has run once.
DEPS_ONLY=0
case "${CONFIG_INPUT}" in
  --deps-only|prepare-deps) DEPS_ONLY=1; XCODE_CONFIG="Release" ;;
  debug|Debug) XCODE_CONFIG="Debug" ;;
  release|Release) XCODE_CONFIG="Release" ;;
  *)
    echo "Usage: $0 [debug|release|--deps-only]" >&2
    exit 64
    ;;
esac

APP="Pacemark.app"
DERIVED_DATA=".xcode-derived"
BUILT_APP="${DERIVED_DATA}/Build/Products/${XCODE_CONFIG}/Pacemark.app"
SPARKLE_VERSION="2.9.4"
SPARKLE_ARTIFACT_ZIP="${DERIVED_DATA}/SourcePackages/artifacts/sparkle/Sparkle-for-Swift-Package-Manager.zip"
SPARKLE_ARTIFACT_DIR="${DERIVED_DATA}/SourcePackages/artifacts/sparkle/Sparkle"
SPARKLE_ARTIFACT_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"
PACEMARK_CODESIGN_IDENTITY="${PACEMARK_CODESIGN_IDENTITY:-}"
PACEMARK_CODESIGN_OPTIONS="${PACEMARK_CODESIGN_OPTIONS:---timestamp=none}"
PACEMARK_SPARKLE_FEED_URL="${PACEMARK_SPARKLE_FEED_URL:-https://kezaer.github.io/pacemark/appcast.xml}"
PACEMARK_SPARKLE_PUBLIC_ED_KEY="${PACEMARK_SPARKLE_PUBLIC_ED_KEY:-CgeUbW5ihDn1NxWqJ1TW4lGPhb7lg5uuyEquG+bD8AA=}"
read -r -a CODESIGN_OPTIONS <<< "${PACEMARK_CODESIGN_OPTIONS}"

select_codesign_identity() {
  if [[ -n "${PACEMARK_CODESIGN_IDENTITY}" ]]; then
    # A name may match a renewed certificate too; sign with the newest one's SHA-1.
    local resolved=""
    if [[ "${PACEMARK_CODESIGN_IDENTITY}" != "-" && ! "${PACEMARK_CODESIGN_IDENTITY}" =~ ^[0-9A-Fa-f]{40}$ ]]; then
      resolved="$(pacemark_newest_identity_sha "${PACEMARK_CODESIGN_IDENTITY}")"
    fi
    printf '%s\n' "${resolved:-${PACEMARK_CODESIGN_IDENTITY}}"
    return
  fi

  printf '%s\n' '-'
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
  echo "cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0  ${SPARKLE_ARTIFACT_ZIP}" | shasum -a 256 -c -
  ditto -x -k "${SPARKLE_ARTIFACT_ZIP}" "${SPARKLE_ARTIFACT_DIR}"
}

stamp_sparkle_info() {
  local plist="${APP}/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL ${PACEMARK_SPARKLE_FEED_URL}" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${PACEMARK_SPARKLE_FEED_URL}" "${plist}"
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${PACEMARK_SPARKLE_PUBLIC_ED_KEY}" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${PACEMARK_SPARKLE_PUBLIC_ED_KEY}" "${plist}"
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks true" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "${plist}"
  /usr/libexec/PlistBuddy -c "Set :SUAllowsAutomaticUpdates true" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUAllowsAutomaticUpdates bool true" "${plist}"
  # Bundle default only: Sparkle preserves the user's explicit choice in UserDefaults.
  /usr/libexec/PlistBuddy -c "Set :SUAutomaticallyUpdate false" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool false" "${plist}"
}

if [[ "${DEPS_ONLY}" == "1" ]]; then
  prepare_sparkle_artifact
  echo "✓ Sparkle ${SPARKLE_VERSION} ready at ${SPARKLE_ARTIFACT_DIR}/Sparkle.xcframework"
  echo "  Run tests with: xcodebuild -project Pacemark.xcodeproj -scheme PacemarkAppTests \\"
  echo "    -destination 'platform=macOS' -derivedDataPath ./${DERIVED_DATA} test"
  exit 0
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to build the app bundle." >&2
  echo "Install with: brew install xcodegen" >&2
  exit 69
fi

CODESIGN_IDENTITY="$(select_codesign_identity)"
prepare_sparkle_artifact

echo "→ xcodegen generate"
xcodegen generate

echo "→ xcodebuild Pacemark (${XCODE_CONFIG}, unsigned product)"
xcodebuild \
  -project Pacemark.xcodeproj \
  -scheme Pacemark \
  -configuration "${XCODE_CONFIG}" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  PACEMARK_SPARKLE_FEED_URL="${PACEMARK_SPARKLE_FEED_URL}" \
  PACEMARK_SPARKLE_PUBLIC_ED_KEY="${PACEMARK_SPARKLE_PUBLIC_ED_KEY}" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "→ assembling ${APP}"
if [[ -e "${APP}" ]]; then
  ARCHIVE_DIR="${DERIVED_DATA}/ArchivedApps"
  mkdir -p "${ARCHIVE_DIR}"
  ARCHIVED_APP="${ARCHIVE_DIR}/Pacemark.app.$(date +%Y%m%d-%H%M%S)"
  echo "→ archiving existing ${APP} to ${ARCHIVED_APP}"
  mv "${APP}" "${ARCHIVED_APP}"
fi
ditto "${BUILT_APP}" "${APP}"
cp LICENSE NOTICE "${APP}/Contents/Resources/"
stamp_sparkle_info
pacemark_verify_macos_bundle "${APP}"

# Interrupted codesign runs can leave temporary files inside the bundle. Remove them
# before sealing, or codesign treats the temp file as a malformed nested component.
find "${APP}" -name '*.cstemp' -delete

if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
  echo "→ codesign ad-hoc (set PACEMARK_CODESIGN_IDENTITY to use an Apple certificate)"
else
  echo "→ codesign with ${CODESIGN_IDENTITY} (${CODESIGN_IDENTITY:0:8}…)"
fi
echo "→ codesign options: ${PACEMARK_CODESIGN_OPTIONS}"

while IFS= read -r dylib; do
  sign_path "${dylib}"
done < <(find "${APP}" -type f -name '*.dylib')

while IFS= read -r framework; do
  sign_path "${framework}" --deep
done < <(find "${APP}/Contents/Frameworks" -maxdepth 1 -type d -name '*.framework' 2>/dev/null)

sign_path "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"


LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
if [[ -x "${LSREGISTER}" ]]; then
  echo "→ registering ${APP} with LaunchServices"
  "${LSREGISTER}" -f -R -trusted "${APP}"
fi

echo "✓ Built ${APP}"
echo "  Launch:  open ${APP}    (look for the Pacemark gauge in the menu bar)"
echo "  Quit:    click the icon → Quit"
