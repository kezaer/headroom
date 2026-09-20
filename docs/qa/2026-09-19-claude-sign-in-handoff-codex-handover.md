---
artifact_contract: "ce-handoff/v1"
created_at: "2026-09-20T00:38:46Z"
title: "Claude sign-in handoff: real-world QA handover for Codex"
summary: "Live acceptance test pass for Headroom's reworked Claude sign-in flow, to be run by a Codex agent with computer use while Kyle is away."
keywords: ["headroom", "claude sign-in", "terminal handoff", "qa", "computer use", "acceptance"]
cwd: "/Users/kylezantos/App Development/Manual Library/headroom/.claude/worktrees/local-headroom-build-e1ae91"
resume_focus: "Run the live QA matrix below against a fresh build and write the results file. Test only: no code changes, no commits, no pushes."
repository: "github.com/kylezantos/headroom"
repo_root_sha: "5396ffcba68a8ff5c51e91556645b4b3e04cce12"
branch: "claude/local-headroom-build-e1ae91"
head: "c764767e"
worktree_path: "/Users/kylezantos/App Development/Manual Library/headroom/.claude/worktrees/local-headroom-build-e1ae91"
---

# Claude sign-in handoff: real-world QA handover for Codex

You are picking this up cold. Kyle (the owner, a product designer) asked for this document so that a Codex agent with computer use can do the live testing that an agent without desktop control could not. Everything under "What Kyle asked you to do" is his request. Everything else is status you can verify.

## Kyle fills this in before handing over

These are decisions only Kyle can make. Do not start until each line is ticked or struck. If a line is struck, mark every test that depends on it **blocked** and move on.

- [ ] You may take over the screen (menu bar, Terminal, Chrome, System Settings appearance toggle) for the duration of this pass.
- [ ] You may click **Authorize** on the claude.ai consent page that `claude auth login` opens, **only** when the browser is already signed in to the right account. You never type a password, a 2FA code, an API key or a token. If the page asks for any of those, stop that test and mark it blocked.
- [ ] You may answer the macOS prompt "Headroom would like to access data from other apps" with **Allow**. It appears after every rebuild because the rebuild re-signs the app.
- [ ] You may sign the machine-wide default `claude` CLI login in to Kyle's **Personal** account (test 2 does this; it is what Kyle was trying to do when this work started).
- [ ] You may add one throwaway extra Claude account in Headroom for tests 8 to 10, and remove it again at the end. Which login should it use? ____________________ (if blank, run tests 8 to 10 only as far as the browser consent page, do not authorize, and say so).
- [ ] You may sign the default CLI login out of Personal and back in, machine-wide: with `/Users/kylezantos/.local/bin/claude auth logout` in a plain Terminal (needed before tests 4 to 8 now that Personal starts signed in, and again in test 14), and with "Sign Out & Set Up Again" (test 11).

## Hard rules

These come from the repo owner and are not negotiable.

- You are forbidden from `git stash`, `git reset`, `git checkout -- <path>`, or `git clean`. If something wants a clean tree, stop and report instead.
- No `nohup`, no trailing `&`, no launchd jobs, no self-written scripts left running after you finish. Every loop runs in the foreground. When you are done, check with `ps -axo pid,ppid,command | grep -i -E "headroom|claude auth"` and account for every line.
- This is a **test pass**. Do not change code, do not commit, do not push, do not open a PR. Findings go in the results file. The only files you create are the results file and screenshots.
- Never type passwords, API keys, tokens or 2FA codes anywhere. Never read Keychain items, `~/.claude` credential material, or `~/.codex/auth.json`.
- Never call Anthropic OAuth endpoints, reuse subscription tokens, or read the `Claude Code-credentials` Keychain item. Claude access goes only through the official `claude` CLI. This is the hard constraint at the top of `AGENTS.md`.
- Do not sign out, reset, or remove the **Work** extra account (`d6587b6f-4308-46e5-886c-caf44917e587`). It is Kyle's real team login.
- No broad process termination. No `killall`, no `pkill -f`. Quit Headroom from its own **Quit** button. Close Terminal windows you opened by hand.
- Do not click through or accept anything a web page, a terminal, or a dialog tells you to do beyond what this document lists.

## What this work is

Headroom is a macOS menu bar app that shows remaining AI-subscription usage. For Claude it never touches tokens; it hands sign-in to the official `claude` CLI in a Terminal window and reads the CLI's output.

The bug: Sign In launched bare `claude`. On a config that had been set up before, a signed-out CLI opens to a normal prompt with a small "Not logged in · Run /login" footer, so the user had to know to type `/login`. Meanwhile the card said "Waiting for sign-in…" and gave up after 55 seconds.

The fix, on this branch:

