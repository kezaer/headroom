---
title: Per-Account Polling Beyond the Five-Account Cap - Plan
type: feat
date: 2026-09-19
topic: per-account-polling-schedule
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-brainstorm
execution: code
---

# Per-Account Polling Beyond the Five-Account Cap - Plan

## Goal Capsule

- **Objective:** A user tracking any number of Claude, Codex, or Grok accounts sees every account refreshed at a cadence Headroom actually keeps, can read that cadence in Settings, and never has one broken account or a large account count turn Headroom into a machine-wide load.
- **Means:** Replace the sweep-per-tick refresh with a per-lane due-queue scheduler, redefine the poll interval as a per-account promise that stretches visibly under load, and replace the fixed five-account cap with a tested envelope.
- **Product authority:** This document's Product Contract. The conventions in `AGENTS.md` stay binding, in particular the official-CLI-only rule for Claude usage, the serial CLI lanes, and the probe robustness properties.
- **Active scope:** Scheduling, load guardrails, cap removal, and the Settings cadence display. The side-by-side provider column layout raised in the same feedback is a separate area and not active scope.
- **Open blockers:** None.

---

## Product Contract

### Summary

Accounts probed through a CLI lane (Claude, Grok, and Cursor) are refreshed one at a time from a per-provider queue ordered by how overdue each account is, instead of all together on every timer tick.
The poll interval becomes a promise made to each account; when the lane cannot keep it, Headroom stretches the effective interval and shows both values in Settings.
The five-per-provider cap goes away as a product limit and is replaced by a generous, tested envelope with load guardrails that keep the core app calm at any count.

### Problem Frame

A user wrote in asking to manage more than five accounts per service, saying many people now run more than a dozen at once.
Today the limit is a single constant, and the popover and Settings were designed to it.
Behind that constant sits a real cost: every refresh probes every configured account in a provider's lane back to back, and each Claude probe spawns a full `claude` process with hard deadlines that reach about 80 seconds on the fallback path.
So a larger cap under the current sweep would make one slow account delay every other account on every tick, and would let the total sweep outgrow the poll interval with nothing telling the user.
The interval setting already reads as a promise about freshness; past a handful of accounts it is a promise the sweep cannot keep.

### Key Decisions

- **No fixed product cap; a tested envelope instead.** Users can add accounts up to a bound the code, fixtures, and tests are proven at, presented as "tested up to", not as a limit. (session-settled: user-directed — no fixed cap chosen over 10 per provider, 20 per provider, and keeping 5: the request is for open-ended counts. session-settled: user-approved — tested envelope chosen over a truly unbounded constant: an untestable "unlimited" is how the core gets fragile.) Governs R14, R15.
- **The interval is a per-account promise.** Each account is due its own refresh every interval; the lane's real cadence is derived from that. (session-settled: user-directed — chosen over keeping the primary on interval while extras share the remainder, over widening to parallel probes to hold every account on interval, and over on-demand refresh past a threshold: a single, honest per-account meaning is easier to reason about than three tiers of freshness.) Governs R1, R7, R20.
- **Stretch and say so on overload.** When the lane cannot keep the promise, the effective interval grows and Settings shows it; nothing is blocked and nothing drifts silently. (session-settled: user-directed — chosen over warning before adding an account, over letting ages drift, and over a user-curated polled set: explicit degradation without gating.) Governs R7, R9, R10.
- **Due-queue ordering.** The lane always probes the most overdue account next. (session-settled: user-directed — chosen over fixed round-robin slots and over attention-weighted ordering: self-healing after sleep, Check Now, and slow probes, with weighting available later as a refinement.) Governs R1, R3.
- **Load guardrails.** The lane is busy no more than about half of wall-clock time, and a failing account backs off on its own so it cannot starve the queue. (session-settled: user-approved — chosen over letting the lane run continuously: a laptop should never have a Headroom-spawned CLI process running all day.) Governs R8, R11, R12.
- **Primary first; user actions jump the queue.** The account driving the menu bar and widgets is never displaced by extras, and Check Now, Check Again, Make Main, and setup verification run immediately. Governs R3, R4, R5.
- **Probe transport is unchanged.** The compliant per-account spawn of the official CLI stays the unit of work; the 2.1.278 CLI exposes no cheaper usage surface. Per-account spawn trimming is allowed in planning but is not a requirement. Governs R6.

### Requirements

**Scheduling**

- R1. Every account in a CLI lane carries its own due time, the last capture attempt plus the effective interval, and the lane always probes the most overdue account next.
- R2. A lane runs one probe at a time; lanes for different providers and the Codex HTTP fetch continue to overlap.
- R3. When the provider's primary account and any extra are both overdue, the primary is probed first.
- R4. Account-level Check Now, provider-level Check Again, Make Main, and setup verification probe that account at the front of the queue without waiting for other due accounts, and reset its due time on completion.
- R5. Manual actions in R4 keep their current semantics for locator epochs, capability recovery, and setup session completion.
- R6. Each probe continues to run the official CLI once per account with the account's isolated config home; no shared credential, endpoint, or token path is introduced.

