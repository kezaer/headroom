# Develop Pacemark

Pacemark is a Swift 6 menu bar app for macOS 15 and later. Start UI work with [DESIGN.md](DESIGN.md) and [offline replay and live-window QA](docs/dev/LOCAL-MODELS.md). Apply changes across providers and accounts wherever the official client supports them. Document any exception.

## Build and test

Run these commands from the checkout with Xcode 27 selected. The tests use fixtures. Use demo accounts for UI verification.

```sh
swift build
Scripts/check-pacemark-copy.sh
Scripts/check-design-system.sh
Scripts/check-test-preferences.sh swift test
```

## Provider boundaries

Follow the [provider guide](docs/adding-a-provider.md) and the [provider read paths](docs/how-it-works.md). Keep provider transports injectable. Report failures as typed `FailureReason` values. Never log raw output, credentials or identities.

- Claude usage comes exclusively from the official CLI's usage report. Never use the subscription OAuth endpoint, read its Keychain token, mint subscription tokens or impersonate the CLI. Use print mode only at the verified version floor (2.1.217) or later. A print miss or older version uses the PTY. Keep Remote Control disabled on interactive launches. Never run auth status during routine polling. Parse stable labels and keep valid partial windows. See the [Claude probe notes](docs/solutions/claude-print-mode-usage-probe.md).
- Run PTYs off the main actor. Resolve executables through the login shell, enforce deadlines, terminate the process group and wait for a quiet period across terminal repaints. ANSI stripping in regular expressions requires ICU escapes. Cache a failed Claude executable search within its refresh generation. User actions invalidate the search and an old completion cannot overwrite a newer generation.
- Codex reads usage with the official login. Attached homes use the official app-server. Classify windows by their reported duration before falling back to slot order. Banked resets are read-only. Never consume a reset or refresh an attached home's credentials yourself.
- Grok prefers ACP billing and falls back to the CLI's billing transport. Cursor uses its official interactive usage panel. Preserve their billing periods. Copilot reads usage records from local session logs and checks allowance with the CLI's local server. Keep prompts and tool output out of decoded data.
- Antigravity accepts only no-turn usage and credits answers. Suppress browser sign-in during probes. OpenCode uses its standalone usage operation and keeps all four XDG home overrides together for extra accounts. A confirmed workspace without Go completes setup.
- Keep routine polling free of model calls. [Warm-up](docs/dev/warm-up.md) spends quota and needs explicit consent. Keep it inert in demos and tests.

## Accounts and polling

Wire providers in AppComposition. PacemarkCore owns account storage, polling, parsers and scheduling. PollingEngine wakes for the earliest due account. AccountProbeScheduler serializes each CLI lane, taking the most overdue account first. Due HTTP reads can run concurrently. UsageStore merges results on the main actor. Preserve per-window observation times across partial and failed reads.

Use the engine account list for scheduling and setup. Use the display list for the popover, settings, menu bar and notification labels. Only strong identity matches may merge rows for display. Remembered accounts keep their last reading and never poll or fire reminders. On a login change, commit the slot record with its pending mirror before updating labels, reminders and continuity. Preserve crash recovery and park any new per-account state with its identity.

The default account uses the official CLI home. For added accounts preserve the provider's config-home environment on every read and handoff. Claude, Codex, Grok and OpenCode support multiple accounts, tested to 20 per provider. Cursor and Antigravity lack verified isolated sign-ins. Copilot needs the default CLI's session logs. Remove only owned homes. Detach borrowed homes without deleting them. Hiding the default account leaves its login intact.

Use the account-scoped setup coordinator for Terminal handoffs. Keep Claude workspace trust separate from sign-in. Codex setup goes through its official CLI. Reject in-flight readings from a previous login generation. Provider capability failures belong to the capability coordinator, distinct from account verification. Only a confirmed absence ends final verification immediately. Keep demo setup, credentials, storage, launch-at-login and provider I/O isolated.

## Mac UI and compatibility

Use PacemarkSharedUI for stateless components. SwiftPM imports it as a module and Xcode compiles the files into the app target. Use the shared reset formatter and preserve unknown reset schedules. Use strict comparisons for Foundation dates to avoid unavailable back-deployed comparison symbols.

Use one rasterized status label. A timeline inside the native menu label can cause a status-item update loop. Keep drag positions in MeterRowsLayout. Avoid geometry and animation state on the whole popover. Verify window size, system glass and transitions in the real MenuBarExtra in light and dark modes. Keep the pinned popover for DialKit inspection.

Evaluate reminders only after a live merge with a live window and scheduled reset. Record delivery after the notification poster accepts the request. Access the notification center only from the real app bundle.