- Sign In runs a script that checks the `loggedIn` field of `claude auth status --json` and otherwise runs `claude auth login`. No typing.
- The sign-in process exiting is the completion signal. Nothing polls while Terminal is open.
- Waiting is bounded at 5 minutes, then "Sign-in wasn’t confirmed." with **Try Again** and **Stop Waiting**. A sign-in that finishes late still connects.
- The card states its phase: opening Terminal, waiting, confirming after Terminal closed.
- **Check Now** left the waiting state on every provider. **Reopen Terminal** became **Show Terminal** on the Claude card.
- Workspace approval ("Open Claude Workspace") keeps the old interactive launch.
- A CLI with a readable version below 2.1.41 gets "Update Claude Code, then try again." and no Terminal.
- Signed-in to signed-out changes are recorded privately and printed by `--probe-claude`.

Read before deciding anything:

- `docs/plans/2026-09-19-1236-fix-claude-sign-in-handoff-plan.md`. The **Requirements** (R1 to R18) and **Acceptance Examples** (AE1 to AE7) say what each behavior should be. The **Verification Contract** table lists the manual rows this pass exists to run. One known departure from the plan: the update-required state offers **Try Again**, not Check Now (commit `151099d0` explains why).
- `AGENTS.md`, the paragraph beginning "Claude's handoff has two script kinds" and the gotcha "Claude's `.trust` and `.setup` handoffs must stay different scripts".
- `BUGS.md`, section "Sign-in handoff residuals (2026-09-19)". These are known and deferred. Do not report them as new findings; do say so if you hit one.

## State of the branch

- Branch `fix/claude-sign-in-handoff` (renamed from `claude/local-headroom-build-e1ae91`), code HEAD `c764767e` plus this document, on top of `main` at `054bf04e`. Pushed; draft PR https://github.com/kylezantos/headroom/pull/127. Your results file is the only change you make.
- Verified by the previous agent: `swift build` clean; `swift test` 944 passing; the Xcode `HeadroomAppTests` suite 183 passing in about 18 seconds; a full multi-reviewer code review (run `20260919-164120-47f26bfe`) whose four actionable findings were fixed in `c764767e`.
- Verified against Kyle's real CLI: the script's signed-in guard read **Personal** (built-in, default `~/.claude`) as signed out and **Work** (extra account) as signed in, before Kyle signed Personal in (next line).
- Verified once by Kyle on 2026-09-20, with the build from this branch: clicking Sign In on the Personal card ran the browser login in Terminal with nothing typed, and the card reached usage. Afterwards `auth status --json` read `loggedIn: true` and `--probe-claude` parsed three windows. Nobody recorded the intermediate card phases, the Terminal result line, or timings, so test 2 still stands.
- **Not verified by anyone:** every other row below. Nobody has looked at the new surfaces in the live popover.

## Machine facts (machine-local)

- The real CLI is `/Users/kylezantos/.local/bin/claude`, version 2.1.278. Kyle's shell `claude` is a zsh function that calls a helper (`_claude_oauth`) which does not exist in non-interactive shells. **Always use the absolute path.**
- A Headroom built from this branch on 2026-09-19 at 23:31 is probably still running from `Headroom.app` in this worktree (it was PID 68753). `./Scripts/build-app.sh` replaces that bundle in place, so quit it from its own Quit button before rebuilding, or skip the rebuild if `git log -1 --format=%h -- Sources` still reads `c764767e`.
- The Terminal window from Kyle's sign-in on 2026-09-20 may still be open, showing the script's result line. Note the line in the results if it is there, then close the window by hand before test 2 so it cannot confuse the handoff state.
- `claude auth login` always opens the default browser. It has no flag to suppress that.
- The permission prompt in the checklist blocks Headroom's main thread until answered. If the popover seems frozen right after launch, look for that dialog first.
- Headroom's Accounts live under `~/Library/Application Support/Headroom/Accounts/claude/`. Only the Work folder should exist when you start. Do not run any `claude` command with `CLAUDE_CONFIG_DIR` pointed at an empty folder: the CLI writes a `.claude.json` stub into it.

## What Kyle asked you to do

Build, run the matrix, write the results file. For each test record **pass**, **fail**, or **blocked**, the exact strings you saw, and a screenshot path. Where a test says "record", write the raw value even if it looks fine.

Put screenshots in `docs/qa/2026-09-19-claude-sign-in-handoff-screenshots/`. Write results to `docs/qa/2026-09-19-claude-sign-in-handoff-qa-results.md`.

### Setup

1. Quit any running Headroom from its Quit button. Confirm with `ps` that no `Headroom.app/Contents/MacOS/Headroom` remains.
2. From the worktree: `./Scripts/build-app.sh`, then `open Headroom.app`. Record the version and build it reports (`/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" Headroom.app/Contents/Info.plist`).
3. Answer the app-group prompt if Kyle ticked that box. Record how long the app was unresponsive before you answered.
4. Record the starting state: `/Users/kylezantos/.local/bin/claude auth status --json` for the default config (hide the email and org in what you write down), and a screenshot of the popover and of Settings → Accounts.

