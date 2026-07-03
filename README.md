# Headroom

A macOS menu bar app that shows how much of your AI-subscription usage remains — the
5-hour and weekly windows, when each resets, and a manually-entered monthly renewal
date — for **Anthropic Claude** and **ChatGPT/Codex**, side by side. Built to add more
providers later behind one abstraction.

## How it gets the data (and why this way)

- **Claude** — reads the real 5-hour and weekly windows by driving the official
  `claude` CLI's `/usage` panel in a pseudo-terminal and parsing what it prints. This is
  the **compliant** path: the official client makes the request (a free status fetch, no
  model call), and Headroom only reads its output. It deliberately does **not** reuse or
  mint Claude subscription OAuth tokens — Anthropic's Feb 2026 policy prohibits that and
  enforces it server-side, and those tokens get blocked. The CLI panel itself notes the
  figures are "approximate, based on local sessions on this machine," but it carries the
  official reset windows.
- **Codex/ChatGPT** — reads `~/.codex/auth.json` and calls the `wham/usage` endpoint
  (the same data Codex's `/status` shows).

## Build & test

```bash
swift build          # builds HeadroomCore (logic) + Headroom (app)
swift test           # 49 tests
./Scripts/build-app.sh   # produces Headroom.app (menu bar / LSUIElement), then: open Headroom.app
```

Requires Xcode 26 / Swift 6.3 on macOS 26 (Tahoe), and the `claude` CLI installed and
logged in. Diagnostic: `swift run Headroom --probe-claude` prints the live parsed windows
so you can confirm the Claude path works on your machine.

## Structure

- `Sources/HeadroomCore` — testable logic: domain model, the Claude `/usage` PTY probe
  (`ClaudeUsageCLIProbe`) + parser (`ClaudeUsageParser`), the Codex provider, the polling
  engine/`@Observable` store, and preferences.
- `Sources/HeadroomApp` — the SwiftUI `MenuBarExtra` shell and the Tahoe / Liquid Glass
  popover, cards, settings, and menu bar label.

## Robustness (the PTY scrape is inherently fragile, so it's contained)

- Hard wall-clock deadlines on capture + a guaranteed process-group kill on every exit
  path — a hung `claude` can never stall the app.
- "Quiet-period" capture that survives the panel's several re-renders; the settled
  (last) value for each window wins.
- Login-shell PATH resolution, so a Finder-launched app (bare environment) still finds a
  node/nvm/homebrew `claude` — verified against a stripped environment.
- Graceful degrade: CLI missing → "install Claude Code"; not logged in → "run `claude`";
  transient read failure → keeps last-known data and retries next cycle.
- Reset times are shown **verbatim** from the panel ("Resets Jul 9 at 10am"), so the app
  can't drift from what Claude Code itself displays.
- The probe runs off the main actor, on the poll timer (default 5 min) — never per-render.

## Finalizing as a distributable app (optional)

`./Scripts/build-app.sh` produces an ad-hoc-signed `Headroom.app` that runs locally. For a
persistent build you rebuild often, open the package in Xcode 26, add a macOS App target,
and sign with your free **Apple Development** identity — a stable signature keeps macOS
permission grants from re-prompting after each rebuild. Leave App Sandbox **off** (needed
to spawn `claude` and read `~/.codex/auth.json`). Notarization isn't needed for a locally
built/run app. Provide an app icon via `CFBundleIconFile` when you have one.

## Status

Working end-to-end: live Claude 5h/weekly windows via the CLI probe (verified against a
real account and from a bare launch environment), Codex via its endpoint, manual renewal
dates, launch-at-login, and the Tahoe popover. 49 tests pass. Remaining polish is the
Xcode signing above, an app icon, and visual/VoiceOver smoke on the running app.
