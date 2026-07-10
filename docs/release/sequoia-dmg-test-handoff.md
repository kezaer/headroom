# Sequoia DMG Test Handoff

Use this checklist to build a Developer ID notarized DMG, send it to a macOS 15
Sequoia tester, and collect useful release evidence.

## Build the DMG

Build from the Mac that has the Developer ID Application certificate, Xcode signing
access, notary credentials, and Sparkle private key.

```bash
cd /path/to/headroom
git pull
swift test

HEADROOM_NOTARY_PROFILE=headroom-notary ./Scripts/release-app.sh
```

If the notary profile is named differently, replace `headroom-notary` with that profile
name. To confirm a profile works, run:

```bash
xcrun notarytool history --keychain-profile headroom-notary
```

If you do not remember the profile name, create a fresh one:

```bash
xcrun notarytool store-credentials headroom-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "<app-specific-password>"
```

The release script prints the final DMG path, usually:

```text
dist/Headroom-<version>-<build>.dmg
```

Before sending it, run these checks:

```bash
xcrun stapler validate dist/Headroom-<version>-<build>.dmg
spctl -a -vvv -t open --context context:primary-signature dist/Headroom-<version>-<build>.dmg
shasum -a 256 dist/Headroom-<version>-<build>.dmg
```

Expected results:

- `stapler validate` says the validate action worked.
- `spctl` accepts the DMG and shows the Developer ID origin.
- Save the SHA-256 hash next to the file you send.

## DM to the Tester

Send the DMG plus this text:

```text
Could you test this Headroom build on your Sequoia Mac?

Please install from the DMG by dragging Headroom.app to Applications, then launch it
from /Applications. It is a menu bar app, so look for the vessel icon in the menu bar.

Please take the screenshots listed below and tell me:
- Your exact macOS version from System Settings > General > About.
- Whether the Mac is Apple silicon.
- Whether Gatekeeper showed any warning.
- Whether the Headroom menu bar icon appeared.
- Whether the popover opened and showed Claude/Codex setup or usage states.
- Whether Settings opened.
- Whether adding the Headroom widget worked from Notification Center/Desktop widgets.
```

## Tester Screenshots

Ask for these screenshots during the Sequoia run:

1. `About This Mac` / `System Settings > General > About`, showing macOS 15.x and Mac
   chip type.
2. The mounted DMG Finder window before install, showing `Headroom.app` and
   `Applications`.
3. The copied app in `/Applications`.
4. First launch result:
   - If it opens cleanly, screenshot the Headroom menu bar icon and popover.
   - If macOS shows a Gatekeeper dialog, screenshot the whole dialog.
5. Any privacy prompt Headroom triggers, especially "Headroom would like to access data
   from other apps". Screenshot the prompt before clicking Allow.
6. The main Headroom popover on Sequoia after the first refresh settles.
7. Headroom Settings.
8. Widget gallery with Headroom visible, plus one added Headroom widget on the Desktop
   or Notification Center.
9. If Claude CLI and Codex CLI are installed/logged in on the tester machine, screenshot
   the live usage state. If not, screenshot the setup/connection state.

Do not ask the tester to screenshot token files, Keychain items, API keys, or Terminal
output that could expose credentials.

## Optional Tester Terminal Checks

These checks are useful if the tester is comfortable with Terminal:

```bash
sw_vers
uname -m
xattr -p com.apple.quarantine /Applications/Headroom.app 2>/dev/null || true
spctl -a -vvv -t execute /Applications/Headroom.app
codesign --verify --deep --strict --verbose=2 /Applications/Headroom.app
```

If the app does not launch, collect:

```bash
log show --predicate 'process == "Headroom"' --last 10m --style compact
```

Review the log before sharing it outside the team.

## Notarization Note

Developer ID notarization does not use screenshots. Apple notarization is a command-line
submission, scan, and ticket-stapling flow for software distributed outside the Mac App
Store. The screenshots above are release QA evidence for the Sequoia support gate, not
inputs to the notarization service.
