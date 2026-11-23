# Phase A Grounding: Headroom × T3 Codex Shadow Homes, Menu Bar Provider Icons, and T3-Managed Antigravity

Repo path: `~/Git/headroom` (branch: `t3-codex-shadow-homes`, base commit `132508b` / v1.8).
Toolchain on this Mac: Swift 6.4.2 Command Line Tools (`swift build --target HeadroomCoreTests && swift test --skip-build` passes; full Xcode / `xcodegen` is not installed, so SwiftUI targets fail on missing `SwiftUIMacros` plugin). Every unit of core logic MUST live in `HeadroomCore` and be thoroughly testable via `HeadroomCoreTests`, while `HeadroomApp` SwiftUI/AppKit changes stay surgical, well-typed, and strictly aligned with existing symbols.

---

## 1. Local T3 Code & Machine Facts (Verified Live)

### `~/.t3/userdata/settings.json`
Contains `providerInstances` keyed by instance ID:
```json
{
  "providerInstances": {
    "codex_pro100": {
      "driver": "codex",
      "displayName": "Pro100",
      "enabled": true,
      "config": {
        "shadowHomePath": "~/.codex-t3/pro100",
        "binaryPath": "/opt/homebrew/bin/codex",
        "setupMode": "existing"
      }
    },
    "codex_pro200": {
      "driver": "codex",
      "displayName": "Pro200",
      "enabled": true,
      "config": {
        "binaryPath": "/opt/homebrew/bin/codex",
        "shadowHomePath": "~/.codex-t3/pro200",
        "setupMode": "existing"
      }
    },
    "codex": {
      "driver": "codex",
      "enabled": false
    },
    "antigravity": {
      "driver": "antigravity",
      "displayName": "Antigravity",
      "enabled": true
    }
  }
}
```
- Only **regular** Codex instances (`driver == "codex"`, `enabled == true`, non-empty `config.shadowHomePath`) have readable shadow homes. Managed Codex instances keep credentials encrypted inside T3's own data and have no readable `shadowHomePath`.
- Each shadow home (e.g. `~/.codex-t3/pro100`, `~/.codex-t3/pro200`) has symlinks into `~/.codex` for shared config/skills/sessions, while `auth.json` is a **real file** (`0600`, owner-only; T3 rejects symlinked `auth.json`).
- `~/.codex/auth.json` is NOT fixed — it tracks whichever account is active in the Codex desktop app.
- Live `/opt/homebrew/bin/codex` is `codex-cli 0.171.0`.
- Live probe of `CODEX_HOME=<shadow> /opt/homebrew/bin/codex app-server` using newline-delimited JSON-RPC (`initialize` → `initialized` notification → `account/read` `{refreshToken: false}` → `account/rateLimits/read` `{excludeResetCreditDetails: true}`):
  - Succeeds on both `pro100` (~1.0s) and `pro200` (~2.4–3.6s) without Headroom reading/refreshing tokens directly.
  - `initialize` returns `{ codexHome, platformFamily, platformOs, userAgent }`.
  - `account/read` returns `{ account: { type: "chatgpt", email, planType ("prolite"|"pro"|...), workspaceName }, userId, requiresOpenaiAuth, workspaceRouting: { chatgptAccountId } }`.
  - `account/rateLimits/read` returns:
    - `ordinaryUsageAllowed: Bool?`
    - `accountId: String?`
    - `rateLimits: { limitId, limitName, normalModelSlug, primary: { usedPercent, windowDurationMins, resetsAt }, secondary: { ... }?, credits: { hasCredits, unlimited, balance }?, planType }`
    - `rateLimitsByLimitId: [String: RateLimitSnapshot]?` (multi-bucket map keyed by `limit_id`, e.g. `"codex"`, plus any Spark/model-specific buckets)
    - `rateLimitResetCredits: { availableCount: Int, credits: [...]? }?` (with `excludeResetCreditDetails: true`, `availableCount` is still populated while `credits` is `null`).

