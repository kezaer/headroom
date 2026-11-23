# Headroom UI work with a local model

Headroom is a macOS menu bar app written in Swift 6 and SwiftUI.
The menu bar and popover show subscription usage and reset times.
Settings › Accounts manages which provider logins appear.

## Run offline

Quit Headroom first. Open the installed build with this command:

```sh
open -a /Applications/Headroom.app --args --demo captured
```

Replay uses `~/Library/Application Support/Headroom/DevCapture/latest.json`.
It uses no live provider services. Refresh reapplies the captured data. Account edits
last until the app quits. The actual reset deadlines are shifted to the replay launch time.

To use a different capture, pass `--demo "captured=/path/to/capture.json"`.
While online, run `/Applications/Headroom.app/Contents/MacOS/Headroom --capture-demo`
to refresh the capture. The previous file becomes `previous.json`.

## Build and test

Run from the repository root. To try an edit offline with Command Line Tools:

```sh
Scripts/t3-install-local.sh --build-only
open -n "$PWD/Headroom.app" --args --demo captured
swift test --filter 'DemoCaptureTests|DemoFixtureTests'
```

Quit your previous preview before opening another one. The build creates
`Headroom.app` in the checkout. For a UI change, run the filtered tests and check
the changed screen in the bundled preview. To install in `/Applications`, run
`Scripts/t3-install-local.sh --install`. The installer opens a normal live session,
so quit it before running the installed replay command.

Before pushing a larger change, run `swift build --target HeadroomCoreTests && swift test --skip-build`.
If the test bundle has not been built yet, run `swift test` once.

With full Xcode and the Sparkle dependency already available, run the macOS app tests:

```sh
xcodebuild -project Headroom.xcodeproj -scheme HeadroomAppTests -destination 'platform=macOS' -derivedDataPath .xcode-derived CODE_SIGNING_ALLOWED=NO test
```

For a Settings › Accounts edit, add `-only-testing:HeadroomAppTests/AccountsSettingsInteractionTests`
to the Xcode command for a focused check.

## Find the UI

Paths below start at `Sources/`. Read only the file for the area you are changing.

- Menu bar label and badges — `HeadroomApp/UI/MenuBarLabel.swift` (`MenuBarStatusLabel`, `MenuBarLabelRenderer`).
- Menu bar glyphs — `HeadroomApp/UI/MenuBarGlyphImage.swift` (`MenuBarGlyphImage`), `VesselGlyph.swift` (`VesselGlyph`).
- Popover — `HeadroomApp/UI/PopoverView.swift` (`PopoverView`, `RefreshFooter`).
- Provider card — `HeadroomApp/UI/ProviderCardView.swift` (`ProviderCardView`), `CompactAccountRow.swift` (`CompactAccountRow`).
- Settings window and panes — `HeadroomApp/UI/SettingsView.swift` (`SettingsView`), `SettingsSidebar.swift` (`SettingsSidebar`), `SettingsPanes.swift` (pane views).
- Settings › Accounts — `HeadroomApp/UI/AccountsSettingsTile.swift` (`AccountsSettingsTile`, `AddAccountSourceSheet`).
- Provider setup UI — `HeadroomApp/UI/ClaudeSetupViews.swift` (`ClaudeConnectCard`) and `CodexSetupViews.swift` (`CodexConnectCard`).
- Colours — `HeadroomSharedUI/ProviderStyle.swift` (`ProviderStyle`), `HeadroomCore/Models/BrandColorValues.swift` (`HeadroomBrandColorValues`), `HeadroomCore/Models/MenuBarPalette.swift` (`MenuBarPalette`).
- Fonts and spacing — `HeadroomApp/UI/SettingsRows.swift` (`SettingsType`, `SettingsMetrics`), `HeadroomApp/UI/PopoverView.swift` (`PopoverCardMetrics`), `HeadroomSharedUI/HeadroomTuning.swift` (`HeadroomTuning`).

See `DESIGN.md` for the existing colours, spacing, typography and motion rules.

## Example

To add 2 points between each source icon and its title in the Add Source sheet:

1. Find `AddAccountSourceSheet.choice` in the file listed above.
2. Change that button label's `HStack(spacing: 10)` to `HStack(spacing: 12)`.
3. Run the build, preview and focused Swift tests above.
4. Open Settings › Accounts, then choose **Add Source…** for Codex. Check the icon gap and click one source to make sure the row still opens its next step.
5. Run `git diff --check`. Stage the edited Swift file and commit with `git commit -m "Adjust add source icon spacing"`.

## Rules

- Make one small change per commit.
- Leave `Sources/HeadroomCore/Providers/`, auth, T3 discovery and persistence formats alone.
- Leave other upstream UI alone unless the task asks to change it.
- Keep captures, emails, account names and local paths out of commits. Use fictional test data.
- Review `git diff --stat` and `git diff` before staging files.

## When stuck

- **Main actor isolation error.** Keep view or store reads on the main actor. Mark the small caller `@MainActor` or use `await MainActor.run { ... }` from async code.
- **Non-Sendable value crosses an actor boundary.** Pass a provider ID or a value snapshot. Keep views, bindings and AppKit objects on the main actor.
- **Result builder or type-check timeout.** Move the changed branch into a small `@ViewBuilder` property or a `View`. Build again before changing anything else.
- **Opaque return type branches differ.** Use `@ViewBuilder` on the helper returning `some View` and remove explicit returns from its branches.
- **Cannot find a shared UI type with SwiftPM.** Copy the nearby `#if SWIFT_PACKAGE` import of `HeadroomSharedUI` into your file. Xcode compiles that folder into the app directly.
- **Cannot access a private helper after a move.** Check where the helper is declared. Keep it private when it is used only in that file. Use internal visibility for a helper called by another file in the app target.
