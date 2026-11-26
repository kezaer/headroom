#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
die() { echo "$*" >&2; exit 1; }
action=${1:-}
tag=${2:-}
candidate=false
test_mode=false
if [[ $# == 3 && $action == package && ( $tag == v0.0.0-test || $tag == v1.0.0-rc1 ) && $3 == --local-test ]]; then
  test_mode=true
elif [[ $# == 3 && $action == package && $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && $3 == --candidate ]]; then
  candidate=true
else
  [[ $# == 2 && $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Usage: release.sh package|publish|promote vX.Y.Z"
fi
repo=kezaer/pacemark
version=${tag#v}
version=${version%-test}
version=${version%-rc1}
name=Pacemark-$version.dmg
prefix=https://github.com/$repo/releases/download/$tag/
feed=https://kezaer.github.io/pacemark/appcast.xml
pub=CgeUbW5ihDn1NxWqJ1TW4lGPhb7lg5uuyEquG+bD8AA=
out="$PWD/dist/$tag"
work="$PWD/.xcode-derived/release/$tag/$(git rev-parse HEAD)"
if $candidate; then
  head=$(git rev-parse HEAD)
  out="$PWD/dist/candidates/$tag/$head"
  work="$PWD/.xcode-derived/release/candidates/$tag/$head"
fi
sparkle=.xcode-derived/SourcePackages/artifacts/sparkle/Sparkle
mkdir -p "$work"
# Serialize use of Xcode derived data and persisted notary receipts in this checkout.
if [[ ${PACEMARK_RELEASE_LOCKED:-} != "$PWD" ]]; then
  exec python3 - "$PWD" "$@" <<'PYLOCK'
import fcntl, os, sys
root, *args = sys.argv[1:]
fd = os.open(os.path.join(root, '.xcode-derived/release/lock'), os.O_CREAT | os.O_RDWR, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
os.set_inheritable(fd, True)
os.environ['PACEMARK_RELEASE_LOCKED'] = root
os.execv('/bin/bash', ['bash', os.path.join(root, 'Scripts/release.sh'), *args])
PYLOCK
fi
if $candidate; then
  [[ -z $(git status --porcelain --untracked-files=normal) ]] || die "Modified candidate checkout"
elif ! $test_mode; then
  [[ $(git rev-parse "refs/tags/$tag^{commit}") == "$(git rev-parse HEAD)" ]] || die "Check out the release tag"
  git diff --quiet HEAD || die "Modified release checkout"
  case "$(git remote get-url origin)" in
    "https://github.com/$repo"|"https://github.com/$repo.git"|"git@github.com:$repo.git") ;;
    *) die "Expected $repo as origin" ;;
  esac
  git fetch --quiet origin HEAD
  git merge-base --is-ancestor HEAD FETCH_HEAD || die "Tag is outside the default branch"
  local_tag=$(git rev-parse "refs/tags/$tag")
  remote_tag=$(git ls-remote --refs origin "refs/tags/$tag" | awk '{print $1}')
  [[ $remote_tag == "$local_tag" ]] || die "Tag differs from origin"
fi

# Validate the public contract again after downloading from the draft or public release.
validate() {
  local dir=$1
  [[ $(cat "$dir/$name.sha256") == "$(cd "$dir" && shasum -a 256 "$name")" ]] || die "Checksum mismatch"
  python3 -I - "$dir/appcast.xml" "$prefix$name" "$dir/$name" "$version" <<'PY'
import base64, os, sys, xml.etree.ElementTree as ET
path, url, dmg, version = sys.argv[1:]
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
item, = ET.parse(path).findall('./channel/item')
enc, = item.findall('enclosure')
assert item.findtext(ns+'shortVersionString') == version
assert int(item.findtext(ns+'version')) > 0
assert item.findtext(ns+'minimumSystemVersion') in ('15', '15.0', '15.0.0')
assert enc.get('url') == url and int(enc.get('length')) == os.path.getsize(dmg)
signature = enc.attrib[ns+'edSignature']
assert len(base64.b64decode(signature, validate=True)) == 64
print(signature)
PY
}

notarize() {
  local input=$1 ticket=$2 id status
  local args=(--keychain-profile pacemark-notary)
  if [[ -n ${ASC_KEY_FILE:-} ]]; then args=(--key "$ASC_KEY_FILE" --issuer "$ASC_ISSUER_ID" --key-id "$ASC_KEY_ID"); fi
  if [[ ! -s $ticket ]]; then
    xcrun notarytool submit "$input" "${args[@]}" --output-format json > "$ticket.tmp"
    jq -er .id "$ticket.tmp"
    mv "$ticket.tmp" "$ticket"
  fi
  id=$(jq -er .id "$ticket")
  xcrun notarytool wait "$id" "${args[@]}" --output-format json > "$ticket.result"
  status=$(jq -er .status "$ticket.result")
  echo "$id $status"
  if [[ $status != Accepted ]]; then
    xcrun notarytool log "$id" "${args[@]}" "$ticket.log"
    die "Apple returned $status. See $ticket.log"
  fi
}

audit_app() {
  local app=$1 path details entitlements
  local framework="Contents/Frameworks/Sparkle.framework/Versions/B"
  local plist="$app/Contents/Info.plist"
  [[ $(plutil -extract SUFeedURL raw "$plist") == "$feed" ]]
  [[ $(plutil -extract SUPublicEDKey raw "$plist") == "$pub" ]]
  [[ $(plutil -extract CFBundleIdentifier raw "$plist") == com.kezaer.pacemark ]]
  [[ $(plutil -extract CFBundleShortVersionString raw "$plist") == "$version" ]]
  [[ $(plutil -extract LSMinimumSystemVersion raw "$plist") == 15.0 ]]
  while IFS= read -r -d '' path; do
    case "${path#"$app"/}" in
      Contents/MacOS/Pacemark|"$framework"/Autoupdate|"$framework"/Sparkle) ;;
      "$framework"/Updater.app/Contents/MacOS/Updater) ;;
      "$framework"/XPCServices/Installer.xpc/Contents/MacOS/Installer) ;;
      "$framework"/XPCServices/Downloader.xpc/Contents/MacOS/Downloader) ;;
      *) die "Unexpected executable: $path" ;;
    esac
    details=$(codesign -dvvv "$path" 2>&1)
    grep -q '^TeamIdentifier=46DQYGR8QP$' <<< "$details"
    grep -q '^Timestamp=' <<< "$details"
    grep -q '(runtime)' <<< "$details"
    entitlements=$(codesign -d --entitlements - --xml "$path" 2>/dev/null)
    [[ $entitlements != *'<key>'* ]] || die "Unexpected executable entitlement: $path"
  done < <(find "$app" -type f -perm -111 -print0)
}

package() {
  local stage="$work/disk" app="$work/disk/Pacemark.app" payload="$work/payload"
  local identity display='Developer ID Application: Nikolai Fateev (46DQYGR8QP)'
  local dmg="$payload/$name" plist="$app/Contents/Info.plist" tools="$sparkle/bin"
  local key=(--account pacemark)
  if [[ -n ${SPARKLE_KEY_FILE:-} ]]; then key=(--ed-key-file "$SPARKLE_KEY_FILE"); fi
  if [[ -d $out ]]; then verify_pair "$out"; return; fi
  Scripts/build-app.sh --deps-only
  source Scripts/codesign-identity.sh
  identity=$(pacemark_newest_identity_sha "$display")
  [[ -n $identity && $(pacemark_identity_name_for_sha "$identity") == "$display" ]] || die "Missing Developer ID"
  mkdir -p "$stage" "$payload"
  if [[ ! -f $work/app.zip ]]; then
    if ! $test_mode; then
      if grep -Eq 'CODE_SIGN_ENTITLEMENTS:.*PacemarkApp.entitlements' project.yml; then
        die "Apply the host entitlement removal before packaging"
      fi
      xcodegen generate
      git diff --exit-code -- Pacemark.xcodeproj
    fi
    xcodebuild -project Pacemark.xcodeproj -scheme Pacemark -configuration Release \
      -destination 'generic/platform=macOS' -derivedDataPath .xcode-derived ARCHS=arm64 \
      CODE_SIGNING_ALLOWED=NO ENABLE_HARDENED_RUNTIME=YES build
    rm -rf "$app"
    ditto .xcode-derived/Build/Products/Release/Pacemark.app "$app"
    if $test_mode; then
      rm -rf "$app/Contents/PlugIns/PacemarkWidgets.appex"
      plutil -replace CFBundleShortVersionString -string "$version" "$plist"
    fi
    [[ -z $(find "$app" -name '*.appex') ]] || die "Unexpected extension"
    [[ $(lipo -archs "$app/Contents/MacOS/Pacemark") == arm64 ]] || die "Expected arm64"
    [[ $(plutil -extract CFBundleIdentifier raw "$plist") == com.kezaer.pacemark ]] || die "Wrong bundle"
    [[ $(plutil -extract CFBundleShortVersionString raw "$plist") == "$version" ]] || die "Tag/version mismatch"
    plutil -replace SUFeedURL -string "$feed" "$plist"
    plutil -replace SUPublicEDKey -string "$pub" "$plist"
    plutil -replace SUEnableAutomaticChecks -bool YES "$plist"
    plutil -replace SUAllowsAutomaticUpdates -bool YES "$plist"
    plutil -replace SUAutomaticallyUpdate -bool NO "$plist"
    cp LICENSE NOTICE "$app/Contents/Resources/"
    cp "$sparkle/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE"
    local framework="$app/Contents/Frameworks/Sparkle.framework" child
    local nested=()
    for child in Autoupdate Updater.app XPCServices/{Installer,Downloader}.xpc; do
      nested+=("$framework/Versions/B/$child")
    done
    for child in "${nested[@]}" "$framework" "$app"; do
      codesign --force --timestamp --options runtime --sign "$identity" "$child"
    done
    audit_app "$app"
    codesign --verify --deep --strict "$app"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$work/app.tmp.zip"
    mv "$work/app.tmp.zip" "$work/app.zip"
  fi
  if $test_mode && [[ $tag == v1.0.0-rc1 ]]; then
    audit_app "$app"
    codesign --verify --deep --strict "$app"
    echo "Developer ID signing rehearsal passed: $app"
    return
  fi
  notarize "$work/app.zip" "$work/app.json"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  if [[ ! -f $dmg ]]; then
    cp LICENSE NOTICE "$stage/"
    ln -snf /Applications "$stage/Applications"
    hdiutil create -ov -volname Pacemark -srcfolder "$stage" -fs APFS -format UDZO "$work/new.dmg"
    codesign --force --timestamp --sign "$identity" "$work/new.dmg"
    mv "$work/new.dmg" "$dmg"
  fi
  notarize "$dmg" "$work/dmg.json"
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  "$tools/generate_appcast" "${key[@]}" --maximum-deltas 0 --download-url-prefix "$prefix" "$payload"
  (cd "$payload" && shasum -a 256 "$name" > "$name.sha256")
  verify_pair "$payload"
  signature=$(validate "$payload")
  "$tools/sign_update" "${key[@]}" --verify "$dmg" "$signature"
  mkdir -p "$(dirname "$out")"
  local ready
  ready=$(mktemp -d "dist/.ready.XXXXXX")
  cp "$dmg" "$dmg.sha256" "$payload/appcast.xml" "$ready/"
  mv "$ready" "$out"
}

verify_pair() {
  local dir=$1 signature build mount
  signature=$(validate "$dir")
  # SubjectPublicKeyInfo for Ed25519 has a fixed 12-byte DER header.
  python3 - "$pub" "$signature" "$work" <<'PY'
import base64, pathlib, sys
key, signature, directory = sys.argv[1:]
p = pathlib.Path(directory)
(p/'public.der').write_bytes(bytes.fromhex('302a300506032b6570032100') + base64.b64decode(key))
(p/'signature.bin').write_bytes(base64.b64decode(signature))
PY
  "${OPENSSL:-openssl}" pkeyutl -verify -pubin -keyform DER -inkey "$work/public.der" \
    -rawin -in "$dir/$name" -sigfile "$work/signature.bin"
  spctl -a -t open --context context:primary-signature -vv "$dir/$name" 2>&1 | tee "$work/dmg.assessment"
  grep -Fx 'source=Notarized Developer ID' "$work/dmg.assessment"
  (
    mount=$(mktemp -d)
    hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$dir/$name"
    trap 'hdiutil detach "$mount"; rmdir "$mount"' EXIT
    local app="$mount/Pacemark.app" legal
    audit_app "$app"
    codesign --verify --deep --strict "$app"
    spctl -a -t exec -vv "$app" 2>&1 | tee "$work/app.assessment"
    grep -Fx 'source=Notarized Developer ID' "$work/app.assessment"
    xcrun stapler validate "$app"
    [[ $(readlink "$mount/Applications") == /Applications ]]
    for legal in LICENSE NOTICE; do
      cmp "$legal" "$mount/$legal"
      cmp "$legal" "$app/Contents/Resources/$legal"
    done
    build=$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")
    python3 - "$dir/appcast.xml" "$build" <<'PYBUILD'
import sys, xml.etree.ElementTree as ET
value = ET.parse(sys.argv[1]).findtext('.//{http://www.andymatuschak.org/xml-namespaces/sparkle}version')
if value != sys.argv[2]:
    sys.exit("Appcast build differs from signed app")
PYBUILD
  )
}

fetch_public() {
  local dir=$1 asset
  mkdir -p "$dir"
  for asset in "$name" "$name.sha256" appcast.xml; do
    curl -fsSL --retry 4 "$prefix$asset" -o "$dir/$asset"
  done
  verify_pair "$dir"
}

publish() {
  local draft remote asset
  remote=$(mktemp -d "$work/assets.XXXXXX")
  if ! draft=$(gh release view "$tag" -R "$repo" --json isDraft --jq .isDraft); then
    verify_pair "$out"
    check_build "$out"
    gh release create "$tag" -R "$repo" --verify-tag --draft --title "Pacemark $version" \
      --notes "Download $name for Apple silicon. [Corresponding source](https://github.com/$repo/tree/$tag)."
    draft=true
  fi
  if [[ $draft == true ]]; then
    verify_pair "$out"
    for asset in "$name" "$name.sha256" appcast.xml; do
      if ! gh release download "$tag" -R "$repo" -p "$asset" -D "$remote"; then
        gh release upload "$tag" -R "$repo" "$out/$asset"
        gh release download "$tag" -R "$repo" -p "$asset" -D "$remote"
      fi
      cmp "$out/$asset" "$remote/$asset"
    done
    verify_pair "$remote"
    check_build "$remote"
    gh release edit "$tag" -R "$repo" --draft=false
  fi
  fetch_public "$remote"
}

check_build() {
  local remote=$1 code
  code=$(curl -sSL --retry 3 -o "$work/current.xml" -w '%{http_code}' "$feed")
  case "$code" in
    404) [[ $tag == v1.0.0 ]] || die "Only the first release can initialize the feed" ;;
    200)
      python3 - "$work/current.xml" "$remote/appcast.xml" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET
old, new = map(pathlib.Path, sys.argv[1:])
def build(path):
    return max(int(n.text) for n in ET.parse(path).findall('.//{http://www.andymatuschak.org/xml-namespaces/sparkle}version'))
if old.read_bytes() != new.read_bytes() and build(new) <= build(old):
    sys.exit("Promotion would replace an equal or higher build")
PY
      ;;
    *) die "Feed returned HTTP $code" ;;
  esac
}

promote() {
  local remote="$work/public"
  fetch_public "$remote"
  check_build "$remote"
  mkdir -p dist/pages
  [[ -z $(find dist/pages -mindepth 1 ! -name appcast.xml -print -quit) ]] || die "Unexpected Pages artifact"
  cp "$remote/appcast.xml" dist/pages/
}

case $action in
  package) package ;;
  publish) publish ;;
  promote) promote ;;
  *) die "Unknown subcommand" ;;
esac