### T3-Managed Antigravity (Verified Live)
- Binary path: `~/.t3/tools/antigravity-acp/darwin-<arch>/active.json` contains `{"releaseId":"<hash>"}` → binary at `~/.t3/tools/antigravity-acp/darwin-<arch>/versions/<releaseId>/antigravity` (v1.5.13 on this Mac; arch is `arm64` on Apple Silicon, `x64` on Intel).
- Data dir: `~/.t3/userdata/providers/antigravity/<sha256(instanceId)>/antigravity-acp/` (for instanceId `"antigravity"`, `sha256("antigravity") == "ac0a3dfd6dddb20962cecff6ee5fe65e19d3923be20e52c5ab52ff877f7e4c32"`), containing `antigravity-oauth-token` (`0600`).
- Local `~/.local/bin/agy` exists (v1.5.13) but `~/.gemini/antigravity-cli` is NOT signed in, so `agy -p /usage` prints `"Authentication required. Please visit the URL to log in:"` on stderr.
- Live probe verified: creating a Headroom-owned probe `HOME` directory with `.gemini/antigravity-cli` symlinked to T3's `antigravity-acp` directory and running `HOME=<probeHome> <t3-antigravity-binary> -p /usage --output-format json` and `-p /credits --output-format json` succeeds with `rc=0`, `status: "SUCCESS"`, `num_turns: 0`, `total_tokens: 0`, returning all 4 Antigravity quota buckets (`gemini-weekly`, `gemini-5h`, `3p-weekly`, `3p-5h`) and `remaining_credits` — zero separate sign-in, zero token file reads/copies, zero writes into T3's settings.

### Existing User Defaults on This Mac
- `/Applications/Headroom.app` is installed and `com.kylezantos.headroom` already has `providerAccounts.v1` stored. Auto-discovery / reconciliation MUST work seamlessly both on fresh installs and on existing `UserDefaults` without overwriting user-renamed labels or resurrecting explicitly removed/detached accounts.

---

## 2. How Headroom Currently Works

### A. Codex Auth, Credentials & Usage Fetching
- `Sources/HeadroomCore/Credentials/CodexAuthReader.swift`: `CodexAuthFileReader(path:)` defaults to `~/.codex/auth.json`. Verifies POSIX mode `(perms & 0o077) == 0` via `AccountStorage.credentialFilePermissionsAreSafe(at:)`. Parses `tokens.{access_token, refresh_token, account_id, id_token}` and `last_refresh`; base64url-decodes `id_token` payload locally only for normalized `email`.
- `Sources/HeadroomCore/Credentials/CredentialStore.swift`: Actor wrapping one `CodexAuthReading`; returns `CodexSession(accessToken, accountEmail, identity: AccountIdentity.codex(accountID:))` — discarding `refreshToken`. Never refreshes tokens.
- `Sources/HeadroomCore/Providers/CodexProvider.swift`: Runs on `.concurrent` lane (`UsageProvider.pollingLane`). Calls `credentials.codexSession()`, sends `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer <accessToken>` via `RedirectBlockingHTTPClient`. On 401, re-reads `auth.json` once (retrying HTTP only if `accessToken` changed; otherwise `.codexSessionUnverified` non-permanent stale). On 200, decodes `CodexUsageDTO` (`rate_limit.{primary_window, secondary_window}`, `additional_rate_limits`, `plan_type`, `rate_limit_reset_credits`) using `CodexWindowClassifier` (keying off `limit_window_seconds`: 18000s → `.fiveHour`, 604800s → `.weekly`, other → `.other`). Brackets `AccountIdentity` before/after HTTP; mismatch/unreadable returns `.identityUnreadable(for: .codex)`.
- `Sources/HeadroomCore/Providers/StdioChildProcess.swift` + `CLIProcessThread.swift` + `CLIExecutableResolver.swift`: Production `posix_spawn` stack with `POSIX_SPAWN_SETSID` whole-group `SIGTERM`→`SIGKILL` cleanup, dedicated OS thread off Swift's cooperative pool, stdin `.pipe`/`.nullDevice`, stdout piped, stderr `.discard`/`.watch`.
- `Sources/HeadroomCore/Providers/ProviderAccountConfiguration.swift` & `AccountStorage.swift`: Maps `ProviderAccount` to `codexHomeDirectory` and `codexAuthFile`. Built-in (`.primary`) has `codexHomeDirectory == nil` (`~/.codex/auth.json`); extras get `~/Library/Application Support/Headroom/Accounts/codex/<safe-id>/`.
- `Sources/HeadroomApp/HeadroomApp.swift` (`AppComposition.makeCodexProvider`, L1453–1464): Short-circuits `account.isBuiltIn` directly to `CodexProvider(credentials: credentials)` (bypassing `ProviderAccountConfiguration.make(for:)`!). Diagnostic `--probe-codex` also hardcodes `~/.codex/auth.json` with no `--codex-home` flag.