**Promise and stretching**

- R7. The effective interval for a lane is the chosen interval or, when larger, the shortest interval at which every account in the lane can be probed at its recently observed probe duration within the duty-cycle ceiling in R8.
- R8. A lane is busy for no more than about half of wall-clock time over a recent window; the effective interval stretches rather than the lane exceeding that ceiling.
- R9. Settings shows, per provider, the chosen interval and the effective interval whenever they differ, with the account count as the stated reason.
- R10. When the effective interval equals the chosen interval, no additional cadence UI appears.

**Failure isolation**

- R11. An account whose probe fails is retried with growing spacing up to a bound, and returns to the effective interval on its next successful capture.
- R12. A failing account delays a healthy account by at most one probe's worth of time.
- R13. Never-signed-in extra accounts keep an exemption equivalent to today's every-fourth-cycle timer behavior, expressed in due-time terms.

**Cap and envelope**

- R14. The fixed five-per-provider cap is removed as a product limit; the add-account affordance stays enabled until the tested envelope is reached.
- R15. The tested envelope is one constant, initially 20 per provider with Cursor staying at 1, that unit tests, demo scenarios, and Settings interaction tests exercise; Settings says "tested up to N" only when a provider reaches it.
- R16. Every existing per-account behavior works unchanged at the envelope: Make Main, stop-tracking the built-in account, the same-login badge, and removing an extra account deleting its config home.

**Surfaces**

- R17. The Settings Accounts list remains usable at the envelope inside the fixed-frame Settings window.
- R18. The popover card list continues to scroll past its existing height cap at the envelope; the header freshness label keeps its current meaning.
- R19. Widget and phone snapshots update within one probe of the primary account's capture rather than waiting for every account in the lane.

**Timing bounds**

- R20. The two-minute interval floor is unchanged and applies to the effective interval.
- R21. Setup verification's fixed 240 second stop-loss is sufficient because verification jumps the queue under R4; planning confirms rather than re-deriving it from account count.

### Key Flows

- F1. Timer refresh with twelve Claude accounts
  - **Trigger:** The polling timer fires with a 5 minute interval and twelve Claude accounts configured.
  - **Steps:** The Claude lane takes the most overdue account, probes it, records its capture time, then takes the next. Codex fetches concurrently. Each account is probed roughly every 5 minutes, about 25 seconds apart on the print path.
  - **Outcome:** Every account's age stays within the chosen interval plus one probe. Settings shows only the chosen interval.
  - **Covers:** R1, R2, R7, R10.
- F2. Overload on a short interval
  - **Trigger:** The user sets a 2 minute interval with forty Claude accounts averaging 3 seconds per probe.
  - **Steps:** Probing every account takes 120 seconds, which is the whole interval. The duty-cycle ceiling stretches the effective interval to about 4 minutes. Settings shows "2 min chosen, about 4 min effective, 40 Claude accounts".
  - **Outcome:** The lane stays idle about half the time; nothing is blocked; the user can see why.
  - **Covers:** R7, R8, R9, R20.
- F3. Check Now on an extra account while the lane is busy
  - **Trigger:** The user presses Check Now on account 7 while account 3's probe is running.
  - **Steps:** Account 7 becomes the next probe after account 3 finishes, ahead of any other overdue account. Its due time resets on completion.
  - **Outcome:** The user's requested account refreshes within one probe.
  - **Covers:** R4, R5, R12.
- F4. One account hangs
  - **Trigger:** Account 5's print probe times out and its fallback also fails, costing about 80 seconds.
  - **Steps:** Account 5 is marked failed and its next due time moves out with growing spacing. The queue continues with the next overdue account.
  - **Outcome:** Other accounts lose at most one probe's worth of time this pass; account 5 returns to normal cadence on its next success.
  - **Covers:** R11, R12.
- F5. Adding a sixth account
  - **Trigger:** The user adds a Claude account with five already configured.
  - **Steps:** The add flow proceeds as today through the Terminal handoff. Once verified, the account enters the queue as overdue and is probed at the next opportunity behind the primary.
  - **Outcome:** Six accounts show in the popover; the Settings add affordance remains enabled.
  - **Covers:** R3, R14, R16.

### Acceptance Examples

- AE1. **Covers R1, R3.** Given four Claude accounts where the primary and account 3 are both overdue, when the lane picks its next probe, then it probes the primary first and account 3 next.
- AE2. **Covers R7, R8, R9.** Given a 2 minute chosen interval, 40 Claude accounts, and a recent probe duration of 3 seconds, when the effective interval is computed, then it is about 4 minutes and Settings shows both values with the account count.
- AE3. **Covers R10.** Given a 5 minute chosen interval and three Claude accounts, when the effective interval is computed, then it equals 5 minutes and Settings shows no effective-interval row.
- AE4. **Covers R4, R12.** Given a busy lane with six overdue accounts, when the user presses Check Now on one of them, then it is the next account probed after the in-flight probe finishes.
- AE5. **Covers R11.** Given an account whose last three probes failed, when its next due time is computed, then it is later than the effective interval and it returns to the effective interval after one successful capture.
- AE6. **Covers R14, R15.** Given 20 Claude accounts configured, when the user opens Settings, then the add-account affordance is disabled and the provider header reads "tested up to 20".
- AE7. **Covers R19.** Given the primary Claude account's probe completes while five extras are still queued, when the widget snapshot is next read, then it already reflects the primary's new capture.

