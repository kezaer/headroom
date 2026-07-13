---
name: release-website-dmg
description: "Ship or prepare a Headroom macOS website release: bump the version, build a Developer ID-signed and notarized DMG, publish the Sparkle appcast and download assets to headroom.zantos.co through kz-portfolio, and verify fresh downloads and updates from installed older releases. Use whenever the user asks to release, publish, ship, update, or make a new Headroom DMG available."
---

# Headroom Website DMG Release

Follow [docs/release/website-dmg-release.md](../../../docs/release/website-dmg-release.md) as
the authoritative procedure. Use `Scripts/release-app.sh` for the signed/notarized artifact;
do not recreate its signing, appcast, or packaging logic.

## Scope and safety

- Treat `https://headroom.zantos.co` as the public site. Do not substitute a similarly named
  domain.
- The source repo is Headroom; the public assets and Vercel deployment belong to
  `/Users/kylezantos/App Development/Manual Library/kz-portfolio`.
- Never release from an unmerged Headroom branch, deploy `dist/` as a separate Vercel project,
  force-push, or delete versioned DMGs, checksum files, or Sparkle deltas.
- Perform external publishing only when the user explicitly asks to ship or publish. For a
  request to prepare/review the release process, stop before changing the portfolio repo or
  production site.

## Required release sequence

1. Identify the target marketing version and monotonically increasing build. Update the version
   fields together in `project.yml`, run `xcodegen generate` and `swift test`, and merge the
   release bump to `main` before generating public artifacts.
2. Seed `dist/headroom.zantos.co` from the current `kz-portfolio/public` using the runbook's
   non-destructive staging step. This retains the current appcast history so Sparkle can produce
   deltas; the latest full versioned DMG remains the fallback for all older installations.
3. Run `HEADROOM_NOTARY_PROFILE=headroom-notary ./Scripts/release-app.sh`. Do not echo,
   inspect, or commit credentials, signing keys, auth files, or generated secret values.
4. Validate notarization, Gatekeeper, checksums, `latest.json`, and every appcast enclosure
   before copying release outputs. Confirm the app has `SUFeedURL`, `SUPublicEDKey`, and the
   new `CFBundleVersion` stamped.
5. Create a normal branch and PR in `kz-portfolio`; copy the versioned DMG and checksum, stable
   DMG and checksum, `appcast.xml`, `latest.json`, and every delta referenced by the new feed.
   Preserve every existing versioned asset. Build, preview, merge, then use the portfolio's
   documented `pnpm ship` path.
6. Validate the live manifest, appcast, stable-DMG checksum, mounted DMG signature, and public
   diagnostic. Then run the runbook's installed-app update test from an older public release in
   a dedicated macOS test user or VM. The release is not complete until Sparkle upgrades it to
   the new version/build.

## Handoff

Report the target version/build, the public download URL, live checksum match, appcast result,
and installed-app update result. If any verification fails, do not call the release complete;
state the failed gate and keep the prior public assets intact.
