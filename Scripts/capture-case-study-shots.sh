#!/usr/bin/env bash
#
# capture-case-study-shots.sh — the iPhone pair for the portfolio case study
# (zantos.co → Headroom, "ON THE PHONE").
#
# Why this is not `capture-demo-screenshots.sh`: that script shoots the App Store sets
# with `--demo`, which stamps a "Demo Mode — sample data, no accounts are connected"
# banner on Usage and forces Settings to read `Status: Demo data` / `Source: Built-in
# sample`. Correct for the App Store; wrong for the case study, whose caption promises
# "the sync settings beside them" — the proof is the Mac→iPhone mirror, so a
# no-accounts-connected banner would contradict the story it illustrates.
#
# So this uses the DEBUG preview-seed path (`HEADROOM_PREVIEW=1`) instead. Same locked
# demo scenario numbers (Claude 38/72/54, Codex 64/91, spend $142.67 / $58.90 — see
# CompanionPreviewSeed), but rendered as ordinary synced content: no banner, and Settings
# reports `Source: Mac snapshot`.
#
# Both shots are headless — no Simulator GUI, no screen takeover, no UI automation.
# Settings opens via `HEADROOM_PREVIEW_SCREEN=settings`, pinned to the `.large` detent so
# the sheet reads as a settled opaque screen rather than a half-height sheet over a dimmed
# Usage background.
#
# Usage:  Scripts/capture-case-study-shots.sh [output-dir]
#         (default output dir: ~/Desktop/headroom-case-study-shots)

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-$HOME/Desktop/headroom-case-study-shots}"
IOS_BUNDLE="com.kylezantos.headroom.ios"
mkdir -p "$OUT"

# iPhone 16 Pro (not Pro Max): its 1206x2622 screen is exactly the 201/437 aspect the
# portfolio's `lib/case-study-assets.ts` already declares for ios-usage / ios-settings,
# so refreshed captures drop in without touching the asset manifest's aspect ratios.
PHONE_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
PHONE_SIM_NAME="Headroom Case Study 16 Pro"
RUNTIME="$(xcrun simctl list runtimes 2>/dev/null | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-26[0-9-]*' | tail -1)"
[ -z "$RUNTIME" ] && { echo "✗ No iOS 26 simulator runtime installed (needed for Headroom's iOS target)." >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 \
  || { echo "✗ ffmpeg is required to flatten the PNG alpha channel." >&2; exit 1; }

echo "▸ Output → $OUT"

UDID="$(xcrun simctl list devices | grep "$PHONE_SIM_NAME (" | grep -oE '[0-9A-Fa-f-]{36}' | head -1 || true)"
if [ -z "$UDID" ]; then
  UDID="$(xcrun simctl create "$PHONE_SIM_NAME" "$PHONE_DEVICE_TYPE" "$RUNTIME")"
  echo "▸ created $PHONE_SIM_NAME ($UDID) on $RUNTIME"
fi

echo "▸ building HeadroomIOS (Debug — the preview seed is compiled out of Release)…"
xcodebuild build \
  -project Headroom.xcodeproj \
  -scheme HeadroomIOS \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath .build/ios-case-study \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -quiet
APP_PATH="$(find .build/ios-case-study/Build/Products -maxdepth 3 -name 'HeadroomIOS.app' | head -1)"
[ -z "$APP_PATH" ] && { echo "✗ build produced no HeadroomIOS.app" >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b || true
xcrun simctl install "$UDID" "$APP_PATH"
# The case study ships dark-mode only.
xcrun simctl ui "$UDID" appearance dark 2>/dev/null || true

shoot() {   # $1 = output path, $2… = extra SIMCTL_CHILD_ env assignments
  local output="$1"; shift
  xcrun simctl terminate "$UDID" "$IOS_BUNDLE" 2>/dev/null || true
  sleep 1
  xcrun simctl status_bar "$UDID" override \
    --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3
  # HEADROOM_UI_TEST_RESET_DEMO clears any persisted app-group demo flag, which would
  # otherwise win over the preview seed in `refresh()` and bring the banner back.
  env SIMCTL_CHILD_HEADROOM_PREVIEW=1 \
      SIMCTL_CHILD_HEADROOM_UI_TEST_RESET_DEMO=1 \
      "$@" \
      xcrun simctl launch "$UDID" "$IOS_BUNDLE" >/dev/null
  sleep 8   # content settles, sheet finishes presenting, first-boot system banner clears
  xcrun simctl io "$UDID" screenshot "$output"
  local opaque="${output%.png}-opaque.png"
  ffmpeg -loglevel error -i "$output" -vf format=rgb24 -y "$opaque"
  mv "$opaque" "$output"
  echo "  ✓ $output ($(sips -g pixelWidth -g pixelHeight "$output" | awk '/pixel/ {printf "%s ", $2}'))"
}

echo "▸ capturing Usage…"
shoot "$OUT/ios-usage.png"
echo "▸ capturing Settings…"
shoot "$OUT/ios-settings.png" SIMCTL_CHILD_HEADROOM_PREVIEW_SCREEN=settings

cat <<EOF

────────────────────────────────────────────────────────────────────────────
Next (portfolio repo):
  cwebp -q 90 "$OUT/ios-usage.png"    -o public/images/projects/case-study/headroom/ios-usage.webp
  cwebp -q 90 "$OUT/ios-settings.png" -o public/images/projects/case-study/headroom/ios-settings.webp
  rm -rf .next/cache/images   # overwriting in place otherwise serves stale optimized bytes
  pnpm check-case-study-assets
────────────────────────────────────────────────────────────────────────────
EOF
