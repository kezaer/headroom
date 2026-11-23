# Account Pre-Warm in Headroom

**Design handoff · macOS · 20 November 2026**

Place **Account Pre-Warm…** in the tracked account’s existing **•••** menu under **Settings › Accounts**. Open a compact account detail with the account name, provider and login source above the consent switch. The user grants permission for one particular subscription. Enabling a provider, adding a login, opening Settings, or fetching usage grants no permission to spend quota.

**Implementation order.** Build the coordinator, consent, account detail and fixture-backed runner first. Claude is the first candidate for a production adapter. Its five-hour trigger is documented. OpenCode Go has a documented trigger too. Codex and Antigravity have useful quota readers, but the evidence below does not establish an eligible first-turn trigger and a fully isolated execution path for either. A request deliberately consumes quota and is visible to the service. The attainable guarantee concerns the user’s workspace, local prompt history, resumable conversations and tool execution. No provider was exercised with a live model request in this research.

## Which window can an early request move?

| Provider | What starts or replenishes the relevant window | What Headroom can see | MVP decision |
|---|---|---|---|
| Claude | On plans with a session limit, the first message starts five hours. Account-assigned weekly resets keep their usual day and time. Verified Ultra accounts can lack the session cap. Usage is shared across Claude surfaces. | The official CLI usage report supplies a session percentage and sometimes a reset label. Its absence has several explanations. | First adapter candidate. Gate on an eligible session, a qualified CLI profile and trustworthy idle evidence. [Anthropic usage limits](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work) |
| Codex | OpenAI lists five-hour allowances for Plus and Standard Business. Its current pricing guide says Pro has no five-hour limit. Model, context and tier affect cost. The app-server contract documents reset timestamps, without defining a first-turn start or a canonical idle encoding. | Primary and secondary buckets, optional model-specific buckets and optional timestamps. Window duration matters. A primary bucket can be a different duration. | Capability unavailable until a specific plan and CLI demonstrate the benefit and isolation. The “Pro” rows in v7 are presentation fixtures. [Codex pricing](https://developers.openai.com/codex/pricing/) · [App-server rate limits](https://developers.openai.com/codex/app-server/) |
| Antigravity | Google describes five-hour replenishment for AI Pro/Ultra, subject to weekly limits. Baseline accounts refresh weekly. Google does not specify that the first model call anchors either deadline. | Per-pool Gemini and Claude/GPT five-hour and weekly readings. An optional reset accompanies remaining fraction. A Gemini call could debit a different pool from the one a user wants to start. | Unavailable. Requires pool-specific trigger evidence and a history-free, tools-off client. [Google plans and overages](https://antigravity.google/docs/plans) |
| Grok | Grok exposes a shared weekly pool on applicable subscriptions. | The ACP/billing source classifies the actual current period and needs a valid end date. A complete typed period can legitimately omit a zero-valued usage scalar. | No supported first-use target in the current source. [Grok usage limits](https://docs.x.ai/x-subscription/usage-limits) |
| Cursor | Depending on plan, a weekly included pool or legacy monthly billing-cycle allowance. | Headroom’s Cursor provider maps plan/pool billing evidence, including billing-period rows. | No evidenced five-hour start. A real agent invocation could consume billed usage. [Cursor billing](https://cursor.com/help/account-and-billing/billing) |
| GitHub Copilot | Included monthly allowance renews at the beginning of the UTC calendar month. | Copilot status/ledger handles monthly usage and unresolved resets. | An early request cannot advance this renewal. [GitHub monthly reset](https://docs.github.com/en/copilot/reference/copilot-billing/license-changes) |
| OpenCode Go | First allowance use starts the five-hour period. Weekly quota renews Monday at 00:00 UTC and monthly quota follows the paid period. | Go DTO requires rolling, weekly and monthly buckets with finite positive reset timestamps. A limited bucket maps to 100% used. A missing plan has its own unavailable placeholder. | Strong next candidate. Qualify the official client’s Go-account routing, transcript behavior and tool controls before adding an adapter. [OpenCode Go allowance](https://opencode.ai/docs/console/go/) |

The three primary CLIs were available locally. The secondary CLIs (`grok`, `cursor-agent`, `gh`, `opencode`) were absent from the shell search path. The secondary findings use provider documentation and Headroom’s `GrokProvider`, `CursorProvider`, `CopilotProvider`, `OpenCodeProvider` and their source/DTO files.

## Runner evidence and launch contracts

The following are **design specimens**. The CLI documentation establishes flag intent. It cannot establish what happens in an installed, authenticated configuration with arbitrary mandatory settings. Do not qualify a version merely because it accepts these arguments.

### Claude Code 2.1.329

One small user message such as a period can elicit an explanation. Request a single fixed character instead. Use the subscription’s supported low-cost Haiku alias, a tiny task-specific system prompt, no fallback model, no extra turns and no agent tools. A candidate argument vector, shown with shell quoting for readability, is:

```sh
claude -p --model haiku --max-turns 1 --no-session-persistence \
  --safe-mode --restricted --strict-mcp-config --tools "" --disallowedTools "*" \
  --disable-slash-commands --no-chrome --permission-prompts none \
  --prompt-suggestions false --system-prompt-snapshot off \
  --settings '{"disableAllHooks":true,"disableClaudeAiConnectors":true,"disableRemoteControl":true,"remoteControlAtStartup":false}' \
  --system-prompt "Reply with a period." --output-format json -- "."
```

- Installed help explicitly describes the empty built-in tool list, strict MCP configuration, print-only session persistence switch, restricted mode, safe mode, permission prompts and system-prompt snapshot control. The official reference documents `--max-turns`; this installed help listing omits it. Qualify the combination and the exact Haiku alias against the intended version. Unknown flag, unavailable model, conflicting enforced policy or unknown routing means unavailable. Never downgrade to permissive defaults. [Claude CLI reference](https://code.claude.com/docs/en/cli-reference)
- Restricted mode ignores user/project/local settings. An empty `--setting-sources ""` is unnecessary and does not constrain managed policy. Safe mode alone leaves managed plugin hooks in scope. Check effective managed hooks/connectors and the precedence of disable settings before claiming total isolation. `--bare` also skips keychain reads, which can defeat the user’s normal subscription login. Skip paid API and cloud-provider fallbacks. [Claude settings precedence](https://code.claude.com/docs/en/settings) · [Claude CLI modes](https://code.claude.com/docs/en/cli-reference)
- Use the official binary with the already-selected account’s `CLAUDE_CONFIG_DIR`. Omit the variable for the default login, including any inherited value. Mirror the selection rules in `ClaudeUsageCLIProbe.environment`. Construct a minimal child environment allowing only needed locale, resolved executable path, account home and approved controls. Set `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1`. Exclude API keys, model/endpoint overrides, cloud credentials, session tokens and plugin injection. The CLI handles its own authentication. Headroom never reads, links or copies credential content for this operation.
- Use a private, empty, per-attempt directory outside tracked homes and repos. The existing ClaudeProbe workspace deliberately writes a local settings file and has its own trust lifecycle. Give Pre-Warm its own directory. Pass arguments directly, close stdin, parse only bounded success/turn/usage fields, discard output and remove the temporary cwd. Session suppression covers resumable local transcript files. Provider-side records, app telemetry, auth refresh and CLI caches require separate consideration. A short prompt bounds neither system tokens nor provider retries. A turn cap or client-side dollar estimate cannot guarantee an exact charge.
- **Distribution boundary.** Anthropic distinguishes an end user signing in to the unmodified client from third-party products routing model requests on users’ subscription credentials. Existing permission to read a free status panel does not establish permission for recurring automated subscription requests. Confirm applicability to Headroom’s proposed unattended flow before enabling a production Claude adapter. No API-key substitute would start the same subscription clock. [Anthropic authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance)

### Codex CLI 0.171.0 and app-server

The installed top-level and exec help support this *candidate*, with placeholders supplied as single argv elements. The official pricing table currently gives GPT-6 Luna the highest estimated messages per eligible five-hour allowance of the models it lists. Select that tier only if the chosen subscription actually exposes it, it consumes the intended bucket and supports the specified effort. Do not silently choose an expensive default.

```sh
codex --ask-for-approval never exec --ephemeral --ignore-user-config --ignore-rules \
  --sandbox read-only --skip-git-repo-check -C "$scratch" --model gpt-6-luna \
  -c 'model_reasoning_effort="low"' -c 'web_search="disabled"' --json "Reply only with a period."
```

- Directly set `CODEX_HOME` to the selected canonical default, T3 shadow or external home using Headroom’s attachment information and preferred executable. `--ignore-user-config` skips its config.toml while retaining CLI-owned authentication in that home. Strip keys/base URL overrides. Reject non-ChatGPT accounts, missing/moved homes, weak identity and unsupported endpoint policy. Never switch to another home. `--trust` explicitly persists project trust even in ephemeral mode. [Codex CLI reference](https://developers.openai.com/codex/cli/reference/)
- `--ephemeral` addresses local session files. Read-only sandboxing restricts writes by sandboxed commands. Approval policy `never` suppresses dialogs and still permits already-authorized commands. Ignoring user config removes one source of MCP definitions, but global/managed configuration, built-in tools, instructions and hook startup remain unqualified. These switches do not establish zero tools, zero process startup, a one-token output ceiling or zero writes to the CLI home. No qualifying invocation was established for this release.
- The passive conversation in `CodexAppServerProvider.swift` initializes, acknowledges initialization, brackets `account/rateLimits/read` with `account/read` using `refreshToken:false`, and compares identities. These are status reads. A deliberate model request would require a separate client: initialize → initialized → `thread/start` with `ephemeral:true`, specific cwd/model, `sandbox:"read-only"`, `approvalPolicy:"never"` → one `turn/start` with a text input → await matching completion. An empty dynamic tool list describes client-supplied tools only. Never add thread/turn methods to the polling enum. [App-server protocol](https://developers.openai.com/codex/app-server/)
- Headroom decodes `usedPercent` plus optional `windowDurationMins` and `resetsAt`. Its mapper drops windows with nil reset dates. The result can contain only the weekly window or become a stale decode failure if no window survives. Nothing in the RPC contract requires `resetsAt == nil`, a missing primary, or `usedPercent == 0` to mean “never started.” An illustrative RPC payload is not a first-turn trace. [Codex rate-limit fields](https://developers.openai.com/codex/app-server/) · [Plan-specific limits](https://developers.openai.com/codex/pricing/)

### Antigravity 1.5.13, T3-managed binary

The active release manifest selected `d9825ebce6954df6b7841970fd7ef3d37acdfe628993f14c396ec73b20ed06bb`. Its executable reported 1.5.13. Help describes a single noninteractive prompt, a print timeout, sandbox restrictions, execution modes, a model selector, effort and per-session settings. The closest candidate is:

```sh
antigravity -p "Reply only with a period." --disable-slash-commands \
  --mode plan --sandbox --effort low --print-timeout 20s --output-format json
```

This specifies one input prompt. The help does not promise one internal model request. It provides neither an explicit disable-all-tools/MCP switch nor conversation non-persistence. `--settings` makes its settings override transient. It does not make the resulting conversation transient. Plan mode and terminal restrictions permit other activity. Never set `historySize:0` on a borrowed home to emulate ephemerality: the docs describe trimming existing prompt history on exit. Cheapest model is pool- and plan-specific. A cheaper Flash-family model cannot establish that a Claude/GPT-pool clock started. No eligible run profile for the installed version. [Google CLI settings](https://antigravity.google/docs/settings?tab=cli) · [Quota pools and plans](https://antigravity.google/docs/plans)

For T3, `AntigravityLaunchResolver` produces an executable and `.t3Managed(instanceID,probeHome)`. The child’s `HOME` is the probe home. Its `.gemini/antigravity-cli` is a directory symlink to T3’s data directory. Pointing a model conversation there can write into real T3 state. Do not call a link-creating resolver as an isolation test, clone a logged-in home, or select the system login when a T3 home goes missing. A future adapter needs an official ephemeral conversation facility compatible with the exact bound instance.

The passive source has a closed set of operations: version, literal `/usage`, literal `/credits`. It requires a matching command and `provesNoTurn`: zero turns and all five token counters present and zero. A violation can persist an unsupported-client stop keyed to the executable. A future explicit runner must own its process, arguments, parser, timeout and ledger. It must have no writable reference to `AntigravityProbeMemory` or `stoppedClients`. Its one-turn result must never enter `AntigravityCLIUsageSource`’s classifier. A stopped or unavailable passive reader leaves automation without eligible evidence. Resume of Pre-Warm cannot clear the passive stop.

## How to interpret a reading

`UsageStore.mergeResult` rejects discarded captures, stale attachment generations and ineligible setup outcomes. `merge` resolves default-login identity and runs `UsageContinuityPolicy.mergedSnapshot`. Consume **accepted source evidence** in the successful account-bound path, before stale rows are carried forward. Use the settled account projection to suppress duplicate/merged rows. A snapshot may be live while an individual window is unavailable.

| Observation | Representation today | Pre-Warm interpretation |
|---|---|---|
| Fresh account, no reliable session sample | Snapshot pending/stale, missing window, or live zero with unresolved deadline | Unknown. Do not send. A missing label can be an incomplete render. |
| Known previous window passes its deadline | Cached scheduled window becomes unavailable at its old reset. A refresh can still fail or return another account. | Old deadline identifies a candidate epoch. Wait for fresh same-account evidence. |
| Reset followed by idle | A provider might return a trustworthy idle indication, or a zero reading without a reset. Headroom has no general `unstarted` state. | Teach the specific adapter a documented or fixture-verified idle shape. Never manufacture a deadline from an absence, elapsed/invalid label or bare zero. |
| New live window | Session reading has a scheduled future deadline and a percentage which can still round to zero. | Suppress sending if evidence shows an active window. Observe the provider-reported reset after a send. |
| Prior successful send, outcome unknown | Today’s models have no attempt metadata. Continuity can keep old usage visible. | Record “Request sent · window unconfirmed.” Wait for passive evidence. No second request to prove success. |

Claude’s parser recognizes Current session and Current week, then its normalizer classifies reset evidence. `ResetSchedule` can be scheduled or unresolved (absent, elapsed, unparseable, implausible, invalid zone, legacy unknown). Antigravity maps `(1 − remainingFraction) × 100` into distinctly labelled `.other` rows for each pool/window. Retain the typed bucket when deciding eligibility. `UsageWindow.utilization` is percent **used**. UI remaining-percent preferences must never change the scheduler input.

`UsageSnapshot.bankedResets` describes Codex reset credits. Null credit object maps to zero, explicit count maps to its count, omitted/unreported maps to nil. `BankedResetAcknowledgements` tracks announcements. Neither is evidence that a session reset occurred. Pre-Warm never redeems a reset or touches its acknowledgement state.

## Placement and interaction

| Placement | Benefit | Cost |
|---|---|---|
| **Accounts › account ••• › Account Pre-Warm…** | Consent sits beside the selected identity, source and plan. Reuses the row menu; no new row columns. | One extra click. Retain a predictable menu label and restore focus to the invoking row on Back. |
| General tile | Easy to discover. | Mixes a spend permission with app-wide preferences and requires a duplicate account picker. |
| Dedicated App/Sources sidebar item | Room for fleet management. | Seven existing destinations already distinguish app behavior from sources. A separate page duplicates the account hierarchy for a small optional setting. |
| Menu-bar popover action | Fast manual access. | Puts a quota-spending command beside passive refresh. More prominent than this infrequent action warrants. |

Use the first option. Keep Apps/Sources grouping from `SettingsPane`, the real `SettingsSidebar` and `SettingsPaneScaffold`. v7’s source columns, badge field, Add Source sheet and provider toggles retain their own jobs. The mockup starts one level inside Accounts to show the feature immediately. Back exposes the complete v7 list. Its two Claude logins are simulated independently. Codex and Antigravity rows illustrate unavailable reasons. For providers with no relevant window, omit the action.

- **Pre-warm this account** defaults off everywhere, including newly added or rebound logins. Put the quota explanation beside it. Changing the switch records consent without an immediate send. Opting out cancels queued work.
- **Run** offers *After a window resets* and *Manually only*. Default to after-reset when enabled. **Active hours** default to 07:00–22:00 local, with an explicit off switch for all day. The same hours apply to manual runs. Support overnight intervals. Disallow equal endpoints. Use local calendar components for daylight-saving transitions.
- **Pre-Warm Now** runs the same eligibility checks. While sending, disable repeat submission. Keep the last result and timestamp visible after a subsequent pause or opt-out. Examples: “Request sent 08:01 · waiting for usage”, “5h window observed · resets 13:01”, “Paused · outside active hours”, “Paused after 3 failures · Resume”. Resume clears the breaker without sending or resetting the cooldown.
- The default automatic flow waits for an observed reset. After sleeping through a reset or the start of active hours, re-evaluate once on a fresh eligible reading. Do not wake the Mac or replay missed windows. A precise daily wall-clock trigger can follow if requested; the active-hours start already gives a useful morning boundary.

## Implementation handoff

Paths below are relative to the Headroom checkout. These are proposed files, not changes to the shared tree.

| File | Change |
|---|---|
| `Sources/HeadroomCore/Models/PreWarmPolicy.swift` | Add Foundation-only input/output values, reason enums, typed pool/window identity, trigger, active hours, availability and pure eligibility logic. Reuse `AccountIdentity`, `AccountKey`, `ResetSchedule` and existing freshness types. |
| `Sources/HeadroomCore/Settings/PreWarmSettings.swift` | Add versioned per-attachment consent/settings records. Store locally; no sync/export. Preserve unknown versions without overwriting. |
| `Sources/HeadroomCore/Engine/PreWarmLedger.swift` | Add durable attempt claim/outcome store with atomic replacement and an interprocess lock, or a transactional SQLite equivalent. Keep mutable macOS I/O in Engine. |
| `Sources/HeadroomCore/Engine/PreWarmCoordinator.swift` | Add one actor to serialize decisions, coalesce manual/automatic calls, enforce one in-flight request per subscription, and publish sanitized status. Inject clock, calendar, storage, capability registry and runners. |
| `Sources/HeadroomCore/Providers/AccountPreWarmer.swift` | Define separate `Sendable` runner protocol, typed binding, receipt and failure. Reuse executable locator and validated home metadata. Expose only qualified adapters. |
| `Sources/HeadroomCore/Providers/ClaudeAccountPreWarmer.swift` | Implement the version-qualified argv, minimal environment, private cwd, bounded JSON classification, process-group cancellation and cleanup. Inject subprocess launcher. Start with a disabled production capability and a fake runner for tests/demo. |
| `Sources/HeadroomCore/Providers/ClaudeUsageParser.swift`, `ClaudeProvider.swift`, `Models/UsageProvider.swift` | When sanitized evidence establishes a reliable idle signal, carry that typed signal on the fetch result alongside the snapshot. Unrecognized idle shapes return unknown. Keep provider capture separate from actuation. |
| `Sources/HeadroomCore/Engine/UsageStore.swift`, `UsageStoreAccountLifecycle.swift`, `UsageStoreDefaultLogin.swift` | Forward only accepted fresh evidence, invalidate/cancel on provider disable, detach, replacement or identity change. Recheck generation and binding immediately before spawn. |
| `Sources/HeadroomApp/HeadroomApp.swift` | Wire the local coordinator, sleep/wake and existing scheduler lifecycle. Inject a non-spending runner into preview/demo dependencies. |
| `Sources/HeadroomApp/UI/AccountsSettingsTile.swift`, `SettingsPanes.swift`, new `AccountPreWarmDetail.swift` | Add the account menu action and nested detail selection to Accounts. Reuse scaffold/tile/type styles and native controls. Keep the selected sidebar destination Accounts. Subscribe to status for only the displayed account. |

`project.yml` directly includes Core Models, Settings, Notifications, Sync and selected Widgets in iOS targets. Keep those directories Foundation/CryptoKit-only. Process, POSIX file locking, Darwin, NSWorkspace, sandbox and executable resolution belong in macOS-only locations. No iPhone control, phone-triggered spend, new CLI subcommand or widget writes are necessary.

### Consent, claims and accounting

- **preWarmSettings.v1**: local versioned records keyed by provider, `AccountKey`, source attachment and verified account digest. Store enabled, trigger, optional local start/end minutes, consent timestamp. Default missing entries to off. Discard consent on sign-out, reattach/rebind and conflicting identity. A mere display-name change preserves consent. Multiple rows for the same confirmed subscription share a spend lock.
- **preWarmLedger.v1**: local durable record keyed by provider + stable account digest + true pool/window kind. Persist last known live epoch, latest observation time, claimed epoch, unique attempt ID, reserved-at time, status, next-eligible time, last receipt status/time, consecutive failures and breaker state. Do not store prompts, CLI output, tokens, provider email or home paths. Preserve recent claims through toggles and row removal so reattaching cannot double spend. This is a per-Mac guarantee; independent installations need separate consent and cannot coordinate a global lock in this MVP.
- Keep ordinary preferences in UserDefaults. A read-modify-write of two defaults keys offers no durable atomic claim across processes. Make the ledger an independently versioned atomic file/transaction. Verify the save before launch. On unreadable/corrupt/unknown ledger, pause. A crash after durable reservation, even one before actual dispatch, sacrifices that opportunity. This produces at-most-once dispatch by Headroom without pretending a remote provider offers exactly-once execution.
- Runner seam: `AccountPreWarmer.run(_ request: PreWarmRequest) async -> PreWarmReceipt`. A request holds immutable target binding, generation, validated executable/home handle, attempt ID and deadline. A receipt distinguishes `notLaunched`, `acceptedOneTurn`, `possiblySent` and `unsafeClient`. Capability detection is side-effect-free. The passive fetch protocol has no access to this entry point.

### State transitions

1. **Off / unavailable → waiting.** Require explicit fresh consent, same tracked/enabled subscription, supported CLI/model/plan, live identity, applicable five-hour pool and available included quota for all relevant caps. Unknown overage routing or required limits keep the adapter unavailable. Reject stale/out-of-order samples, demo accounts and ambiguous mutable login bindings. If identity cannot be pinned sufficiently for unattended execution, withhold that binding.
2. **Waiting → eligible.** Save the previous live reset deadline as epoch identity. After it passes, consume the next fresh, source-qualified idle observation at or after that deadline. Use the existing polling cadence or request a free, coalesced refresh at the opening of active hours. The wall clock alone never starts a run. New live deadline or positive consumption means a real user already started the window. For an explicitly verified first-ever idle state with no prior epoch, allow a manual claim under a single persisted bootstrap key. Unlock future epochs only from a subsequent observed active window and its expiry. Never bootstrap from an empty row.
3. **Eligible → reserved.** Recheck wake state, local half-open hours, attachment generation, consent revision, time/freshness, cooldown, breaker and prior claims under serialization. A manual click may skip the automatic trigger but none of those guards. Calendar time determines active hours. Use a minimum five hours from dispatch across manual/auto and tolerate clock rollback by failing closed. Enforce both the claim and cooldown even if provider rounding shifts the reported deadline.
4. **Reserved → sending → sent / uncertain / failed.** Use direct spawn, no shell, no PTY, closed stdin, bounded pipes, an example 20-second deadline and process-group reap. A timeout, cancellation after possible dispatch, malformed receipt or crash leaves the claim spent. No queued retry in that window. No fallback CLI, account or model. Opt-out/sleep cancels locally and suppresses further launches; a sent request cannot be recalled.
5. **Sent → observed / unconfirmed.** Let the next normal free refresh with a newly scheduled matching window update status. Acknowledge an observed window, without asserting that Headroom caused it in a race with another client. Skip stale continuity and unrelated weekly/model windows. Display unconfirmed if the result never arrives.
6. **Failure → pause.** Count failures across independent eligible attempts, persist a breaker after three consecutive failures, clear on a confirmed success, and offer explicit Resume. Unsafe-client evidence pauses immediately. Missed hours, active windows and legitimate skips are neutral. Back off preflight failures so every polling tick cannot become another attempt. A restarted application recovers durable reservations as uncertain and reevaluates scheduling from fresh evidence.

**Concrete example.** Monday’s passive capture reported a session ending 06:55. Headroom is asleep at the boundary. At 08:00 it wakes, verifies identity and receives a qualified idle report. At 08:01 it reserves the 06:55 epoch and sends once. A second click, wake notification or settings window cannot repeat it. At 08:03 the CLI reports a reset at 13:01; only now does the activity line report a five-hour window. If the 08:00 report already has a new future deadline, Headroom spends nothing.

### Acceptance tests for Sol

Use fixture homes, fake executables, deterministic clocks and injected sleep/wake. Provider integration fixtures must be synthetic or sanitized. A quota request against a real login is outside this test plan.

| Test location under `Tests/HeadroomCoreTests/` | Must demonstrate |
|---|---|
| `PreWarmPolicyTests.swift` | All providers/accounts start off. Manual and auto enforce consent, distinct pool, included allowance, freshness, identity, active window suppression, zero rounding, unresolved/missing resets, plan with no 5h window, expired cache and weekly-only inputs. Cover inclusive start/exclusive end, overnight hours, DST gap/fold, zone change, clock rollback and stale post-wake reading. |
| `PreWarmCoordinatorTests.swift` | Manual + auto race, repeated passive ticks and two display aliases yield one dispatch. Quit/crash before spawn and after send, corrupt ledger, same-identity reattach, replaced login, in-flight detach/disable, no wake catch-up storm, cooldown, three failures, immediate unsafe pause, explicit Resume and per-account independence. |
| `AccountPreWarmerTests.swift` | Fake executable records argv/env and cwd in a temporary test area. Assert no secret variables, correct bound home, no model fallback, closed stdin, private cwd cleanup, child-group reap, bounded stdout/stderr, redacted statuses and empty subsequent session/workspace inventory in the fixture. Feed zero/multiple turns, timeout, unexpected tool event and successful receipt. Fake binaries verify our launch contract; CLI internals still need version-specific vendor evidence. |
| `AntigravityPreWarmIsolationTests.swift` | Feed a one-turn result to a dedicated fake warm runner. Passive stop-memory spy receives zero writes; valid zero-turn/zero-token `/usage` still parses. Inject one turn or a missing counter into the **passive** reader; its existing unsupported-client stop still trips. Resume/toggle cannot clear that stop. |
| `Tests/HeadroomAppTests/AccountPreWarmDetailTests.swift` | Verify account-scoped menu, back focus, accessible labels, consent copy, pending/uncertain/paused/last-run states, keyboard activation and unavailable reasons. Demo mode can only use a fake runner. |

**Release evidence still needed.** A sanctioned account-bound launch path, exact qualified CLI profiles, and an unambiguous same-account idle capture are the outstanding prerequisites for unattended sends. Fake-process tests establish Headroom’s scheduling and isolation boundaries. They cannot prove the vendor’s real first-use encoding, external history retention, or an exact token bill. If the authenticated CLI cannot provide the required isolation, ship that capability as unavailable.

## Local implementation references

- Raw result acceptance, continuity merging and display projection are adjacent in the Mac store. The freshness distinctions and restore rules have separate owners. [UsageStore.swift](~/Git/headroom/Sources/HeadroomCore/Engine/UsageStore.swift:1151) · [UsageModels.swift](~/Git/headroom/Sources/HeadroomCore/Models/UsageModels.swift:459) · [UsageContinuityCache.swift](~/Git/headroom/Sources/HeadroomCore/Engine/UsageContinuityCache.swift:370) · [BankedResetAcknowledgements.swift](~/Git/headroom/Sources/HeadroomCore/Settings/BankedResetAcknowledgements.swift)
- Read each source at the point where it translates a provider reading into a window. [ClaudeUsageParser.swift](~/Git/headroom/Sources/HeadroomCore/Providers/ClaudeUsageParser.swift) · [CodexLimits.swift](~/Git/headroom/Sources/HeadroomCore/Providers/CodexLimits.swift) · [CodexAppServerProvider.swift](~/Git/headroom/Sources/HeadroomCore/Providers/CodexAppServerProvider.swift:350) · [AntigravityProvider.swift](~/Git/headroom/Sources/HeadroomCore/Providers/AntigravityProvider.swift:82)
- The no-turn proof, persistent passive stop and T3 home mapping are distinct responsibilities. [AntigravityDTOs.swift](~/Git/headroom/Sources/HeadroomCore/Providers/AntigravityDTOs.swift:26) · [AntigravityUsageSource.swift](~/Git/headroom/Sources/HeadroomCore/Providers/AntigravityUsageSource.swift:645) · [AntigravityLaunch.swift](~/Git/headroom/Sources/HeadroomCore/Providers/AntigravityLaunch.swift:31)
- The account menu supplies the entry point and Settings already owns the sidebar selection. [AccountsSettingsTile.swift](~/Git/headroom/Sources/HeadroomApp/UI/AccountsSettingsTile.swift:723) · [SettingsPanes.swift](~/Git/headroom/Sources/HeadroomApp/UI/SettingsPanes.swift:837) · [SettingsView.swift](~/Git/headroom/Sources/HeadroomApp/UI/SettingsView.swift:337) · [v7 Accounts mockup](~/.t3/scratch/2026-11-20-you-are-the-orchestrator-for-6ce70a5e/settings-accounts-mockup-v7.html)

## Prototype verification

The standalone HTML uses the v7 sidebar, account grid, source menus and native-style controls. It opens on Personal › Account Pre-Warm with consent off and a fixed simulated clock of 08:01. Two Claude fixtures exercise separate consent. Adjusting active hours across 08:01 changes eligibility. A simulated successful manual run locks that window. Reload resets the demonstration.

| Preview | Width | contentHeight | Console messages |
|---|---:|---:|---:|
| Desktop dark | 728 px | 592 px | 0 |
| Desktop light | 728 px | 592 px | 0 |
| Mobile dark | 390 px | 548 px | 0 |

Interactive assertions also passed for default off, manual-only selection, out-of-hours blocking, disabling active hours, repeat-run suppression, independent account settings, returning to a configured account and Antigravity’s unavailable state. All model invocations above are design examples. The only provider CLI commands executed during research requested help or version information.
