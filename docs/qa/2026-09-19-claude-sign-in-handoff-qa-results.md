# Claude sign-in handoff live QA results

Status: **live UI pass stopped at owner direction; follow-up fixes implemented** — live UI testing started 2026-09-20. Kyle deprioritized the five-minute timer after the environment made that row disproportionately expensive to reproduce. The two actionable regressions found during the pass are fixed in the working tree and covered by automated regression tests. Remaining unrun live rows are listed explicitly below.

## Build tested

- Version: `1.4.1`
- Build: `33`
- Git HEAD: `db678d8a`
- Implementation under test: `c764767e`
- Final release build: `./Scripts/build-app.sh` passed (`** BUILD SUCCEEDED **`), assembled and signed `Headroom.app`, and passed on-disk and designated-requirement validation.
- Final Swift suite: 944 tests in 65 suites passed.
- Final Xcode app suite: 188 tests in 26 suites passed (`** TEST SUCCEEDED **`).

Kyle authorized screen control, the Claude browser authorization for the already signed-in Personal browser session, the app-group prompt, machine-wide Personal logout/reset and restoration, and local rebuilding. Tests 8–10 were excluded because no throwaway extra account was authorized. Work account `d6587b6f-4308-46e5-886c-caf44917e587` was explicitly out of scope for mutation.

## Matrix

| # | Result | What happened | Screenshot evidence |
|---|---|---|---|
| 1 | Pass | Fresh build launched. After the app-group prompt was manually allowed, the popover showed live Personal and Work Claude usage and both Accounts rows showed Connected. | Captured inline through computer use; local persistence was unavailable (see findings). |
| 2 | Partial pass | The official CLI/browser path opened with no typing. The Settings row showed `Waiting for sign-in…`; the browser visibly identified the correct Personal account, **Authorize** completed successfully, and the row returned to Connected without another Headroom click. The opening/confirming transitions and Terminal result line were too brief/inaccessible to record. | Inline only. |
| 3 | Blocked | No Sign In surface was offered while Personal was already connected. The extra-account manual-command path is out of scope. | — |
| 4 | Pass with evidence limitation | Ctrl-C produced exact text `Terminal closed before sign-in finished.` with **Sign In**. A targeted SIGHUP (the signal sent when a terminal session closes) produced the same result; Ghostty itself cannot be controlled by the computer-use API. On the abandoned-browser attempt, `claude auth login` exited by itself in under a few seconds because the existing browser session auto-authorized, and the row returned to Connected. The Terminal last line was inaccessible to automation and its completion marker had already been cleared. | Inline Settings captures only. |
| 5 | Fail on first natural attempt; retry stopped | Reset entered exact `Waiting for sign-in…` state with only **Stop Waiting** and no **Check Now**. The staged Terminal command did not initially execute: no new TTY/process owned it, Personal remained logged in, and the marker stayed pending. At about 5m20s the delayed handoff completed and the row jumped to Connected instead of showing `Sign-in wasn’t confirmed.`; the generated `.command` file remained behind. A controlled retry was stopped at Kyle's direction because the timer was not important enough to justify more manual setup. | Inline Settings captures only. |
| 6 | Not run | Stopped with the timeout retry at owner direction. | — |
| 7 | Not run | Stopped with the timeout retry at owner direction. | — |
| 8 | Blocked | No throwaway extra Claude account was authorized. | — |
| 9 | Blocked | Depends on excluded throwaway extra account. | — |
| 10 | Blocked | Depends on excluded throwaway extra account. | — |
| 11 | Partial | After a clean relaunch, reset immediately showed `Waiting for sign-in…` in Settings. Interrupting the reset produced `Terminal closed before sign-in finished.` and left Personal signed out. Popover waiting-state and final successful reset acceptance remain. | Inline Settings capture only. |
| 12 | Not run | Stopped at owner direction. | — |
| 13 | Partial | Settings waiting state showed no **Check Now**; only **Stop Waiting** was present. Popover and Codex halves remain. | Inline Settings capture only. |
| 14 | Pass | Starting count `sign-out-events=0`. External `/Users/kylezantos/.local/bin/claude auth logout` produced exactly one event for `claude/primary` with timestamp `2026-09-20T16:02:35Z`; no identity/provider payload was printed in the diagnostic section. After deliberate resets and final Personal restoration, the count remained `1`, confirming reset sign-outs were not recorded. | CLI output recorded here; no screenshot. |
| 15 | Partial | Initial connected popover and Accounts view looked unclipped in Dark appearance. Phase-by-phase light/dark acceptance was not completed before the pass stopped. | Inline only. |

