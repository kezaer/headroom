# AGENTS.md — Headroom

Project-specific guidance for AI agents working in this repo. Read this before making
changes.

## What this is

A native macOS 15+ menu bar app (Swift 6 / SwiftUI) showing remaining AI-subscription
usage — 5-hour and weekly windows, reset times, manual renewal dates — for **Claude** and
**ChatGPT/Codex**, behind one provider abstraction so more can be added. Tahoe uses Liquid
Glass; Sequoia uses a native material popover surface.

## ⚠️ Hard constraint — do NOT reintroduce Claude subscription-OAuth

Claude usage is read by driving the **official `claude` CLI's `/usage` panel** in a
pseudo-terminal and parsing it (`ClaudeUsageCLIProbe` + `ClaudeUsageParser`). This is a
deliberate, load-bearing choice.

**Do not** "improve" this by calling `api.anthropic.com/api/oauth/usage`, reusing the
`Claude Code-credentials` Keychain token, minting tokens via a "Sign in with Claude" OAuth
flow, or spoofing a `claude-code` User-Agent. Anthropic's Feb 2026 policy **prohibits**
third-party use of subscription OAuth credentials and **enforces it server-side** (it broke
OpenClaw/OpenCode/Roo/Goose and CodexBar's OAuth path). That approach is both non-compliant
and non-functional. The earlier git history contains a removed OAuth/Keychain implementation
— that was retired for these reasons; do not resurrect it.

The compliant principle: let the **official client** make the request; we only read its
output. `/usage` is a free status fetch (no model call), so polling it costs no usage.

## Architecture

- `Sources/HeadroomCore` — all testable logic (no SwiftUI):
  - `Models/` — `UsageSnapshot`/`UsageWindow` (with `resetLabel`), `FailureReason`,
    `Freshness` (`.pending`/`.live`/`.stale`), `UsageProvider` protocol, `Countdown`.
  - `Providers/` — `ClaudeProvider` (via `ClaudeUsageSource`), `ClaudeUsageCLIProbe`
    (openpty + posix_spawn), `ClaudeUsageParser`, `CodexProvider` (+ `UsageHTTPClient`,
    DTOs), `RedirectBlocker`.
  - `Credentials/` — `CredentialStore` (Codex-only), `CodexAuthReader`, `Redaction`.
  - `Engine/` — `PollingEngine`, `UsageStore` (`@MainActor @Observable`).
  - `Settings/` — `Preferences` (UserDefaults), `LaunchAtLogin` (SMAppService).
- `Sources/HeadroomApp` — SwiftUI `MenuBarExtra(.window)` shell + adaptive popover (Liquid
  Glass on Tahoe, native material on Sequoia), cards, settings, menu bar label.
  `AppComposition` is the one place providers are wired.

Data flow: `PollingEngine` → `UsageStore.refreshAll()` fetches providers concurrently →
merges with continuity → menu bar label + popover bind to the `@Observable` store.

## Commands

```bash
swift build                        # HeadroomCore + Headroom
swift test                         # unit suite (fast, all mocked — no CLI/network/Keychain)
swift run Headroom --probe-claude  # diagnostic: prints live parsed /usage windows
./Scripts/build-app.sh             # → Headroom.app (LSUIElement), then: open Headroom.app
```

Building requires Xcode 26 / Swift 6.3. The app targets macOS 15+ on Apple silicon; a real
macOS 15 Apple-silicon runtime smoke is required before advertising Sequoia support. Claude
requires the `claude` CLI logged in; Codex requires `~/.codex/auth.json`.

## Conventions

- **Swift 6 strict concurrency is on.** `CredentialStore` is an `actor`; `UsageStore` is
  `@MainActor`; models and providers are `Sendable`. Keep it compiling clean under complete
  concurrency checking.
- **Everything is injectable for tests.** Providers take a source/HTTP/`now` seam; tests use
  fixtures + mocks (`Mocks.swift`) and never touch the real CLI, network, or Keychain. Add
  new behavior behind a seam and test it the same way.
- **Failures are the typed `FailureReason` enum, never interpolated errors** (no token/PII
  leakage). Providers never throw — they return a stale snapshot (`.stale(for:reason:)`).
- **Reset times are shown verbatim** via `UsageWindow.resetLabel` when the source provides
  text (Claude); Codex uses a computed countdown from `resetsAt`.
- Comments cite plan/decision anchors (e.g. `KTD7`, `R12`) as WHY notes — keep those; drop
  comments that just narrate WHAT the next line does.
- Don't commit build artifacts (`.build/`, `Headroom.app/`) — already gitignored.

## Gotchas

- **`ClaudeUsageParser` is pinned to the current `/usage` layout.** It keys on stable shapes
  ("Current session", "Current week (…)", "N% used", "Resets …"), not line positions, and
  fails safe (empty → transient stale). If Claude redesigns the panel, update the parser and
  the fixture in `ClaudeProviderTests.swift`; use `--probe-claude` to see the live panel.
- **PTY probe robustness is intentional** — hard deadlines, guaranteed process-group kill,
  quiet-period capture across re-renders, login-shell PATH resolution (works from a bare
  Finder-launch env), off-main-actor. Preserve these when editing `ClaudeUsageCLIProbe`.
- **ANSI stripping uses ICU escapes (`\x1B`), not Swift's `\u{1B}`** — the latter silently
  fails inside `.regularExpression`.
- Each Claude poll spawns a full `claude` session (~20–30s). Fine at the 5-min default; don't
  poll aggressively.

## Follow-ups

See `BUGS.md` for deferred items (Codex field-name verification, backoff, app icon, Xcode
signing for persistent permission grants).
