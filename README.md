# Headroom

A macOS menu bar app that shows how much of your AI-subscription usage remains — the
5-hour and weekly windows, when each resets, and a manually-entered monthly renewal
date — for **Anthropic Claude** and **ChatGPT/Codex**, side by side. It can also show
optional API dollar spend in a separate section for users who use metered OpenAI or
Anthropic APIs, and it bundles macOS widgets for small, medium, and large glanceable
desktop / Notification Center views.

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
- **API spend** — optional and off by default. When enabled in Settings, Headroom stores
  provider admin/reporting keys in the macOS Keychain and reads official cost-report
  endpoints for the selected period: OpenAI organization costs and Anthropic organization
  cost reports. These keys are separate from CLI subscription login, and Headroom never
  uses Claude subscription OAuth credentials for API spend.

## Build & test

```bash
swift build          # builds HeadroomCore + Headroom + HeadroomWidgets
swift test
./Scripts/build-app.sh   # produces Headroom.app (menu bar / LSUIElement), then: open Headroom.app
```

Requires Xcode 26 / Swift 6.3 on macOS 26 (Tahoe). The app bundle build also requires
`xcodegen` because macOS widget discovery expects a real Xcode app-extension target:
`brew install xcodegen`. Claude usage requires the `claude` CLI installed and logged in.
Codex subscription usage requires `~/.codex/auth.json`. API spend rows require the
relevant OpenAI/Anthropic admin keys entered in Settings. Diagnostic:
`swift run Headroom --probe-claude` prints the live parsed windows so you can confirm the
Claude path works on your machine.

## Structure

- `Sources/HeadroomCore` — testable logic: domain model, the Claude `/usage` PTY probe
  (`ClaudeUsageCLIProbe`) + parser (`ClaudeUsageParser`), the Codex provider, optional API
  spend providers, the polling engine/`@Observable` store, widget cache/export models,
  credentials, and preferences.
- `Sources/HeadroomApp` — the SwiftUI `MenuBarExtra` shell and the Tahoe / Liquid Glass
  popover, cards, settings, and menu bar label.
- `Sources/HeadroomWidgets` — the WidgetKit extension. It reads only the redaction-safe
  App Group cache written by the app; it never spawns `claude`, reads credentials, or
  calls provider endpoints.

## Widgets

Headroom includes one WidgetKit extension with size-specific layouts:

- **Small** — weekly percentage left for Claude and Codex, provider-by-provider.
- **Medium** — weekly and 5-hour usage for both providers.
- **Large** — adds reset, freshness, and renewal-date context.

Enable or pause widget data in Headroom Settings with **Share data with widgets**. Add,
remove, and resize widgets from macOS itself; Settings controls data export, not OS
installation. Widget data sharing uses the App Group `group.com.kylezantos.headroom`, so
the app and extension need matching entitlements under a stable Apple Development
signature for persistent real-world use. If the App Group is unavailable, widgets show a
setup state rather than reading provider credentials directly. Local manual-signed builds
also mirror the redaction-safe widget snapshot into the widget extension container as a
development fallback while App Group provisioning is being finished.

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

`./Scripts/build-app.sh` generates `Headroom.xcodeproj` from `project.yml`, builds a real
macOS app target with an embedded WidgetKit app-extension target, then signs both the app
and extension with the first local **Apple Development** identity it finds. If no Apple
signing identity is installed, it falls back to an ad-hoc signature so the app can still
launch locally.

To use a specific certificate:

```bash
security find-identity -v -p codesigning
HEADROOM_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./Scripts/build-app.sh debug
```

A stable Apple Development signature keeps macOS permission grants and App Group sharing
from re-prompting or failing after each rebuild. Leave App Sandbox **off** for the host
app (needed to spawn `claude` and read `~/.codex/auth.json`); the widget extension is
sandboxed and reads only the App Group cache. Notarization isn't needed for a locally
built/run app. Provide an app icon via `CFBundleIconFile` when you have one.

## Status

Working end-to-end: live Claude 5h/weekly windows via the CLI probe (verified against a
real account and from a bare launch environment), Codex via its endpoint, optional
OpenAI/Anthropic API spend rows, manual renewal dates, launch-at-login, the Tahoe popover,
widget cache export, and the bundled widget extension. Remaining polish is an app icon
and visual/VoiceOver smoke on the running app and widgets.
