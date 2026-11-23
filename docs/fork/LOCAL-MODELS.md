# Headroom UI work with a local model

Headroom is a macOS menu bar app written in Swift 6 and SwiftUI.
The menu bar and popover show subscription usage and reset times.
Settings › Accounts manages which provider logins appear.

## Fast check

Use the debug build after each edit. Run it from the repository root.

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
swift build --product Headroom
```

Always keep both variables. A plain `swift build` uses the default 27.2 SDK, which fails
to load the SwiftUI `State` macro. This builds the debug app without packaging it.
Use the screenshots below to inspect the result, or build the release bundle for a
hands-on check.

## Run offline

Quit Headroom before opening the installed build in replay mode.

```sh
open -a /Applications/Headroom.app --args --demo captured
```

Replay uses `~/Library/Application Support/Headroom/DevCapture/latest.json`.
It uses no live provider services. Refresh reapplies the captured data. Account edits
last until the app quits. The actual reset deadlines are shifted to the replay launch time.

To use a different capture, pass `--demo "captured=/path/to/capture.json"`.
While online, run `/Applications/Headroom.app/Contents/MacOS/Headroom --capture-demo`
to refresh the capture. The previous file becomes `previous.json`.

## Check screenshots

Run the headless renderer from the repository root. With Command Line Tools,
pin the macOS 26.5 SDK as the local bundle script does. The default CLT 27.2 SDK
fails to load the SwiftUI `State` macro.

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
swift build --product Headroom && \
.build/debug/Headroom --render-popover .build/popover-shots
```

Open `settings-accounts-multi-light.png` and `settings-accounts-multi-dark.png` in
`.build/popover-shots/` to check the multi-account list. The renderer uses built-in
fixtures and also writes screenshots of the popover and other Settings panes.
The full sweep can take a few minutes.

## Preview and test

For a hands-on check, build the release bundle in the checkout and open it in replay mode.

```sh
Scripts/t3-install-local.sh --build-only && \
open -n "$PWD/Headroom.app" --args --demo captured
```

Quit your previous preview before opening another one.

Run focused replay tests with `swift test --filter 'DemoCaptureTests|DemoFixtureTests'`.

Before pushing a larger change, run `swift build --target HeadroomCoreTests && swift test --skip-build`.
Run `swift test` if you need to build or relink the test bundle.

The macOS app tests need full Xcode, XcodeGen and a local Sparkle dependency.
Prepare Sparkle while online with `Scripts/build-app.sh --deps-only` if needed.

```sh
xcodegen generate
xcodebuild -project Headroom.xcodeproj -scheme HeadroomAppTests -destination 'platform=macOS' -derivedDataPath .xcode-derived CODE_SIGNING_ALLOWED=NO test
```

For a Settings › Accounts edit, add `-only-testing:HeadroomAppTests/AccountsSettingsInteractionTests`
to the Xcode command for a focused check.

## Find the UI

Paths below start at `Sources/`. Short Accounts paths are relative to `HeadroomApp/UI/`.
Read only the file for the area you are changing.

