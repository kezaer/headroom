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
    `Freshness` (`.pending`/`.live`/`.stale`), `UsageProvider` protocol, `Countdown`,
    `Account` (`AccountID`/`AccountKey`/`ProviderAccount`).
  - `Providers/` — `ClaudeProvider` (via `ClaudeUsageSource`), `ClaudeUsageCLIProbe`
    (openpty + posix_spawn), `ClaudeUsageParser`, `CodexProvider` (+ `UsageHTTPClient`,
    DTOs), `CodexConnection`, shared login-shell `CLIExecutableResolver`, `RedirectBlocker`,
    `AccountStorage` (per-account config homes).
  - `Credentials/` — `CredentialStore` (Codex-only), `CodexAuthReader`, `Redaction`.
  - `Engine/` — `PollingEngine`, `UsageStore` (`@MainActor @Observable`).
  - `Settings/` — `Preferences` (UserDefaults), `AccountRegistry` (persisted account
    catalog, max 5 per provider), `LaunchAtLogin` (SMAppService).
- `Sources/HeadroomApp` — SwiftUI `MenuBarExtra(.window)` shell + adaptive popover (Liquid
  Glass on Tahoe, native material on Sequoia), cards, settings, menu bar label.
  `AppComposition` is the one place providers are wired.

Data flow: `PollingEngine` → `UsageStore.refreshAll()` fetches providers concurrently →
merges with continuity → menu bar label + popover bind to the `@Observable` store.

### Multi-account (Jul 2026)

One provider can carry up to 5 signed-in accounts. Snapshots are keyed by `AccountKey`
(provider + account); one `UsageProvider` instance exists per account. The **built-in**
`.primary` account reads the CLI's default config (`~/.claude`, `~/.codex`) exactly as
before — zero migration for existing installs. **Extra** accounts get Headroom-owned
config homes under `~/Library/Application Support/Headroom/Accounts/…` and route the
same compliant paths there: the Claude probe runs with `CLAUDE_CONFIG_DIR` set, and
Codex reads the `auth.json` that official `codex login` wrote under that account's
`CODEX_HOME`. Sign-in is always a Terminal handoff to the official CLI
through the account-scoped `SetupSessionCoordinator` — the OAuth
constraint above applies to every account. The menu bar and widgets follow each
provider's primary account; the popover shows all accounts (compact meter density from
3 accounts up; the card list scrolls past a 640pt cap). Account management lives in
Settings → Accounts (`AccountsSettingsTile`); removal deletes the account's config home.

## Commands

```bash
swift build                        # HeadroomCore + Headroom
swift test                         # unit suite (fast, all mocked — no CLI/network/Keychain)
xcodebuild -project Headroom.xcodeproj -scheme HeadroomAppTests -destination 'platform=macOS' test
swift run Headroom --probe-claude  # diagnostic: prints live parsed /usage windows
./Scripts/build-app.sh             # → Headroom.app (LSUIElement), then: open Headroom.app
```

## Website DMG releases

For any request to prepare, publish, or ship a new public Headroom DMG, use the repo-local
`release-website-dmg` skill. Its authoritative runbook is
`docs/release/website-dmg-release.md`; it covers Developer ID signing, notarization, the
Sparkle appcast, portfolio deployment, and the required installed-app update acceptance test.
The public domain is `headroom.zantos.co`.

For a coordinated release that also includes TestFlight or App Store work, begin with
`docs/release/release-operations.md`. Keep macOS publication, Sparkle acceptance, TestFlight
upload, TestFlight availability, device acceptance, and App Review submission as separate states;
never collapse them into a generic “released.” Preflight dedicated test environments and manual
security/browser handoffs before publishing. Do not brute-force menu-bar UI, configure iPhone
Mirroring during a release, or use broad process termination to clean up QA copies.

Building requires Xcode 26 / Swift 6.3. The app targets macOS 15+ on Apple silicon; a real
macOS 15 Apple-silicon runtime smoke is required before advertising Sequoia support. Claude
requires the `claude` CLI logged in; Codex requires its CLI-managed `~/.codex/auth.json`.
When Codex auth is missing or rejected, the app delegates recovery to official `codex login`
in Terminal and never owns the browser callback, token refresh, or auth-file writes.

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
- **Codex window kind comes from `limit_window_seconds`, NOT the primary/secondary slot**
  (`#codex-window-kind`, `CodexWindowClassifier`). Slot position is plan-dependent: the
  `prolite` plan returns its *weekly* window in `primary_window` with `secondary_window: null`,
  so the old slot-based mapping mislabeled it "5-hour" and dropped the weekly row. Codex tags
  each window with `limit_window_seconds` (18000 = 5h, 604800 = 7d); classify off that, falling
  back to the slot only when the field is absent. Verify fixtures against a live capture with
  `--probe-codex` (or curl `chatgpt.com/backend-api/wham/usage` with the `~/.codex/auth.json`
  token) — the DTO field names in `UsageDTOs.swift` were originally speculative.
- **PTY probe robustness is intentional** — hard deadlines, guaranteed process-group kill,
  quiet-period capture across re-renders, login-shell PATH resolution (works from a bare
  Finder-launch env), off-main-actor. Preserve these when editing `ClaudeUsageCLIProbe`.
- **Codex setup must remain a CLI handoff.** Keep `CodexCLI.loginCommand`, provider recovery
  copy, Terminal execution, and clipboard fallback on `codex login`. Resolve the executable
  through `CLIExecutableResolver` so Finder launches still support Homebrew/NVM/asdf/mise
  installs; never place auth-file contents, provider responses, or caught errors in the
  generated script.
- **ANSI stripping uses ICU escapes (`\x1B`), not Swift's `\u{1B}`** — the latter silently
  fails inside `.regularExpression`.
- Each Claude poll spawns a full `claude` session (~20–30s). Fine at the 5-min default; don't
  poll aggressively. Configured Claude accounts are probed **serially in one Claude lane** while
  Codex/network work can overlap; the account cap and enforced 2-min interval floor bound cost.
- **Per-account isolation is env-var based and verified**: a fresh `CLAUDE_CONFIG_DIR`
  reports "Not logged in · Please run /login" and a fresh `CODEX_HOME` reports "Not
  logged in" — the CLIs never fall back to the default login. Don't "simplify" account
  probes by dropping the env override; that would silently read the wrong account.

## Follow-ups

See `BUGS.md` for deferred items (backoff, Xcode signing for persistent permission grants).
Codex field names are now verified against a live `wham/usage` capture — see the
`#codex-window-kind` gotcha above and `docs/solutions/codex-window-kind-mislabel.md`.