### B. Multi-Account Model, Registry & Store Engine
- `Sources/HeadroomCore/Models/Account.swift`: `AccountID` (`.primary` or UUID), `AccountKey(providerID, accountID)`, `ProviderAccount(id, providerID, label, isBuiltIn)`.
- `Sources/HeadroomCore/Settings/AccountRegistry.swift`: Persists `providerAccounts.v1`, `hiddenBuiltInAccounts.v1` (stop-tracked built-in tombstones), `primaryAccounts.v1` (Make Main), capacity = `testedEnvelope` (20). Always synthesizes `.primary` unless tombstoned alongside ≥1 extra.
- `Sources/HeadroomCore/Engine/UsageStore.swift` + `UsageStoreAccountLifecycle.swift` + `UsageStoreDefaultLogin.swift` + `DisplayAccounts.swift`:
  - Maintains `providers`, `accountsByProvider`, `snapshots`, `attachmentGenerations`, `DefaultLoginRecordStore` (`defaultLoginRecords.v1`), `DisplayMergePlanner`, `UsageContinuityCache` (`usageContinuitySnapshots.v2`), `NotificationCoordinator`, `BankedResetAcknowledgements`, `SessionReliabilityRecord`, widget export, and iPhone Companion v4 sync.
  - `DisplayMergePlanner`: If built-in `~/.codex` reports the same strong `AccountIdentity` as *exactly one* extra Codex account, built-in is hidden/merged into that extra row.
  - `UsageStore.addAccount` calls `accountStorage.ensureDirectories(for:)`; `UsageStore.removeAccount` calls `accountStorage.removeDirectories(for:)` which **recursively deletes the directory on disk**.
  - `UsageStore.stopTrackingBuiltInAccount` hides `.primary` via tombstone without touching disk.

### C. Settings, Setup UI & Presentation
- `Sources/HeadroomApp/UI/AccountsSettingsTile.swift` + `AccountsSettingsInteractions.swift`:
  - Clicking "Add Account…" immediately calls `store.addAccount(for:)` and opens Terminal via `SetupSessions.openSetup(for:)` to run `codex login`.
  - Removing an extra account warns "Its sign-in on this Mac is deleted with it" and calls destructive `store.removeAccount`.
  - Built-in account shows `"CLI login"` badge, offers `"Stop Tracking"` (non-destructive) when ≥1 extra exists, and `"Show CLI Account"` undo.
- `Sources/HeadroomApp/UI/SetupSessions.swift` + `CodexSetupViews.swift`:
  - `SetupSessions.prepareHandoff` calls `AccountStorage.ensureDirectories(for:)` for `!account.isBuiltIn` and writes `.headroom-setup-*` markers inside `accountDirectoryURL(for:)`.
  - `CodexSetupSession.codexHome(for:)` bypasses `ProviderAccountConfiguration` and calls `AccountStorage.codexHomeDirectoryURL(for:)` directly.