- Menu bar label and badges — `HeadroomApp/UI/MenuBarLabel.swift` (`MenuBarStatusLabel`, `MenuBarLabelRenderer`).
- Menu bar glyphs — `HeadroomApp/UI/MenuBarGlyphImage.swift` (`MenuBarGlyphImage`), `VesselGlyph.swift` (`VesselGlyph`).
- Popover — `HeadroomApp/UI/PopoverView.swift` (`PopoverView`, `RefreshFooter`).
- Provider card — `HeadroomApp/UI/ProviderCardView.swift` (`ProviderCardView`), `CompactAccountRow.swift` (`CompactAccountRow`).
- Settings window and panes — `HeadroomApp/UI/SettingsView.swift` (`SettingsView`), `SettingsSidebar.swift` (`SettingsSidebar`), `SettingsPanes.swift` (pane views).
- Settings › Accounts container — `HeadroomApp/UI/AccountsSettings/AccountsSettingsTile.swift` (`AccountsSettingsTile`).
- Accounts provider groups — `AccountsSettings/AccountsSettingsProviderGroup.swift` (`AccountsSettingsTile.providerGroup`).
- Accounts row, menu and recovery — `AccountsSettings/AccountsSettingsAccountRow.swift` (`accountRow`), `AccountsSettingsRowActions.swift` (`accountMenu`), `AccountsSettingsRecovery.swift` (`AccountsSettingsTile.AccountStatus`).
- Accounts row copy and rules — `HeadroomApp/UI/AccountsSettingsInteractions.swift` (`AccountsSettingsInteractions`).
- Accounts loading and removal transitions — `HeadroomApp/UI/AccountsSettingsLoading.swift` (`SettingsAccountWaitPill`, `SettingsAccountExit`).
- Add Source sheet — `AccountsSettings/AddAccountSourceSheet.swift` (`AddAccountSourceSheet`).
- Accounts columns and badge editor — `AccountsSettings/AccountsSettingsStyle.swift` (`AccountsColumns`, `AccountMenuBarBadgeField`).
- Provider setup UI — `HeadroomApp/UI/ClaudeSetupViews.swift` (`ClaudeConnectCard`) and `CodexSetupViews.swift` (`CodexConnectCard`).
- Colours — `HeadroomSharedUI/ProviderStyle.swift` (`ProviderStyle`), `HeadroomCore/Models/BrandColorValues.swift` (`HeadroomBrandColorValues`), `HeadroomCore/Models/MenuBarPalette.swift` (`MenuBarPalette`).
- Fonts and spacing — `HeadroomApp/UI/SettingsRows.swift` (`SettingsType`, `SettingsMetrics`), `HeadroomApp/UI/PopoverView.swift` (`PopoverCardMetrics`), `HeadroomSharedUI/HeadroomTuning.swift` (`HeadroomTuning`).

See `DESIGN.md` for the existing colours, spacing, typography and motion rules.

### Large upstream files

Token counts are rough estimates based on file size. Find the relevant section,
then read a slice such as `sed -n '276,360p' Sources/HeadroomApp/UI/ProviderCardView.swift`.
Keep these files intact so the fork can continue syncing with upstream.

| File | Approx. tokens | Find the relevant section |
| --- | ---: | --- |
| `ProviderCardView.swift` | 25k | `grep -n -e 'struct ProviderCardView' -e 'struct UsageBarsStack' Sources/HeadroomApp/UI/ProviderCardView.swift` |
| `PopoverView.swift` | 21k | `grep -n -e 'struct PopoverView' -e 'struct RefreshFooter' Sources/HeadroomApp/UI/PopoverView.swift` |
| `SettingsPanes.swift` | 15k | `grep -n 'struct .*SettingsPane:' Sources/HeadroomApp/UI/SettingsPanes.swift` |
| `UsageStore.swift` | 21k | `grep -n -e 'var menuBarMeters' -e 'func setShowAllProviderAccountsInMenuBar' Sources/HeadroomCore/Engine/UsageStore.swift` |

## Recipe for adding a setting

Use the existing `showAllProviderAccountsInMenuBar` toggle as a reference.

1. `HeadroomCore/Settings/Preferences.swift` — add a key, a typed getter with a
   default, and a setter.
2. `HeadroomCore/Engine/UsageStore.swift` — add the observable property,
   initialise it from preferences and add a method that writes both.
3. `HeadroomApp/UI/SettingsPanes.swift` — add a control in the relevant pane.
   Bind its getter to the store property and its setter to the store method.
4. In the view or store projection that uses the setting, read it from the store.
   For the example toggle, look for `menuBarMeters` in `UsageStore.swift`.
5. Run the debug build and check the relevant screenshot or replay.

Keep new UI settings out of `DemoCaptureSettings.swift`. Replay gets the setting's
current default from `Preferences`. That keeps ordinary UI work out of the capture
format. If a future change needs to preserve a setting in the capture, decode a
missing key with the same default so existing captures still load.

## Example

This edit adds 2 points between each source icon and its title in the Add Source sheet.

1. Find `AddAccountSourceSheet.choice` in the file listed above.
2. Change that button label's `HStack(spacing: 10)` to `HStack(spacing: 12)`.
3. Run the debug build and the focused Swift tests above.
4. In the bundled preview, open Settings › Accounts and choose **Add Source…** for Codex. Check the icon gap and click a source to make sure it opens its next step.
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
