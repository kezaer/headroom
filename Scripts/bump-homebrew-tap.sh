#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tag=${1:-}
tap=${2:?Usage: bump-homebrew-tap.sh vX.Y.Z path-to-kezaer-tap}
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
case "$(git -C "$tap" remote get-url origin)" in
  https://github.com/kezaer/homebrew-tap[.]git|https://github.com/kezaer/homebrew-tap|git@github.com:kezaer/homebrew-tap.git) ;;
  *) echo "Wrong tap origin" >&2; exit 1 ;;
esac
Scripts/release.sh promote "$tag"
curl -fsSL --retry 4 https://kezaer.github.io/pacemark/appcast.xml | cmp dist/pages/appcast.xml -
version=${tag#v}
public=".xcode-derived/release/$tag/$(git rev-parse HEAD)/public"
sha=$(shasum -a 256 "$public/Pacemark-$version.dmg" | awk '{print $1}')
mkdir -p "$tap/Casks"
candidate=$(mktemp)
trap 'rm -f "$candidate"' EXIT
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha/" packaging/homebrew/pacemark.rb > "$candidate"
if [[ -n $(git -C "$tap" status --porcelain -- Casks/pacemark.rb) ]]; then
  cmp "$candidate" "$tap/Casks/pacemark.rb" || { echo "Cask contains unrelated edits" >&2; exit 1; }
else
  cp "$candidate" "$tap/Casks/pacemark.rb"
fi
brew audit --cask kezaer/tap/pacemark
git -C "$tap" add Casks/pacemark.rb
if ! git -C "$tap" diff --cached --quiet -- Casks/pacemark.rb; then
  git -C "$tap" commit -m "Update Pacemark to $version" -- Casks/pacemark.rb
fi
git -C "$tap" push origin HEAD
