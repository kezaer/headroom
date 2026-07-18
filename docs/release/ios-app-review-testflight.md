# iOS App Review and TestFlight Runbook

Release candidate: iOS 1.0 build 23 (`com.kylezantos.headroom.ios`) with widget
extension build 23 (`com.kylezantos.headroom.ios.widgets`). Last known uploaded build
baseline for this cut: 22.

## Why this resubmission exists

On July 15, 2026, App Review rejected build 14 under Guideline 2.1(a) because the
reviewer could not access connected functionality without a Mac/iCloud publisher.
Submission ID: `3472c833-11a3-4815-82d0-816b291dab60`. Apple explicitly accepted a
demonstration mode as the resolution.

Build 23 includes the production, one-tap demo introduced in build 21, needs no login,
Mac, iCloud payload, or provider account, and carries the latest companion/widget fixes.
The host and widget extension remain universal on iPhone/iPad. Demo data is bundled and
read-only; a separate App Group flag coordinates the widget and never replaces the real
snapshot cache.

## Automated release gates

```bash
swift test
xcodegen generate

# Run HeadroomIOSUITests on an iPhone and an iPad Air 11-inch simulator.
# XcodeBuildMCP or xcodebuild may be used; both destinations must pass.

HEADROOM_IOS_LAST_UPLOADED_BUILD=22 Scripts/verify-ios-release.sh --source
```

The release script repeats source preflight, archives, validates the signed host and
embedded widget, and only then exports/uploads:

```bash
HEADROOM_IOS_LAST_UPLOADED_BUILD=22 ./Scripts/release-ios-testflight.sh

HEADROOM_IOS_LAST_UPLOADED_BUILD=22 \
HEADROOM_IOS_UPLOAD=1 \
  ./Scripts/release-ios-testflight.sh
```

If using API-key authentication, set all three `HEADROOM_ASC_KEY_PATH`,
`HEADROOM_ASC_KEY_ID`, and `HEADROOM_ASC_ISSUER_ID` variables. Never paste their values
into this document or command output. Build 23 must be confirmed unused in App Store
Connect before upload; if a newer build already exists, increment host and widget
together and use the actual highest uploaded build as the baseline.

## Internal TestFlight acceptance

Keep the currently accepted build available while validating the candidate.

1. Wait for App Store Connect processing and export-compliance completion.
2. Assign the candidate to the internal Headroom group first.
3. Delete prior development/App Store copies before installing from TestFlight.
4. On iPhone and an iPad-class device, launch with no Mac publisher available.
5. Tap **Explore Demo** and verify Claude, Codex, Weekly (Fable), API Spend, Settings,
   light/dark appearance, and readable portrait/landscape layouts.
6. Add small, medium, and large widgets. Each must show a visible DEMO label and open
   `headroom://usage` back to the labeled demo.
7. Terminate/relaunch the app; app and widget must remain in demo.
8. Exit through Settings; app and widget must return to the real waiting/synced state.
9. Publish a real Mac snapshot and verify it appears unchanged after demo exit.
10. Check stale/offline/setup states and confirm no provider credential action exists on iOS.

Only after this gate passes: assign the same build to the intended external group,
submit for Beta App Review when required, and enable broader invitations after approval.

## TestFlight “What to Test”

```text
New in this build: one-tap Demo Mode and native iPad support.

Please test Explore Demo from a clean launch with no Mac connected. Check Claude,
Codex, Weekly (Fable), API Spend, Settings, and small/medium/large widgets on iPhone or
iPad. Confirm the DEMO label remains after relaunch, widget taps return to the app, and
Exit Demo restores your original Waiting for Mac or real synced snapshot. If you use
Headroom for Mac, also verify fresh sync plus stale/offline behavior after exiting demo.

Report device, OS version, widget size, appearance, and reproduction steps with feedback.
```

## App Review fields

- Sign-in required: **Off**. Headroom has no login or account.
- Review Notes: paste the current block in `docs/release/appstore-listing.md`.
- Screenshots: capture with `Scripts/capture-demo-screenshots.sh`; include both the
  6.9-inch iPhone and required 13-inch iPad sets.
- Support URL: `https://headroom.zantos.co`
- Privacy URL: `https://headroom.zantos.co/privacy`
- Export compliance: `ITSAppUsesNonExemptEncryption = NO` in host and extension.

## Reply to the unresolved App Review message

```text
Hello,

Thank you for the guidance regarding Guideline 2.1(a). We added a demonstration mode
that exposes the app's complete display functionality without a login, Mac, iCloud
snapshot, or provider account.

In the new build, launch Headroom and tap “Explore Demo” on the first screen. You can
then review Claude and Codex usage, the Weekly (Fable) model limit, API Spend, Settings,
and all Headroom widget sizes. Demo content is clearly labeled. In Settings, tap “Exit
Demo” to return to the real companion state.

Headroom has no login or developer-hosted account, so “Sign-in required” is disabled.
The Review Notes contain the same step-by-step instructions.

This update addresses submission 3472c833-11a3-4815-82d0-816b291dab60. Thank you.
```

## Resubmission record

After the gates pass, record here: processed build, internal group/date, external Beta
Review status (if applicable), clean-device acceptance result, selected App Store build,
review-thread reply date, and final resubmission status. Do not mark the release shipped
until those facts are verified in App Store Connect.

- 2026-07-15: Fresh reviewed build 21 signed archive and archive preflight passed. Xcode
  Organizer uploaded the host app and embedded widget to App Store Connect at 12:31 PM PT;
  processing, internal-group assignment, and clean TestFlight acceptance remain pending.
- 2026-07-18: Build 23 passed the source, signed-archive, iPhone, and iPad release gates.
  Xcode Organizer uploaded the host app and embedded widget to App Store Connect at
  1:22 PM PT; App Store Connect processing and TestFlight group assignment remain pending.