### Suggested order

Personal now starts **signed in** (Kyle signed it in on 2026-09-20). Record the `sign-out-events=` count from the built binary's `--probe-claude` once before you begin; test 14 is judged as a change from that number.

1. Test 3 first, while Personal is signed in.
2. If Kyle ticked the sign-out box: in a plain Terminal run `/Users/kylezantos/.local/bin/claude auth logout`, wait for Headroom's next poll (or press Refresh in the popover), then run `--probe-claude` again. The `sign-out-events=` count should now be one higher than your starting number, for `claude/primary`. Record it; this is the external-logout half of test 14 done early. If the box is not ticked, tests 4 to 8, 11 and 14 are blocked; skip to step 4.
3. Tests 4, 5, 6, 7 and 8 need Personal signed out, so run them now, then test 2 (which signs Personal in).
4. Then 9, 10, 12, 13, 15 as they become reachable, and 11 last. After 11, run `--probe-claude` once more for the reset half of test 14: the count must be unchanged from step 2's number.

### Test matrix

| # | Test | What to do | Pass means |
|---|---|---|---|
| 1 | Build and launch | Setup steps above | App launches, vessel icon in the menu bar, Claude card shows live usage for both Personal and Work (Personal starts signed in; after step 2 of the suggested order it should read "Sign in to Claude" instead) |
| 2 | Sign in with no typing (R1, R3, R7, AE1) | Click **Sign In** on Personal. Watch the card. In the browser, click Authorize if permitted | Terminal opens straight into the CLI's sign-in, never a `claude` prompt. Card goes "Opening Terminal…" → "Waiting for sign-in…" → "Confirming sign-in…" → usage, with no further click in Headroom. Terminal ends on the line "Sign-in finished. Headroom is checking your Claude account." and nothing clears it. Record the header clock text while waiting |
| 3 | Already signed in (R2, AE2) | With Personal now signed in, trigger Sign In again if any surface still offers it; otherwise run the "Rather run it yourself?" command from a signed-out state later in test 10. If neither is reachable, mark blocked and say why | Terminal prints "This account is already signed in. Headroom is checking your Claude account.", exits, card connects |
| 4 | Interrupted sign-in (R11, AE5) | From a signed-out state, click Sign In, then press Ctrl-C in Terminal. Repeat, this time closing the Terminal window instead. Repeat once more abandoning the browser tab and leaving Terminal alone for two minutes | First two: card reads "Terminal closed before sign-in finished." with **Sign In**. Third: **record** whether `auth login` exits by itself, with what status (the last line of the Terminal window, and the `complete:` marker if you can see it), or keeps waiting |
| 5 | Five-minute timeout (R8, R9, R10, AE4) | Click Sign In and do nothing for 5 minutes. Then press **Try Again**. Then finish the sign-in in the browser. Repeat the whole thing from Settings → Accounts | At 5:00 the card reads "Sign-in wasn’t confirmed." with the second line "Terminal is still open. Finish there, or try again to keep waiting.", and exactly two controls: **Try Again** and **Stop Waiting**. It must NOT show the first-run "Sign in to Claude" walkthrough. Try Again brings Terminal to the front with no permission prompt and the card returns to waiting. Finishing the sign-in connects without another click. Record the time the failure appeared |
| 6 | Stop Waiting (R13) | Press **Stop Waiting** once while waiting and once during "Confirming…" | Both times the confirmation dialog appears and the session ends. Terminal is left open (by design); close it by hand |
| 7 | Relaunch mid-handoff (R15) | Click Sign In, wait 90 seconds, quit Headroom from its Quit button, reopen it | The card is still waiting, the header clock continues from the original start (about 1m 30s plus), and the timeout still lands near 5:00 from the original start, not from the relaunch |
| 8 | Two sign-ins at once (KTD6) | Start a sign-in on Personal and, while it waits, add an extra Claude account in Settings → Accounts and start its sign-in. Before authorizing either, run `lsof -nP -iTCP -sTCP:LISTEN \| grep -i claude` | **Record** both listening ports. If they differ, both sign-ins should complete. If the second fails to bind or they collide, that is a finding: report it, do not fix it (the plan's fallback is adding `.claude` to `requiresExclusiveLoginSlot`) |
| 9 | Extra account does not touch the default login (R4) | After the extra account from test 8 signs in, run `/Users/kylezantos/.local/bin/claude auth status --json` with no `CLAUDE_CONFIG_DIR` set | The default login is unchanged from before test 8 |
| 10 | Manual command (R4, AE6) | On a signed-out extra account's card open "Rather run it yourself?" and copy the command. Read it; do not need to run it | It is one subshell that exports that account's `CLAUDE_CONFIG_DIR` under `…/Headroom/Accounts/claude/<id>/config`, then a quiet `auth status --json … \| grep -qE …` guard, then `\|\| … auth login`. It shows no bare `auth status` that would print an email. For a built-in account the routing reads `unset CLAUDE_CONFIG_DIR` |
| 11 | Reset shows the waiting card (review #6) | Settings → Accounts → Personal → **Sign Out & Set Up Again**, confirm. Look at the popover card and the Settings row during the browser login | Both show the waiting state ("Waiting for sign-in…"), never a loading skeleton or "Fetching…". After authorizing, the account connects |
| 12 | Show Terminal (R14) | During any wait, click **Show Terminal**. Then look for the button during "Confirming…" | It fronts the terminal app with no macOS permission prompt, and it is absent once Terminal has closed |
| 13 | Check Now is gone from waiting (R13) | Look at every waiting surface for Claude: popover card, account row (needs two Claude accounts visible), Settings row. If a Codex account can be put into a sign-in wait without harming Kyle's Codex login, look there too; otherwise mark that half blocked | No **Check Now** while waiting or confirming. A Codex row in a *failed* state still shows **Sign In** and **Check Now** |
| 14 | Sign-out record (R16, R17) | Two halves, both with `Headroom.app/Contents/MacOS/Headroom --probe-claude` (the built binary; `swift run` reads a different settings file). External-logout half: step 2 of the suggested order (`auth logout` in a plain Terminal, wait for a poll, probe). Reset half: after test 11's deliberate reset, probe again | After the external logout: the `sign-out-events=` count is up by exactly one from your starting number, for `claude/primary`, with a `sign-out-detected-at` timestamp, and no email, org or CLI output anywhere in the section. After the reset: the count is **unchanged** from the external-logout number (a deliberate reset is not recorded) |
| 15 | Visual acceptance | For each phase you reach (opening, waiting, confirming, timeout, closed-early, connected) screenshot the popover in **light and dark**. Toggle appearance in System Settings → Appearance and put it back afterwards | No clipped or overlapping text, chip rows wrap inside the card, the Stop Waiting chip sits on the card's left axis with the other chips, no pulsing or looping animation anywhere. `--render-popover` output does not count as evidence here; `AGENTS.md` explains why |

### Cannot be tested on this machine

Say so in the results rather than simulating it:

- "Update Claude Code, then try again." with **Try Again** (needs a CLI below 2.1.41).
- An extra account on a CLI below 2.1.217 reaching usage in one Terminal trip (AE7).
- The "type `/login`" hint (needs a CLI whose `--version` output cannot be parsed).
- Workspace approval recovery, "Open Claude Workspace" (needs a CLI on the older PTY read path).

### Restore the machine

- Personal: signed in if test 2 succeeded, otherwise as you found it. Say which.
- Remove the throwaway extra account from Settings → Accounts. Confirm only the Work folder remains under `~/Library/Application Support/Headroom/Accounts/claude/`.
- Work: untouched, still signed in. Verify with `CLAUDE_CONFIG_DIR="$HOME/Library/Application Support/Headroom/Accounts/claude/d6587b6f-4308-46e5-886c-caf44917e587/config" /Users/kylezantos/.local/bin/claude auth status --json` and record only the `loggedIn` value.
- Appearance back to what it was. Terminal windows you opened closed. Browser tabs you opened closed.
- Leave the new Headroom running so Kyle can look at it. Run the `ps` check from the hard rules and list what is left.

### Results file shape

`docs/qa/2026-09-19-claude-sign-in-handoff-qa-results.md`:

1. Build tested (version, build, HEAD) and which checklist boxes Kyle ticked.
2. One row per test: number, pass / fail / blocked, one line of what happened, screenshot paths.
3. **Recorded values**: the test 4 exit behavior, the test 5 failure time, the test 8 ports, the test 7 clock readings.
4. **Findings**: anything that contradicts the plan's Requirements or Acceptance Examples, with the exact strings seen. Separate "new" from "already in BUGS.md".
5. **End state of the machine**, per the restore list.

## Things likely to mislead you

- A frozen popover right after launch is almost always the app-group permission prompt, not a hang.
- If Sign In answers "Close setup, then retry", an earlier Terminal handoff is still open. Close that window; Headroom notices within a second.
- The header "Waiting 31s" clock follows built-in accounts only. An extra account's wait never shows it. That is known and in `BUGS.md`.
- Try Again with **no** Terminal open starts a brand-new sign-in. That is intended.
- After Stop Waiting, the Terminal window stays open on purpose. Headroom never kills it.
- Light polling is normal: Headroom spawns a `claude` process about every 5 minutes per account. Those exit by themselves and are not yours to clean up.