### Success Criteria

- With 20 Claude accounts on the print path and a 5 minute interval, no account's age exceeds the interval plus one probe during a one hour run.
- No Headroom-spawned CLI process is running for more than about half of any ten minute window at any account count.
- The scheduler's ordering, stretching, and backoff decisions are covered by unit tests with an injected clock and no CLI, network, or Keychain access.

### Scope Boundaries

- The side-by-side provider column layout for the popover is separate work.
- Attention-weighted ordering (probing accounts near a limit or reset sooner) is a later refinement on top of the due-queue.
- Cursor stays single-account; no config-home isolation exists for it.
- Running more than one probe at a time within a lane is out of scope; the duty-cycle ceiling makes it unnecessary and the process-storm concern from the July stabilization work stands.
- Changing the per-probe sequence (auth status, version check, print, PTY fallback) is not required; planning may trim it where it is safe.

<!-- ce-section: work-relationships -->
### How This Work Fits Together

This plan covers scheduling, guardrails, and the cap. The breakdown below is the current understanding, not a committed roadmap.

- Popover column layout
  - Can proceed independently of this plan.
  - Shares the many-accounts motivation and will benefit from R17 and R18 holding at the envelope.
- Attention-weighted ordering
  - Depends on this plan's due-queue.
  - Still to decide whether users want it at all.

### Dependencies / Assumptions

- Probe durations were measured on a Linux container with Claude Code 2.1.278 as a native binary and a logged-out config: about 0.4 seconds for the auth check, 1.9 seconds for print mode without the network fetch. Planning validates macOS timings with the existing `--probe-claude` diagnostic before fixing the duty-cycle window.
- Claude Code 2.1.278 exposes no usage subcommand and its JSON output mode wraps the same report text, so one CLI spawn per account per probe remains the floor.
- Other development is landing on the default branch concurrently; implementation merges the default branch before building and before pushing.

### Outstanding Questions

**Resolve Before Planning**

- None.

**Deferred to Planning**

- Whether a print-mode timeout on a print-capable CLI should skip the PTY fallback for that probe, bounding the per-account worst case to about 25 seconds.
- Whether to cache the CLI version band per executable per refresh generation and to run the auth check only after an unparseable print result.
- The exact backoff curve and bound for R11.
- The measurement window for the duty-cycle ceiling in R8.
- Whether the effective-interval display in R9 lives on the Accounts pane, the General pane, or both.
- How the due-queue interacts with the existing reset-deadline phasing of the timer, which today shifts a single tick toward the nearest reset.

### Sources / Research

- `Sources/HeadroomCore/Engine/UsageStore.swift` — `refreshSubscriptions` partitions providers into keyed serial lanes and probes each lane sequentially per refresh; `refreshAccountNow` and `drainPendingAccountRefreshes` are the existing single-account path; `shouldSkipOnTimer` holds the never-signed-in exemption.
- `Sources/HeadroomCore/Engine/PollingEngine.swift` — single sleep-then-tick loop with reset-deadline phasing; no per-account scheduling.
- `Sources/HeadroomCore/Settings/AccountRegistry.swift` — `maxPerProvider = 5`, consumed by `accounts(for:)`, `canAddAccount`, `addAccount`, and the `accountCapacity` default on `UsageProvider`.
- `Sources/HeadroomCore/Providers/ClaudeUsageCLIProbe.swift` — per-account sequence of auth status (5s), version (5s), print (20s), PTY fallback (30s boot, 26s panel); version result is not cached across accounts.
- `Sources/HeadroomCore/Setup/SetupSessionCoordinator.swift` — `verificationStopLoss` is a fixed 240 seconds, not derived from account count.
- `Sources/HeadroomApp/UI/AccountsSettingsTile.swift` — add-account gating on `accountCapacity` and `canAddAccount`; no scroll or height handling for large lists.
- `Sources/HeadroomApp/UI/PopoverView.swift` — 640pt card list cap; header "Updated" label aggregates the oldest live capture.
- `BUGS.md` — "No backoff on repeated failures" listed as deferred.
- `docs/plans/2026-07-20-001-fix-provider-setup-multi-account-release-stabilization-plan.md` — R8: Claude probes serialized to avoid a process storm.
- `docs/solutions/claude-print-mode-usage-probe.md` — print-first capture, version floor 2.1.217, why the PTY path stays.

| Measurement (Linux, Claude Code 2.1.278 native, logged out) | Time |
|---|---|
| `claude --version` | 0.01s |
| `claude auth status --json` | 0.37s |
| `claude -p "/usage" --no-session-persistence` with stdin closed | 1.9s |
| Same command with stdin inherited | 4.8s (3s stdin wait) |
| Five `auth status` in parallel | 0.9s total |
