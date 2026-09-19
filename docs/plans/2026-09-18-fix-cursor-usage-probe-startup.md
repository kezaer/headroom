---
title: Cursor Usage Probe Startup Recovery - Plan
type: fix
date: 2026-09-18
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# Cursor Usage Probe Startup Recovery - Plan

## Goal Capsule

Restore Cursor usage capture for a signed-in user whose official Cursor Agent opens a workspace-trust screen or uses the newer prompt placeholder. Keep the official CLI `/usage` boundary and fail closed on unfamiliar screens. Ship a reviewed PR with deterministic terminal tests and available live diagnostic evidence. Do not publish a new DMG in this work.

## Product Contract

Headroom 1.4.1 reports “Cursor Agent opened an unrecognized screen” after a valid sign-in. The first-run Headroom workspace can display Cursor's trust menu, and newer Cursor versions show “Plan, search, build anything” at the ready prompt instead of “Ask (shift+tab to cycle).” PR #124 changed executable discovery and panel capture, not these gates.

### Requirements

**Startup and recovery**

- R1. A recognized Cursor workspace-trust screen yields a distinct, actionable state that lets the user approve the Headroom-owned workspace through the official Cursor Agent, then retry usage capture.
- R2. Headroom never accepts workspace trust or MCP server approval on the user's behalf and never sends `/usage` into a trust, approval, login, or unknown screen.
- R3. Both verified ready-prompt generations permit the existing `/usage` autocomplete path; the Cursor banner alone never permits typing.

**Usage integrity**

- R4. A positively selected `/usage` row remains required before Enter; only a valid usage panel becomes a live reading. Existing auth, timeout, process cleanup, and parser behavior remain intact.
- R5. The failure and recovery state remains typed and redacted across provider snapshots, cards, settings, and setup actions.

### Acceptance Examples

- AE1. Covers R1, R2, R5: Given a signed-in Cursor CLI that opens “Workspace Trust Required” for the Headroom workspace, Headroom identifies trust as the needed action and offers an official CLI handoff. It sends no slash command before user approval.
- AE2. Covers R3, R4: Given a trusted workspace with the “Plan, search, build anything” input and a selected `/usage` completion, Headroom opens the panel and parses the included percentage.
- AE3. Covers R2, R3: A Cursor banner on an MCP approval or unfamiliar screen does not authorize typing. A rejected or abandoned trust handoff keeps the state actionable on the next check.

### Scope Boundaries

Cursor remains a single-account provider. No private Cursor endpoint or credential reuse is introduced. Compatibility for the older MCP approval screen means safe classification and user guidance, never silent approval.

## Planning Contract

### Key Technical Decisions

- KTD1. Keep the official `cursor-agent` PTY and `/usage` command path, chosen over private dashboard requests or credential reuse because this is Headroom's established compliant provider boundary (governs R2, R4).
- KTD2. Classify boot screens before PTY input: trust takes priority, then a positive ready prompt that includes the version-specific input placeholder, while approval and unknown screens fail closed (governs R1-R3).
- KTD3. Route trust recovery through a Terminal handoff to Cursor Agent in the exact Headroom workspace, following Claude's user-approved workspace pattern. Avoid automated trust keystrokes; the user makes Cursor's security decision (governs R1, R2, R5).
- KTD4. Exercise the real PTY state transitions with a deterministic fake CLI in addition to pure classifier tests. Parser fixtures alone cannot detect a pre-prompt gate failure (governs R1-R4).

The existing `CursorUsageCLIProbe` owns boot and autocomplete gates; `CursorPanelResult` and `ProviderSetupOutcome` own typed failures; `SetupSessions` dispatches recovery actions. Follow `ClaudeUsageCLIProbe` and `ClaudeSetupViews` for trust semantics without coupling Cursor to Claude's UI.

## Implementation Units

### U1. Classify Cursor boot states and preserve input gates

