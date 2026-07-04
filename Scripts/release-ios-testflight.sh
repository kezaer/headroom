#!/bin/bash
# Archive HeadroomIOS for App Store Connect/TestFlight and optionally upload it.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="Headroom.xcodeproj"
SCHEME="${HEADROOM_IOS_SCHEME:-HeadroomIOS}"
CONFIGURATION="${HEADROOM_IOS_CONFIGURATION:-Release}"
TEAM_ID="${HEADROOM_TEAM_ID:-8D42S4MS38}"
DIST_DIR="${HEADROOM_IOS_DIST_DIR:-dist/ios-testflight}"
ARCHIVE_PATH="${HEADROOM_IOS_ARCHIVE_PATH:-${DIST_DIR}/HeadroomIOS.xcarchive}"
EXPORT_PATH="${HEADROOM_IOS_EXPORT_PATH:-${DIST_DIR}/export}"
EXPORT_OPTIONS_TEMPLATE="${HEADROOM_IOS_EXPORT_OPTIONS:-Scripts/ExportOptions-TestFlight.plist}"
UPLOAD="${HEADROOM_IOS_UPLOAD:-0}"

ASC_KEY_PATH="${HEADROOM_ASC_KEY_PATH:-}"
ASC_KEY_ID="${HEADROOM_ASC_KEY_ID:-}"
ASC_ISSUER_ID="${HEADROOM_ASC_ISSUER_ID:-}"

if [[ "${UPLOAD}" == "1" ]]; then
  EXPORT_DESTINATION="upload"
else
  EXPORT_DESTINATION="export"
fi

auth_args=()
if [[ -n "${ASC_KEY_PATH}" || -n "${ASC_KEY_ID}" || -n "${ASC_ISSUER_ID}" ]]; then
  if [[ -z "${ASC_KEY_PATH}" || -z "${ASC_KEY_ID}" || -z "${ASC_ISSUER_ID}" ]]; then
    echo "Set HEADROOM_ASC_KEY_PATH, HEADROOM_ASC_KEY_ID, and HEADROOM_ASC_ISSUER_ID together." >&2
    exit 64
  fi
  auth_args=(
    -authenticationKeyPath "${ASC_KEY_PATH}"
    -authenticationKeyID "${ASC_KEY_ID}"
    -authenticationKeyIssuerID "${ASC_ISSUER_ID}"
  )
fi

mkdir -p "${DIST_DIR}" "${EXPORT_PATH}"
GENERATED_EXPORT_OPTIONS="${DIST_DIR}/ExportOptions.generated.plist"
cp "${EXPORT_OPTIONS_TEMPLATE}" "${GENERATED_EXPORT_OPTIONS}"
/usr/libexec/PlistBuddy -c "Set :destination ${EXPORT_DESTINATION}" "${GENERATED_EXPORT_OPTIONS}"
/usr/libexec/PlistBuddy -c "Set :teamID ${TEAM_ID}" "${GENERATED_EXPORT_OPTIONS}"

echo "→ archiving ${SCHEME} for App Store Connect"
archive_command=(
  xcodebuild
  -project "${PROJECT}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination 'generic/platform=iOS'
  -archivePath "${ARCHIVE_PATH}"
  -allowProvisioningUpdates
  archive
)
if [[ ${#auth_args[@]} -gt 0 ]]; then
  archive_command+=("${auth_args[@]}")
fi
"${archive_command[@]}"

echo "→ exporting archive (${EXPORT_DESTINATION})"
export_command=(
  xcodebuild
  -exportArchive
  -archivePath "${ARCHIVE_PATH}"
  -exportPath "${EXPORT_PATH}"
  -exportOptionsPlist "${GENERATED_EXPORT_OPTIONS}"
  -allowProvisioningUpdates
)
if [[ ${#auth_args[@]} -gt 0 ]]; then
  export_command+=("${auth_args[@]}")
fi
"${export_command[@]}"

if [[ "${UPLOAD}" == "1" ]]; then
  echo "✓ Uploaded archive to App Store Connect for TestFlight processing."
else
  echo "✓ Exported TestFlight IPA: ${EXPORT_PATH}/Headroom.ipa"
  echo "  Set HEADROOM_IOS_UPLOAD=1 to upload instead of exporting locally."
fi