- `Sources/HeadroomCore/Models/PlanLabelPresentation.swift`: Already maps Codex `"prolite"` → `"Pro Lite"` and `"pro"` → `"Pro"`.
- `Sources/HeadroomApp/HeadroomApp.entitlements`: Host app is **NOT sandboxed** (can read `~/.t3/...`, `~/.codex-t3/...`, spawn `/opt/homebrew/bin/codex` and T3's `antigravity`). Widget extension IS sandboxed and only reads the App Group snapshot written by the host app.

### D. Menu Bar Rendering & Settings
- `Sources/HeadroomCore/Engine/UsageStore.swift`: `menuBarMeters: [MenuBarMeter]` returns 1 meter in `.auto` mode or 1 meter per `selectedMenuBarProviders` (each from that provider's main account). Each `MenuBarMeter` carries `summary` (which includes `providerID: ProviderID?`, `text`, `severity`, `needsAttention`, `isNeutral`, `detail`, `percentageMode`), `fill: Double?` (`UsageMeterReading(window:).fraction(for: usagePercentageMode)` — note: `.remaining` = fraction left, `.used` = fraction used!), `awaitingFirstReading`, `isLiveReading`, `sourceAccountKey`.
- `Sources/HeadroomCore/Models/MenuBarLabelGeometry.swift`: Pure SwiftUI/AppKit-free layout calculator (currently assumes fixed `vesselWidth = 11`, `height = 18`, `vesselTextGap = 7`, `meterGapWithPercentage = 16`, `meterGapIconOnly = 8`, `attentionDotDiameter = 5`, `attentionDotInset = 2`).
- `Sources/HeadroomCore/Models/MenuBarPalette.swift`: Explicit light/dark menu bar colors (`ink`, `neutralLiquid`, `liquid(for: severity)`, `severityInk(for:)`).
- `Sources/HeadroomApp/UI/MenuBarLabel.swift` + `VesselGlyph.swift` + `ProviderLogoView.swift`:
  - `MenuBarLabelRenderer.render(...)` draws every meter into one `NSImage` (height 18pt) using `VesselGlyph.menuBarImage(...)` (11×18 capsule filled from bottom with severity color, optional sine-wave `wavePhase` slosh, ghost halftone, 4-frame print/crossfade ink).
  - Bundled brand SVGs live in `Sources/HeadroomApp/Resources/BrandIcons/`: `claude-color.svg`, `codex-color.svg`, `antigravity-{dark,light}.svg`, `copilot-{dark,light}.svg`, `cursor-{dark,light}.svg`, `grok-{dark,light}.svg`, `opencode-{dark,light}.svg`. `ProviderStyle.svgResourceName(for:scheme:)` maps every `ProviderID` to its SVG; `HeadroomBrandMark.markSize(for:slot:)` computes optically mass-corrected width/height!
  - `Sources/HeadroomApp/UI/SettingsPanes.swift` (`MenuBarSettingsPane`) & `MenuBarPillArranger.swift` (`PillShelfModel` / `MenuBarPillMetrics`): renders the live menu bar preview, `"Display"` swatches (`Pills + percentages` vs `Pills only`), and `"Your Pills"` drag-and-drop arranger (cards sized down to 62pt floor with `.standard` / `.compact` `MenuBarPillMetrics`).

### E. Antigravity Discovery & Probing
- `Sources/HeadroomCore/Providers/AntigravityUsageSource.swift`:
  - `AntigravityCLI.resolveExecutable()` searches `PATH` + `[/opt/homebrew/bin/agy, /usr/local/bin/agy, ~/.local/bin/agy]`.
  - `AntigravityCLIUsageSource` spawns `agy --version` (min 1.5.9), `agy -p /usage --output-format json`, `agy -p /credits --output-format json` via `StdioChildProcess` with `strippedEnvironment` (strips `GEMINI_API_KEY`, `GOOGLE_API_KEY`, etc.), sticky `stop` on non-zero-turn answers, sticky `signedOut` on stderr sign-in prompt lines.
  - `AntigravityConnection.swift` runs `agy acp --login` when sign-in is needed.

---

## 3. Hard Constraints & Gotchas Any Design MUST Honor

1. **NEVER delete, `chmod`, or write markers into external/T3-owned directories**: `AccountStorage.removeDirectories(for:)` recursively deletes non-built-in account directories (`FileManager.default.removeItem`). `AccountStorage.ensureDirectories(for:)` `chmod`s to `0o700`. `AccountStorage.setupCompletionMarker` writes marker files inside account directories. External `CODEX_HOME` directories (and T3's `antigravity-acp` directory) MUST be strictly protected from all destructive or mutating operations by construction.
2. **NEVER print, log, copy, or commit token values or `auth.json` / `antigravity-oauth-token` contents**. Never modify `~/.t3/userdata/settings.json`, `~/.codex-t3/*`, `~/.t3/userdata/providers/antigravity/*`, or `~/.codex`.
3. **NEVER refresh Codex OAuth tokens directly inside Headroom**: Codex rotates refresh tokens on use. Either delegate auth+usage reads to `CODEX_HOME=<home> codex app-server` (letting Codex refresh safely with its own lock) or read `auth.json` strictly read-only (never refreshing ourselves).
4. **Backward compatibility (`Release162ProviderAccount`)**: Existing tests (`DefaultLoginRecordsLaunchTests`, `RememberedAccountTests`) assert `providerAccounts.v1` decodes as `[Release162ProviderAccount]`. New fields on `ProviderAccount` MUST be optional (`encodeIfPresent`) or stored in a separate versioned store.
5. **iOS target compilability**: `project.yml` compiles all of `Sources/HeadroomCore/{Models,Notifications,Settings,Sync,Widgets}` into `HeadroomIOS` and `HeadroomIOSWidgets` (excluding only `LaunchAtLogin.swift` and `WidgetSnapshotProjector.swift`). Anything placed in `Models/` or `Settings/` MUST remain Foundation-only (no AppKit, no `Darwin`/`posix_spawn`, no Engine/Providers imports).
6. **Stable `AccountID`s across 6 persisted subsystems**: `UsageContinuityCache`, `DefaultLoginRecordStore`, `UseItUpLedger`, `BankedResetNotificationBaseline`, `BankedResetAcknowledgements`, and Companion v4 sync all key by `AccountID`. Auto-discovered T3 shadow homes MUST get deterministic/persisted `AccountID`s so relaunches never wipe history or re-fire notifications.
7. **Built-in `.primary` bypass & coexistence**: `AppComposition.makeCodexProvider` currently short-circuits `account.isBuiltIn` straight to `~/.codex/auth.json`. And `~/.codex/auth.json` tracks the Codex desktop app switcher, so when T3 shadow homes are configured/defaulted, `~/.codex` should NOT pollute the monitored accounts (e.g., auto-stopping-tracking built-in when T3 shadow homes are discovered or cleanly separating external homes from `~/.codex` while keeping non-T3 users working!).
8. **No `/tmp` for test homes on macOS**: `/tmp` is a symlink to `/private/tmp`, which breaks Codex path checks. Tests must use resolved paths (`FileManager.default.temporaryDirectory.resolvingSymlinksInPath()` or scratch directories).
9. **Menu bar geometry single source of truth**: `MenuBarLabelGeometry` owns both width measurement and item placement so nothing clips (especially the trailing 3pt attention-dot overhang). Changing glyph widths for provider icons MUST flow through `MenuBarLabelGeometry` and keep `MenuBarPillMetrics` / `PillCardGeometry` accurate!
10. **Antigravity no-turn safety invariants**: T3-managed Antigravity MUST preserve every `AntigravityCLIUsageSource` safety guard (version gate ≥1.5.9, `provesNoTurn`, size cap, sticky `stop`, sticky `signedOut` on stderr prompt, `strippedEnvironment`, whole-group `SIGTERM`→`SIGKILL`).
