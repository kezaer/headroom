# Synthesized Architecture: Headroom × T3 Shadow Homes, Filled Provider Menu Bar Icons, and T3-Managed Antigravity

## Problem

Headroom v1.8 treats every non-built-in account as a Headroom-owned folder under `Application Support/Headroom/Accounts/` that Headroom creates, `chmod`s, writes setup markers into, and recursively deletes on removal. On a Mac running T3 Code, this causes three gaps:

1. **Multi-account Codex without separate logins or token races**: T3 Code already maintains regular Codex shadow homes (`~/.codex-t3/pro100`, `~/.codex-t3/pro200`) registered in `~/.t3/userdata/settings.json`, while `~/.codex/auth.json` drifts with the Codex desktop app switcher. Headroom must auto-discover T3 shadow homes, allow adding/removing custom `CODEX_HOME` folders and separate Headroom logins cleanly in Settings, preserve user labels and hide decisions across rescans, hide `~/.codex` while T3 homes are active (with an opt-in toggle), never write/chmod/delete external directories, and never refresh tokens directly in Swift.
2. **Identifiable filled provider menu bar icons (with multi-sub corner badges)**: Generic capsules make providers indistinguishable in the menu bar. Each provider pill must draw its own bundled brand silhouette (with the **OpenAI round blossom** replacing Codex's cloud icon in both menu bar and popover) filled bottom-up in Headroom's severity palette (green / amber / red), supporting editable short corner badges (e.g. `100` / `200`) when multiple accounts of the same provider appear in the menu bar.
3. **Zero-reauth T3-managed Antigravity**: Headroom must automatically discover T3's managed Antigravity binary (`~/.t3/tools/antigravity-acp/darwin-<arch>/active.json`) and signed-in data directory (`~/.t3/userdata/providers/antigravity/<sha256(instanceId)>/antigravity-acp`) via a Headroom-owned probe `HOME` symlink, preserving every no-turn safety guard and allowing users to switch between `T3 Code (auto)` and `System agy CLI`.

Hard constraints honored:
- `providerAccounts.v1` retains exact Release 1.6.2 wire compatibility (`Release162ProviderAccount` decoders pass by construction).
- `Sources/HeadroomCore/{Models,Notifications,Settings,Sync,Widgets}` stay Foundation-only (iOS-compilable).
- Account IDs remain deterministic across all 6 persisted stores; absolute home paths never leak to widgets or iPhone companion payloads.
- Under CLT-only macOS 27.2 (`SwiftUIMacros` unavailable), all core logic lives in `HeadroomCore` and is verified via `swift build --target HeadroomCoreTests && swift test --skip-build`, while `HeadroomApp` SwiftUI/AppKit edits remain minimal, exact, and caller-verified.

## Usage (caller's view)

```swift
// 1. Composition root (AppComposition.store): scan T3 once before building providers.
let t3 = T3Installation()
T3DiscoveryCache(defaults: launchDefaults).record(t3.scanCodexHomes())
let registry = AccountRegistry(defaults: launchDefaults)
let store = UsageStore(
    /* ... */,
    accountRegistry: registry,
    borrowedHomes: .live(t3: t3),
    providerFactory: { provider(for: $0, credentials: credentials) }
)

// 2. Unified Codex provider factory (no isBuiltIn short-circuit):
switch ProviderAccountConfiguration.make(for: account).codexTransport {
case .authFile(let url):  CodexProvider(credentials: CredentialStore(codexReader: CodexAuthFileReader(path: url)), accountID: account.id)
case .appServer(let home): CodexAppServerProvider(accountID: account.id, home: home)
case nil:                  UnavailableAccountProvider(account: account)
}

// 3. Settings -> Accounts -> Codex & Antigravity:
_ = store.addExternalCodexHome(at: pickedURL, label: draftLabel)
store.rescanBorrowedHomes()
store.renameAccount(key, to: "Pro 100")
store.setMenuBarBadge("100", for: key)
await store.removeAccount(key)                 // borrowed -> hide/forget only; disk APIs unreachable
store.setTracksCLIDefaultAlongsideT3(true)
store.setAntigravitySourcePreference(.autoPreferT3)

// 4. Menu bar: each meter carries its resolved glyph + optional short corner badge.
store.setMenuBarIconStyle(.providerIcons)
MenuBarLabelRenderer.render(meters: store.menuBarMeters, showsPercentage: store.showMenuBarPercentage, palette: palette)
```

## Shape

### Core data structures & invariants
1. **Structural ownership (`AccountOrigin` + compile-time storage gates)** (`per model-the-domain`, `per encode-lessons-in-structure`):
   - `AccountOrigin` (`.cliDefault`, `.headroomOwned`, `.borrowed(BorrowedHome)`) stored on `ProviderAccount`; `isBuiltIn` becomes a computed property (`origin == .cliDefault`).
   - `HeadroomOwnedHome` (`init?` fails unless `origin == .headroomOwned`) gates `AccountStorage.ensureDirectories(for:)` and `removeDirectories(for:)`. `SetupCapableAccount` (`.cliDefault` | `.owned(HeadroomOwnedHome)`) gates setup markers and Terminal handoffs. Deleting or chmodding a borrowed home is a compile error, not a runtime check.
   - `CanonicalHomePath` enforces textual canonical invariants in `Models/` (Foundation-only); filesystem `realpath` + validation live in `BorrowedHomePaths.canonicalize` (`Providers/`).
   - `AccountID.borrowedHome(_ path: CanonicalHomePath)` uses deterministic pure-Swift FNV-1a-64 (`"home-<16-hex>"`), guaranteeing identical IDs across launches and deduplication by path.
2. **Two single-writer stores merged purely on read** (`per separate-before-serializing-shared-state`, `per make-operations-idempotent`):
   - `t3CodexDiscovery.v1` (`T3DiscoveryCache`): written ONLY by the scanner from `T3CodexScan` (`.notInstalled` | `.found([T3CodexHome])` | `.unreadable`). `.unreadable` never mutates state.
   - `borrowedCodexHomes.v1` (`BorrowedHomeDecisions`): written ONLY by user actions through `AccountRegistry` (`manualHomes`, `labels`, `menuBarBadges`, `hidden`, `tracksCLIDefaultAlongsideT3`).
   - `providerAccounts.v1`: stores only `PersistedAccount` (exact Release 1.6.2 struct; failable `init?` returns `nil` for `.borrowed`).
   - `BorrowedHomeRoster.resolve(discovered:decisions:)` purely merges the two stores inside `AccountRegistry.accounts(for:)`. `~/.codex` suppression (`suppressesCLIDefault`) is derived dynamically on every read and never written to `hiddenBuiltInAccounts.v1`.
   - `UsageStore.reconcileAccounts(for: .codex)` diffs attached providers vs desired roster: newly absent T3 rows **detach without purging** continuity/ledgers/banked-reset baselines (grafted from Candidate A / Judge #2) so toggling a T3 instance off and back on restores history cleanly.
3. **Codex transport & shared window domain** (`per boundary-discipline`):
   - `ProviderAccountConfiguration.make(for:)` derives `codexTransport`: `.authFile(url)` for `.cliDefault` and `.headroomOwned` (preserving proven `wham/usage` for non-T3/Codex.app users), `.appServer(home)` for `.borrowed`.
   - `CodexAppServerProvider` runs on `.serial("codex-app-server")` using a closed 4-message enum `CodexAppServerMessage` (`initialize`, `initialized`, `account/read {refreshToken: false}`, `account/rateLimits/read {excludeResetCreditDetails: true}`) with before/after `account/read` identity bracketing, `StdioChildProcess` (`POSIX_SPAWN_SETSID`, whole-group `SIGTERM`->`SIGKILL`, 256 KB cap, Headroom-owned cwd, `OPENAI_API_KEY`/`CODEX_API_KEY`/`OPENAI_BASE_URL` stripped). Never calls `refreshToken: true` directly and never reads `auth.json`.
   - Verified live on this Mac: `codex app-server`'s `accountId` / `workspaceRouting.chatgptAccountId` equals `auth.json`'s `tokens.account_id` for both `Pro100` and `Pro200`.
   - Both transports convert wire DTOs into one shared `CodexLimitBucket` / `CodexLimitWindow` -> `CodexWindowMapping.windows(_:now:)` so window classification, Spark counters (`rateLimitsByLimitId`), and reset handling live in one place.
4. **Menu bar filled provider icons + OpenAI blossom + editable multi-sub corner badges**:
   - Replace `Sources/HeadroomApp/Resources/BrandIcons/codex-color.svg` and `Sources/HeadroomSharedResources/BrandIcons.xcassets/CodexBrandIcon.imageset/codex-color.svg` with the **OpenAI round blossom** SVG (keeping `HeadroomBrandMark` and `BrandColorValuesTests` / `BrandMarkInkTests` updated and green).
   - `MenuBarIconStyle` (`.providerIcons` default, `.capsules`), `MenuBarGlyphKind` (`.capsule` | `.providerMark(ProviderID)`), and `MenuBarMeter` (`glyph: MenuBarGlyphKind`, `badge: String?`) live in `HeadroomCore/Models/`.
   - **Width ceiling ≤ 16pt** (grafted from Candidate A / Judge #3): `MenuBarGlyph.size(of:)` clamps mark dimensions to `maxDimension = 15.5pt` (`ceil` ≤ `16pt`) derived from `HeadroomBrandMark.inkAspect`, guaranteeing 6 compact Settings pill cards fit within the 62pt floor (`8 + 16 + 4 + 33 = 61 ≤ 62pt`).
   - **Critical-tinted empty track** (grafted from Candidate A): `MenuBarPalette.markTrack(for:isNeutral:)` uses neutral track ink (`white@0.28` dark / `black@0.24` light) normally and shifts to critical red tint (`0.30` / `0.26`) at `.critical`, so even a 0% critical mark reads red.
   - **Severity fill (Option B)**: Fill color is always `palette.liquid(for: severity)` (green/amber/red) rising bottom-up inside the SVG alpha mask, rendered by one unified `MenuBarGlyphImage` supporting slosh wave, halftone ghost, and 4-frame print/crossfade identically for capsules and marks.
   - **Multi-subscription corner badges**: Each `MenuBarMeter` carries optional `badge: String?` (default derived from account label via `MenuBarAccountBadge.defaultBadge(for:index:)` — e.g. `"Pro100"` → `"100"`, `"Pro200"` → `"200"`, else `"1"`, `"2"` — and editable per account in Settings via `store.setMenuBarBadge(_:for:)` persisted in `BorrowedHomeDecisions` / `Preferences`). When a selected menu bar provider has >1 visible account and `showAllProviderAccountsInMenuBar` (enabled by default when multi-account Codex is active, toggleable in Settings → Menu Bar), `UsageStore.menuBarMeters` emits one meter per visible account with its `badge` rendered as a crisp bottom-right corner chip, measured inside `MenuBarLabelGeometry` so neither the corner badge nor the top-right attention dot clips.
5. **T3-managed Antigravity auto-discovery** (`per boundary-discipline`, `per make-operations-idempotent`):
   - `AntigravitySourcePreference` (`.autoPreferT3` default, `.systemCLI`) stored in `Preferences` and exposed in Settings → Accounts → Antigravity.
   - `T3Installation.antigravity()` resolves active release from `~/.t3/tools/antigravity-acp/darwin-<arch>/active.json` -> `versions/<releaseId>/antigravity` + enabled `driver == "antigravity"` instance (`"antigravity"` preferred, then sorted) -> `<sha256(instanceID)>/antigravity-acp`, checking `fileExists(antigravity-oauth-token)` (stat-only, grafted from Candidate A — NEVER reading bytes!) before selecting T3.
   - `AntigravityLaunchResolver` pairs executable + `AntigravitySignInHome` (`.t3Managed(instanceID, probeHome)` | `.system`) and idempotently maintains `Application Support/Headroom/AntigravityHomes/<hash>/.gemini/antigravity-cli` via atomic temp-symlink + `rename(2)` (refusing non-symlinks, never writing into T3's directory).
   - `AntigravityCLIUsageSource` scopes sticky `signedOut` per `signInHome.memoryKey` (`"system"` vs `"t3:<id>"`, migrating legacy Bool as `"system"`), preserving all existing no-turn safety guards unchanged.

## Synthesis decision

- **Base**: **Candidate 2 ("borrowed homes", Claude Opus 5.5)** — scored 19/25 vs Candidate 1's 15/25 by the Phase C cross-judge and confirmed by independent review. Its single-writer dual-store architecture (`t3CodexDiscovery.v1` + `borrowedCodexHomes.v1` merged via `BorrowedHomeRoster`, leaving `providerAccounts.v1` strictly Release 1.6.2-safe) and compile-time storage gates (`HeadroomOwnedHome`, `SetupCapableAccount`) eliminate Candidate 1's split-ownership and runtime-guard hazards structurally.
- **Grafts ported from Candidate 1 (Gemini 4 Neon) + Cross-Judge**:
  1. `fileExists(antigravity-oauth-token)` stat-only precondition in `T3Installation.antigravity()` so an unsigned-in T3 Antigravity install never shadows a working system `agy`.
  2. Non-purging detach when a T3 Codex instance disappears or is disabled, preserving continuity/ledgers/banked-reset baselines across temporary disables.
  3. Menu bar glyph width ceiling ≤ 16pt (`maxDimension = 15.5pt`) + critical-tinted empty mark track (`markTrack(for:isNeutral:)`), fixing Candidate 2's 63pt Copilot card overflow.
  4. Unit test pinning zero leakage of `BorrowedHome.path` into `WidgetSnapshotEnvelope` and Companion v4 sync payloads.
- **User product decisions folded in**:
  1. Option B (Severity fill: green / amber / red) for menu bar icons.
  2. OpenAI round blossom SVG replacing Codex's cloud icon in BOTH menu bar and popover.
  3. Multi-subscription menu bar pills with editable corner badge chip (e.g. `100` / `200`).
  4. Redesigned Settings → Accounts UI with explicit Codex source picker (T3 Code / Existing CLI folder / Separate Headroom login), `Also track ~/.codex` toggle, and Antigravity `T3 Code (auto)` / `System agy CLI` switcher.
- **Rejected**:
  - Candidate 1's `externalHome` stored inside `providerAccounts.v1` (risks v1.8 rewrite dropping the field and causing duplicate IDs).
  - Candidate 1's `refreshToken: true` explicit RPC retry (risks racing with T3's own refresh token rotation).
  - Candidate 1's separate `ProviderGlyph` renderer duplicating `VesselGlyph` caching/wave/ghost logic.
  - Candidate 3 (`codex_pro200` / `gpt-6.2-sol`) dropped out in Phase B due to a missing local execution host in its Codex session.

## Tradeoffs accepted

- We accept **two Codex transports derived by `AccountOrigin`** (`.authFile` for built-in/owned, `.appServer` for borrowed) in exchange for zero regressions for Codex.app-only users without the CLI while giving borrowed T3 homes safe Codex-managed auth/refresh.
- We accept **short-lived `codex app-server` spawns per poll on `.serial("codex-app-server")`** (~1–3.6s/account) in exchange for zero long-lived background daemon supervision.
- We accept **path-derived `AccountID.borrowedHome(path)`** (moving a shadow home path starts fresh history) in exchange for zero ID-map drift and guaranteed deduplication between T3 discovery and manual folder picks.
- We accept **keeping `AccountStorageManaging` app-side call sites small and carefully hand-verified** because CLT-only macOS 27.2 cannot compile SwiftUI targets (`SwiftUIMacros` absent), while 100% of domain/parser/registry/provider/geometry logic is compiled and tested under `HeadroomCoreTests`.

## Alternatives considered

1. **Storing external homes in `providerAccounts.v1` with runtime `ownsConfigDirectory` guards**: Lost due to two-writer conflicts between scanner and user, v1.8 downgrade field stripping, and reliance on every future caller remembering the runtime check.
2. **Read-only `auth.json` + `wham/usage` for T3 shadow homes**: Lost because inactive shadow homes stall in `.codexSessionUnverified` when access tokens expire, and Headroom would hold another app's token bytes.
3. **Brand-colored menu bar icons (Option A)**: Rejected by user in favor of Option B (severity green/amber/red) for immediate urgency legibility.

## Open questions and risks

- **Codex CLI app-server writes to shadow home**: Running `CODEX_HOME=<shadow> codex app-server` is the sanctioned Codex path (Codex manages its own locks/state), though Codex itself may refresh `auth.json` or touch `models_cache.json`/`log` inside the shadow home. Headroom itself performs zero writes there.
- **Full `.app` build requires Xcode**: On this CLT-only Mac, `HeadroomCore` + `HeadroomCoreTests` compile and pass via `swift build --target HeadroomCoreTests && swift test --skip-build`, and we can run a live CLI smoke test against `Pro100`, `Pro200`, and T3 Antigravity via a small Core test/probe harness; building the SwiftUI `.app` bundle will require Xcode (for `SwiftUIMacros`).

## Next implementation step

Implement the `HeadroomCore` foundation first (`AccountOrigin`, `HeadroomOwnedHome`/`SetupCapableAccount`, `BorrowedHomes` + `AccountRegistry` merge, `T3Installation`, `CodexLimits` + `CodexAppServerProvider`, `AntigravityLaunch` + `AntigravityCLIUsageSource`, `MenuBarGlyph` + `MenuBarLabelGeometry` + `MenuBarAccountBadge`, and `UsageStore` lifecycle), verify all new and existing `HeadroomCoreTests`, then apply the surgical `HeadroomApp` UI/asset updates and verify live probes against `Pro100`, `Pro200`, and T3 Antigravity.
