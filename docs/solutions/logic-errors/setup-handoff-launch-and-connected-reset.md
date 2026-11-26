---
title: Treat setup payoff state and Terminal launch as separate contracts
date: 2026-09-20
category: logic-errors
module: PacemarkApp/SetupSessions
problem_type: logic_error
component: state_machine
symptoms:
  - Reset silently did nothing for several seconds after a successful sign-in
  - A staged command could be accepted by LaunchServices without executing
  - Pacemark showed Waiting for sign-in while no Terminal process owned the handoff
root_cause: state_and_launch_contracts
resolution_type: code_fix
severity: high
tags: [claude, setup, reset, terminal, launchservices, state-machine]
---

# Treat setup payoff state and Terminal launch as separate contracts

## Problem

Live Claude sign-in QA exposed two failures in the official-CLI handoff boundary:

- A successful sign-in leaves the coordinator in `.connected` briefly so the UI can show its
  payoff. Settings still presents **Sign Out & Set Up Again** during that interval, but the
  coordinator rejected every new start from `.connected`, making reset a silent no-op until a
  view settled the state or the app relaunched.
- Pacemark opened staged `.command` files through their default LaunchServices handler. The
  configured handler could accept the request without executing the script, leaving Pacemark's
  durable marker pending while no process performed the sign-in or reset.

Both bugs came from treating a nearby signal as if it proved the behavior Pacemark actually
needed. A visual payoff state is not a lock on future user intent, and a successful file-open
request is not proof that a shell script started.

## Solution

### Allow reset to supersede only the connected payoff

`SetupSessionCoordinator.start` now permits `.reset` while the account is `.connected`. Other
starts from `.connected` remain ignored, so duplicate setup actions still cannot create a second
handoff. The Connected payoff carries the coordinator generation that produced it. Starting a
reset advances that generation and releases the UI claim, so the old four-second callback cannot
settle the reset or release a later connection's claim. A reset parked behind Codex's exclusive
login slot also ignores routine live polls until the user continues or cancels it.

This is intentionally narrow: `.connected` remains the success presentation state, but it no
longer blocks a distinct destructive action that Settings continues to offer.

### Target the system Terminal explicitly

New handoffs resolve `com.apple.Terminal` and pass both the staged script URL and the Terminal
application URL to AppKit's asynchronous open API. Pacemark records that same bundle identifier
for **Show Terminal** and durable restoration.

If Terminal cannot be resolved or rejects the open, Pacemark clears the prepared marker, removes
the staged script, copies the already validated manual command, and returns the existing typed
failure. The official CLI still owns authentication; Pacemark does not read credentials, handle
OAuth callbacks, or replace the Terminal workflow.

The prepared script moves into active ownership before the asynchronous AppKit call. **Stop
Waiting** can therefore remove it while Terminal is still launching, and a late opener result
cannot restore a cancelled handoff or overwrite a successor.

## Why this works

- The state machine distinguishes a transient UI payoff from an active external-process lock.
- The reset path keeps its existing generation, marker, isolation, and settlement protections.
- The execution host is deterministic instead of depending on mutable file-association state.
- The opener is awaited, so AppKit errors reach Pacemark's established cleanup and clipboard
  fallback rather than being mistaken for a running handoff.
- The durable record and **Show Terminal** target the application that Pacemark actually chose.

## Tests

- `resetCanStartWhileConnectedPayoffIsStillVisible` proves that reset advances to waiting,
  crosses the reset boundary once, rejects the stale payoff token, and stages and opens a second
  handoff. The blocked-provider test also proves a live poll cannot erase a parked reset.
- `preparedHandoffTargetsSystemTerminalAndPersistsItsHost` proves that the production
  orchestration resolves `com.apple.Terminal`, opens the exact staged script, and persists the
  host for restoration and **Show Terminal**.
- The Terminal-unavailable and open-rejected tests prove typed fallback plus marker/script
  cleanup. The suspended-open cancellation test proves a late AppKit result cannot restore the
  abandoned handoff.
- The existing coordinator and app-boundary suites continue to cover cancellation, marker
  cleanup, clipboard fallback, and restored handoffs.

## Prevention

- Do not use presentation-only states to reject a different user intent unless every surface
  hides or disables that intent for the same lifetime.
- Do not treat LaunchServices acceptance as proof that an executable artifact ran.
- Persist the execution host chosen at launch when later recovery UI needs to reactivate it.
- Transfer resource ownership before an `await`, and generation-bind delayed UI settlement to
  the state it is allowed to end.
- Keep auth acceptance tests on a dedicated machine or VM, where default-handler changes,
  Terminal lifecycle, and installed-app permissions can be tested without disrupting a primary
  workstation.
