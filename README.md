# UsageBar

A macOS menu bar app that shows how much of your AI-subscription usage remains for the
5-hour and weekly windows, when each resets, and your (manually entered) monthly renewal
date — for **Anthropic Claude** and **ChatGPT/Codex**, side by side. Built to add more
providers later behind one abstraction.

Plan: [`docs/plans/2026-07-02-001-feat-ai-usage-menu-bar-app-plan.md`](docs/plans/2026-07-02-001-feat-ai-usage-menu-bar-app-plan.md).

## Build & test

```bash
swift build      # builds UsageBarCore (logic) + UsageBar (SwiftUI menu bar app)
swift test       # runs the UsageBarCore test suite
```

Requires Xcode 26 / Swift 6.3 on macOS 26 (Tahoe). The package also opens directly in
Xcode 26 (`File ▸ Open` the folder), and `xcodebuild -scheme UsageBar` builds it.

## Structure

- `Sources/UsageBarCore` — all testable logic: domain model, credential access
  (`CredentialStore` actor), the two providers, the polling engine/view model, and
  preferences. Fully covered by `swift test` with mocked Keychain/network.
- `Sources/UsageBarApp` — the SwiftUI `MenuBarExtra` shell and the Tahoe / Liquid Glass
  popover, cards, settings, and menu bar label.

## Project-shape note (deviation from plan KTD9)

The plan specified an Xcode `.xcodeproj`. This repo is a **Swift package** instead, so the
core logic builds and verifies headlessly (`swift build` / `swift test`) in CI and
automated runs. The trade-off: SwiftPM does not produce the final distributable menu bar
app bundle. To finalize on your machine:

1. Open the package in Xcode 26 and add a macOS **App** target (or wrap `UsageBarApp`),
   importing `UsageBarCore`.
2. In the app target's `Info.plist`, set `LSUIElement = YES` (no Dock icon).
3. Set signing to your **free Apple Development** team (personal team is enough) — this is
   load-bearing (KTD8): a stable signing identity keeps the Keychain "Always Allow" grant
   for `Claude Code-credentials` persistent across rebuilds. Ad-hoc signing re-prompts
   every build.
4. Leave **App Sandbox off** (needed to read `~/.codex/auth.json` and the cross-app
   Keychain item — KTD8). Notarization is not needed for a locally built/run personal app.

## ⚠️ Before Claude usage works: run the U9 auth spike

The Claude usage endpoint and its OAuth refresh are **undocumented and unverified**. Until
the spike in the plan (unit U9) is run against your real credentials, the app safely
degrades Claude to a "run `claude` to re-login" state instead of guessing. The spike must
confirm, before the Claude live path is trusted:

- Whether your `Claude Code-credentials` token carries the `user:profile` scope required to
  call `GET /api/oauth/usage` at all (Q4).
- Whether the `User-Agent: claude-code/<version>` header actually clears the 429 (Q).
- The exact refresh token URL / `client_id` / `grant_type`, **and whether refreshing
  rotates the token** — if it does, self-refresh would log Claude Code out, so it stays
  disabled and the app degrades to re-login (Q1/Q5, the P0 risk).

**Self-refresh is intentionally disabled** (`ReauthOnlyRefresher`) until the spike proves
the refresh token is non-rotating. Codex reads `~/.codex/auth.json` directly and works
without a spike.

The response field mappings in `ClaudeProvider`/`CodexProvider` are best-effort from
research and must be checked against a live capture; decoding is lenient so unexpected
fields degrade gracefully rather than crash.

## Status

Core logic is implemented and unit-tested (39 tests). The menu bar app, popover, and
settings compile. Remaining manual steps (your machine, GUI, or credentials): the U9
spike, the Xcode app-bundle + signing finalization above, and visual / VoiceOver smoke on
macOS 26.