## Recorded values

- Test 4 Ctrl-C result: `Terminal closed before sign-in finished.`
- Test 4 close-session proxy: targeted SIGHUP to the exact handoff process group; same result.
- Test 4 abandoned browser: CLI exited by itself in under a few seconds and Personal connected because the saved browser session auto-authorized.
- Test 5 first attempt began at approximately `2026-09-20 11:08:46 PDT`; no timeout state appeared. The row returned to Connected at approximately `11:14:08 PDT` (about 5m22s).
- Test 7 clock readings: pending.
- Test 8 ports: blocked by scope.

## Findings

### New

1. **Resolved in the working tree — reset was a no-op immediately after a successful sign-in.** Selecting **Sign Out & Set Up Again** dismissed the confirmation but opened no Terminal and left Personal connected. Repeating it behaved the same. A clean Headroom relaunch made the same reset action work immediately. Root cause: `.connected` doubles as a four-second visual payoff state, but `SetupSessionCoordinator.start` rejected every start from that state. The coordinator now permits only a reset to supersede the connected payoff; ordinary duplicate setup remains ignored. `resetCanStartWhileConnectedPayoffIsStillVisible` reproduces and pins the transition.
2. **Resolved in the working tree — a handoff could remain staged without executing.** On the first five-minute timeout attempt the row showed `Waiting for sign-in…`, but the staged `.command` and pending marker had no new terminal process/TTY and Personal stayed logged in. Around the deadline it completed and the row jumped directly to Connected, so the required timeout UI was never shown. Root cause: the default `.command` handler was Ghostty, and LaunchServices acceptance did not prove the script ran. New handoffs now explicitly open the script with macOS Terminal (`com.apple.Terminal`) through the async AppKit API. Failure to resolve or open Terminal still uses the existing clipboard fallback and marker cleanup. `preparedHandoffTargetsSystemTerminalAndPersistsItsHost` pins the production orchestration, execution host, target script, and durable record.
3. **Local screenshot artifacts could not be persisted.** Computer use rendered valid inline screenshots, but `/usr/sbin/screencapture` failed for both window-ID and rectangle captures with `could not create image`. The requested screenshot directory exists but currently has no files. A dedicated QA machine needs Screen Recording permission or an automation-native artifact export path.

### Already in `BUGS.md`

- The app-group permission prompt blocked Headroom's main thread after the rebuilt app launched; the app resumed when Kyle clicked **Allow**.
- Re-signing the local build caused the prompt to return.

## Machine state after the live pass

- Personal Claude: signed in and Connected in Headroom.
- Work Claude: untouched throughout; final `loggedIn` value was `true`.
- Appearance: Dark (starting value).
- Headroom: fresh build running (PID recorded during cleanup as `53820`).
- Browser: Claude authorization tabs opened by the official CLI remain open; they were not closed because the pass was stopped mid-cleanup.
- Processes: no `claude auth login`, `claude auth logout`, or QA sleep process remained. Only the expected Headroom app process was left running.
- Setup artifacts: one generated `.command` file remained under `~/Library/Application Support/Headroom/Setup/`; this is the orphan described in Finding 2.
- Extra Claude account: none created.
- Repository changes: the two code fixes, their regression tests, this QA record, and a durable solution note are present in the working tree. No commit, push, or PR update has been performed.

## Follow-up verification

- The connected-payoff reset regression failed before the coordinator fix and passes afterward.
- The explicit-Terminal regression failed to compile before the opener seam existed and passes afterward.
- Focused Headroom app tests: 31 tests in 2 suites passed after the final opener and payoff-claim changes.
- Focused coordinator suite: 69 tests passed after the final state-machine changes.
- Full Swift suite: 944 tests in 65 suites passed.
- Full Xcode app suite: 188 tests in 26 suites passed (`** TEST SUCCEEDED **`).
- Release build: `./Scripts/build-app.sh` passed, including bundle assembly, signing, embedded-binary validation, and final code-signature validation.
- The fixed build has not repeated the live auth mutation sequence. That acceptance belongs on the dedicated QA host so it can run without interrupting the primary machine or risking the out-of-scope Work account.
