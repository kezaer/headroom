#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--build-only | --install]"
  echo "The default and --build-only assemble and verify Headroom.app."
  echo "--install also backs up, replaces, registers and relaunches /Applications/Headroom.app."
}

case "${1:---build-only}" in
  --build-only|--install) mode="${1:---build-only}" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then usage >&2; exit 2; fi

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export SDKROOT="$DEVELOPER_DIR/SDKs/MacOSX26.5.sdk"
export HEADROOM_DIALKIT=0
if [[ ! -d "$SDKROOT" ]]; then
  echo "Missing Command Line Tools SDK: $SDKROOT" >&2
  exit 1
fi

# Read the macOS host target, which precedes the widgets and iOS targets.
project_value() {
  awk -v key="$1" '
    /^  Headroom:$/ { in_host = 1; next }
    in_host && /^  [^ ]/ { exit }
    in_host && $1 == key ":" { print $2; exit }
  ' project.yml
}
version="$(project_value MARKETING_VERSION)"
build="$(project_value CURRENT_PROJECT_VERSION)"
bundle_id="$(project_value PRODUCT_BUNDLE_IDENTIFIER)"
minimum_system="$(awk '/^  deploymentTarget:$/ { getline; gsub(/"/, "", $2); print $2; exit }' project.yml)"
if [[ -z "$version" || -z "$build" || -z "$bundle_id" || -z "$minimum_system" ]]; then
  echo "Missing macOS bundle metadata in project.yml." >&2
  exit 1
fi

mkdir -p .build
work="$(mktemp -d "$repo/.build/t3-bundle.XXXXXXXX")"
install_stage=""
cleanup() {
  rm -rf -- "$work"
  if [[ -n "$install_stage" && ! -e "$install_stage/previous.app" ]]; then
    rm -rf -- "$install_stage"
  fi
}
trap cleanup EXIT

swift_args=(--scratch-path "$repo/.build/t3-release" -c release --arch arm64 --product Headroom)
/usr/bin/xcrun swift build "${swift_args[@]}"
products="$(/usr/bin/xcrun swift build "${swift_args[@]}" --show-bin-path)"

app="$work/Headroom.app"
contents="$app/Contents"
resources="$contents/Resources"
mkdir -p "$contents/MacOS" "$resources"
cp "$products/Headroom" "$contents/MacOS/"
ditto "$products/Headroom_HeadroomApp.bundle" "$resources/Headroom_HeadroomApp.bundle"
cp Sources/HeadroomApp/Resources/BrandIcons/*.svg "$resources/"

icon_source=Sources/HeadroomApp/Resources/Assets.xcassets/AppIcon.appiconset
iconset="$work/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  cp "$icon_source/icon_$size.png" "$iconset/icon_${size}x${size}.png"
  cp "$icon_source/icon_$((size * 2)).png" "$iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns -o "$resources/AppIcon.icns" "$iconset"

# SwiftPM does not link Sparkle. Generate just the metadata this app needs.
cat > "$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Headroom</string>
  <key>CFBundleExecutable</key><string>Headroom</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Headroom</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version-t3</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>CFBundleVersion</key><string>$build</string>
  <key>HeadroomAppGroupIdentifier</key><string>group.$bundle_id</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key><string>$minimum_system</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Personal use</string>
</dict>
</plist>
EOF
plutil -lint "$contents/Info.plist"
entitlements="$work/Headroom.entitlements"
cp Sources/HeadroomApp/HeadroomApp.entitlements "$entitlements"
/usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.icloud-container-identifiers' "$entitlements"
/usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.ubiquity-kvstore-identifier' "$entitlements"
codesign --force --sign - --entitlements "$entitlements" "$app"
codesign --verify --deep --strict "$app"

replace_app() {
  local replacement="$1" destination="$2" previous="$3"
  if [[ -e "$destination" ]]; then mv -- "$destination" "$previous"; fi
  if ! mv -- "$replacement" "$destination"; then
    if [[ -e "$previous" ]]; then mv -- "$previous" "$destination"; fi
    return 1
  fi
}

replace_app "$app" "$repo/Headroom.app" "$work/previous.app"
echo "Built and verified $repo/Headroom.app ($version-t3, build $build)."
if [[ "$mode" == --build-only ]]; then exit 0; fi

installed=/Applications/Headroom.app
if [[ -e "$installed" ]]; then
  backup_dir="$HOME/Git/headroom-backups"
  mkdir -p "$backup_dir"
  backup="$backup_dir/Headroom-$(date '+%Y%m%d-%H%M%S').app"
  # mkdir fails if a backup already has this name, even under concurrent runs.
  mkdir "$backup"
  ditto "$installed" "$backup"
  echo "Backed up $installed to $backup."
fi

install_stage="$(mktemp -d /Applications/.headroom-install.XXXXXXXX)"
ditto "$repo/Headroom.app" "$install_stage/Headroom.app"
codesign --verify --deep --strict "$install_stage/Headroom.app"
echo "Quitting Headroom before replacing $installed."
/usr/bin/osascript -l JavaScript - "$bundle_id" <<'JXA'
ObjC.import('AppKit');
function run(argv) {
  const running = () => $.NSRunningApplication.runningApplicationsWithBundleIdentifier(argv[0]);
  const apps = running();
  for (let index = 0; index < apps.count; index++) apps.objectAtIndex(index).terminate;
  for (let attempt = 0; attempt < 50 && running().count > 0; attempt++) delay(0.2);
  if (running().count > 0) throw new Error('Headroom did not quit.');
}
JXA

replace_app "$install_stage/Headroom.app" "$installed" "$install_stage/previous.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if ! "$lsregister" -f "$installed" || ! open "$installed"; then
  echo "Could not register or open the new app." >&2
  if [[ -d "$install_stage/previous.app" ]]; then
    replace_app "$install_stage/previous.app" "$installed" "$install_stage/failed.app"
    "$lsregister" -f "$installed"
    open "$installed"
  fi
  exit 1
fi
rm -rf -- "$install_stage/previous.app"
echo "Installed, registered and launched $installed ($version-t3)."
