# Website DMG Release Runbook

Use this runbook to ship a new public macOS Headroom release at
`https://headroom.zantos.co`. It covers the whole chain: version metadata, Developer ID
signing, Apple notarization, Sparkle appcast generation, the portfolio-hosted download files,
and live verification.

The macOS app source is this repository. The public files are hosted by the separate
`/Users/kylezantos/App Development/Manual Library/kz-portfolio` repository. Its Vercel
project owns `headroom.zantos.co`; do not deploy the generated `dist/` directory directly as a
new Vercel project.

## Prerequisites

- A clean, up-to-date `main` branch in both repositories.
- A Developer ID Application certificate installed locally.
- Working notarization credentials, normally the `headroom-notary` keychain profile.
- The Sparkle private signing key available in the login Keychain.
- `xcodegen`, Xcode, `gh`, `pnpm`, and the Vercel CLI installed and authenticated.

Confirm the signing prerequisites without exposing credentials:

```bash
security find-identity -v -p codesigning | rg 'Developer ID Application'
xcrun notarytool history --keychain-profile headroom-notary
```

## 1. Bump the release version

Create a release branch in this repository. Update `project.yml` as one consistent unit:

- macOS app and widget `MARKETING_VERSION`
- macOS app Info.plist version settings
- `CURRENT_PROJECT_VERSION` for all app targets, including iOS targets

Regenerate the Xcode project, then test and merge the release bump before creating the public
artifact:

```bash
xcodegen generate
swift test
```

The generated `Headroom.xcodeproj/project.pbxproj` must be committed with `project.yml`.
Release from `main`, never from an unmerged feature branch.

## 2. Seed the release staging folder from production

`Scripts/release-app.sh` generates the appcast from `dist/headroom.zantos.co`. That directory
is local build output and may be stale. Before every release, replace it with the current
production asset set from the portfolio repository. This preserves the current appcast item and
lets Sparkle generate a delta from the version users actually have.

```bash
rm -rf dist/headroom.zantos.co
ditto \
  '/Users/kylezantos/App Development/Manual Library/kz-portfolio/public' \
  dist/headroom.zantos.co
```

The delete is limited to ignored local staging output. Do not remove old versioned DMGs from the
portfolio `public/` directory unless intentionally retiring a supported update path.

## 3. Build, sign, notarize, and generate the feed

Run the release script from this repository:

```bash
HEADROOM_NOTARY_PROFILE=headroom-notary ./Scripts/release-app.sh
```

The script builds a Developer ID app, notarizes and staples the app and DMG, validates with
Gatekeeper, signs the Sparkle archive, then updates these local outputs:

- `dist/Headroom-<version>-<build>.dmg`
- `dist/headroom.zantos.co/Headroom-<version>-<build>.dmg`
- `dist/headroom.zantos.co/Headroom.dmg`
- checksums, `appcast.xml`, `latest.json`, and any deltas referenced by the appcast

Validate the output before publishing:

```bash
xcrun stapler validate dist/Headroom-<version>-<build>.dmg
spctl -a -vvv -t open --context context:primary-signature \
  dist/Headroom-<version>-<build>.dmg
shasum -a 256 dist/Headroom-<version>-<build>.dmg
```

Check that the first appcast item names the new version and build, retains the current
production item, and references only files present in `dist/headroom.zantos.co/`.

## 4. Publish assets through the portfolio repository

Create a branch in `kz-portfolio`. Copy only the generated files needed by the new appcast:

```bash
SOURCE='/Users/kylezantos/App Development/Manual Library/headroom/dist/headroom.zantos.co'
TARGET='/Users/kylezantos/App Development/Manual Library/kz-portfolio/public'

ditto "$SOURCE/Headroom-<version>-<build>.dmg" "$TARGET/Headroom-<version>-<build>.dmg"
ditto "$SOURCE/Headroom-<version>-<build>.dmg.sha256" "$TARGET/Headroom-<version>-<build>.dmg.sha256"
ditto "$SOURCE/Headroom.dmg" "$TARGET/Headroom.dmg"
ditto "$SOURCE/Headroom.dmg.sha256" "$TARGET/Headroom.dmg.sha256"
ditto "$SOURCE/appcast.xml" "$TARGET/appcast.xml"
ditto "$SOURCE/latest.json" "$TARGET/latest.json"
```

Also copy every `Headroom*.delta` file referenced in the new appcast. Keep the older versioned
DMGs and their checksums in place.

Before committing, verify the stable file and manifest agree:

```bash
jq -e '.version == "<version>" and .build == "<build>"' "$TARGET/latest.json"
shasum -a 256 "$TARGET/Headroom.dmg"
cat "$TARGET/Headroom.dmg.sha256"
pnpm build
```

Open a PR to `kz-portfolio/main`, wait for the Vercel preview check, then merge it. Promote the
portfolio site through its documented production path, never by pushing directly to its
`production` branch:

```bash
pnpm ship
```

## 5. Verify production from the public URL

Confirm the Vercel deployment aliases `headroom.zantos.co`, then check the live files:

```bash
curl --fail --silent https://headroom.zantos.co/latest.json
curl --fail --silent https://headroom.zantos.co/appcast.xml
curl --fail --silent --location https://headroom.zantos.co/Headroom.dmg | shasum -a 256
```

The live DMG hash must equal `latest.json`'s `sha256` and `Headroom.dmg.sha256`. For the final
download-style smoke test, mount a fresh public download, validate its signature, and run the
diagnostic without launching the menu bar UI:

```bash
hdiutil verify /path/to/Headroom.dmg
codesign --verify --deep --strict --verbose=2 /Volumes/Headroom\ Installer/Headroom.app
/Volumes/Headroom\ Installer/Headroom.app/Contents/MacOS/Headroom --probe-codex
```

For a manual acceptance pass, drag the app to `/Applications`, launch it, and confirm the
popover matches the official provider surfaces. For the Codex window-classification fix, a
`prolite` account may correctly show only Weekly plus Spark Weekly. It must never fabricate a
five-hour row.

## Rollback

If the public artifacts are wrong, revert the release-asset commit in `kz-portfolio/main` and
run `pnpm ship` again. This restores the prior stable DMG, manifest, and appcast together.
Do not delete the notarized versioned DMG from this repository's local `dist/` history while
investigating.