- **Requirements:** R1-R4; AE1-AE3; KTD1, KTD2, KTD4.
- **Files:** `Sources/HeadroomCore/Providers/CursorUsageCLIProbe.swift`, `Sources/HeadroomCore/Providers/CursorProvider.swift`, `Tests/HeadroomCoreTests/CursorProviderTests.swift`, and a test-owned fixture or fake CLI where needed.
- **Approach:** Recognize the exact trust screen and both known ready placeholders; keep unknown/approval states distinct from ready. Add a typed trust result through the provider. Do not weaken the selected-command gate.
- **Test scenarios:** First-run trust, older and newer ready prompts, banner-only and MCP approval negatives, selected `/usage` positive and wrong-command negative, full PTY transition into a parseable usage panel, bounded timeout/cleanup.
- **Verification:** A new test must fail on the baseline startup behavior and pass with the fix; `swift test --filter Cursor` passes.

### U2. Give trust a useful recovery path

- **Requirements:** R1, R2, R5; AE1, AE3; KTD3.
- **Files:** `Sources/HeadroomCore/Models/ProviderSetup.swift`, `Sources/HeadroomCore/Providers/CursorConnection.swift`, `Sources/HeadroomApp/UI/SetupSessions.swift`, affected card/settings action dispatch, and corresponding tests.
- **Approach:** Present a Cursor workspace action distinct from sign-in. Launch the official CLI against the Headroom-owned workspace in Terminal so the user can choose Cursor's trust option, then check usage again. Keep paths and provider output out of status text.
- **Test scenarios:** Trust result maps to the correct redacted status/action, handoff uses the exact quoted workspace path and CLI executable, script syntax is valid, dismissal/retry remains safe, MCP approval is never accepted automatically.
- **Verification:** Targeted Core and app tests pass; compile the app target.

## Follow-up Acceptance: Grok and Cursor First Run

The product goal also includes completing authentication smoothly after the first CLI
handoff, including provider-specific account isolation and optional approval screens.

- R6. Grok built-in and extra-account sign-in use the intended `GROK_HOME`; the
  clipboard fallback uses Headroom's resolved executable path.
- R7. Cursor browser sign-in ignores Terminal API-key overrides, matching the usage
  probe, and its fallback command uses the resolved executable path.
- R8. Workspace trust and configured MCP-server approval are distinct, actionable
  user decisions. Neither is approved by Headroom. After the CLI closes, a live
  provider result completes setup even when quitting the interactive CLI returns a
  nonzero shell status.

Verify these with generated-script execution against fake CLIs, setup-coordinator
state transitions, fake PTY approval screens, and offscreen live Grok/Cursor probes
under a sparse `PATH`. A real user approval remains a user action, not an automated
acceptance step.

## Verification Contract

1. Run the new regression tests against the pre-fix behavior where practical and record the failing assertion.
2. Run `swift test --filter Cursor`, then `swift test` and `swift build` after implementation.
3. Run the Xcode app test command from `AGENTS.md` if Xcode 27 supports this project's targets; report a toolchain-specific failure separately from a code failure.
4. Run `swift run Headroom --probe-cursor` offscreen only if the installed CLI is available; report its typed outcome without exposing account details. Do not drive or capture the user's live desktop.
5. Review the diff for unsafe PTY keystrokes, process cleanup, accidental prompts, and leakage of CLI output or account information.

## Amendment after live verification (2026-09-19)

R2 and KTD3 are narrowed, not reversed: the probe passes `--trust` for Headroom's own
empty, owner-only `CursorProbe` directory, because Cursor Agent `2026.09.15-d2fe57e`
honours the flag interactively and persists it, which removes the handoff for most
users. Headroom still never types into a trust or MCP screen and never uses
`--approve-mcps`; the trust classifier and handoff remain as the fallback for CLI
builds that ignore the flag. Evidence and the corrected `--trust` history live in
`docs/solutions/cursor-agent-usage-feasibility.md`.

## Definition of Done

- U1 and U2 satisfy their acceptance examples with meaningful regression tests.
- The existing Cursor tests and full Swift suite pass, and the app compiles under the available toolchain, or any environment-specific gate is reported precisely.
- The trust decision remains with the user, and no unknown screen triggers a slash command or approval input.
- Experimental or unused code is removed; the branch contains only this fix and its plan/documentation; review findings are resolved or durably tracked before PR handoff.
