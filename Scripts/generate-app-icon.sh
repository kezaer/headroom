#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
catalog=Sources/PacemarkApp/Resources/Assets.xcassets/AppIcon.appiconset
art=Resources/Brand/pacemark-icon.svg
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
# Center the 96-unit source tile on the macOS 824/1024 grid.
sed 's/viewBox="0 0 100 100"/viewBox="-9.650485 -9.650485 119.30097 119.30097"/' "$art" > "$staging/mac.svg"
render() {
  local platform="$1" prefix="$2"
  shift 2
  if command -v rsvg-convert >/dev/null; then
    for size in "$@"; do
      rsvg-convert -w "$size" -h "$size" "$staging/$platform.svg" > "$catalog/${prefix}_$size.png"
    done
  else
    swift Scripts/render-icon.swift "$staging/$platform.svg" "$catalog/$prefix" "$@"
  fi
}
render mac icon 16 32 64 128 256 512 1024
app_art=Sources/PacemarkApp/Resources/AppIcon
cp "$art" "$app_art/pacemark-icon.svg"
# Drop the Midnight tile for popover headers and adapt its foreground to the surface.
sed '/<rect /d' "$art" > "$app_art/pacemark-header-dark.svg"
sed 's/#ffffff/#0c1a2e/g' "$app_art/pacemark-header-dark.svg" > "$app_art/pacemark-header-light.svg"
cp Resources/Brand/pacemark-mark.svg Sources/PacemarkApp/Resources/AppIcon/pacemark-mark.svg
