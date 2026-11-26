---
title: Cursor Agent usage is available through the official /usage panel
date: 2026-08-01
category: provider-integration
tags: [cursor, cli, usage, pty, compliance]
---

# Cursor Agent usage feasibility

## Decision

Cursor is feasible as a Pacemark provider through the official `cursor-agent` CLI. Pacemark
drives the CLI's interactive `/usage` panel in a pseudo-terminal, reads its rendered status,
and does not submit a model prompt. This follows the same official-client boundary used for
Claude: the vendor client owns authentication and the request; Pacemark only parses output.

The prohibited alternatives remain prohibited: do not reuse `WorkosCursorSessionToken`, read
the IDE's `state.vscdb`, or call private dashboard endpoints.

## Verified surface

Verified on 2026-08-01 with Cursor Agent `2026.07.23-e383d2b` and an authenticated Pro+
account:

- `cursor-agent status --format json` reports authentication state but no usage; its
  `userInfo.email` field carries the signed-in address (verified 2026-08-01, used by
  `CursorStatusEmailProbe` for the account-identity display).
- `cursor-agent about --format json` reports plan metadata but no usage.
- The interactive `/usage` panel reports the plan, monthly usage pools, displayed reset day,
  and on-demand state/spend.
- Opening `/usage` does not send a model request.
- The permanent `swift run Pacemark --probe-cursor` diagnostic parsed the live panel.

The redacted capture used by parser tests is
`Tests/PacemarkCoreTests/Fixtures/cursor-usage.txt`.

Reverified on 2026-08-31 with Cursor Agent `2026.08.25-3e8eec8`: the authenticated Pro+
panel still parsed as a live monthly window with on-demand disabled. The same probe succeeded
with `PATH=/usr/bin:/bin`, resolving the native `~/.local/bin/cursor-agent` install from a
Finder-like environment. An Apple Development-signed Pacemark bundle on macOS 26.5.1 also
returned the live panel under that sparse path. Deterministic resolver tests pin
version-manager precedence, Homebrew fallback selection, missing and non-executable candidates,
and an executable disappearing before PTY input. Actual Homebrew/version-manager installs and
macOS 15 Sequoia remain separate runtime characterization work in `BUGS.md`.

## Two-pool subscription usage (2026-09-21)

Cursor's current product documentation defines two independent monthly pools:

- **Cursor Models**, for Cursor's Grok and Composer models; and
- **Other Models**, for third-party models charged at provider prices.

Pro, Pro Plus, and Ultra include both pools, while the Start plan includes only Cursor Models.
Cursor Router can draw from either pool according to the model that handles a request. These
are billing-period pools, not rolling time windows, and unused allowance does not roll over.

The official CLI uses different source labels. A same-account comparison on 2026-09-21 found:

| Official `/usage` row | Pacemark / Plan & Usage label | Used |
|---|---|---:|
| `Auto` | Cursor Models | 1% |
| `API` | Other Models | 3% |

The Cursor Plan & Usage screen supplied for that account showed Cursor Models at 1% and Other
Models at 3%. Cursor Agent `2026.09.18-9a7762b` returned the same values through Pacemark's
shipping PTY probe. This establishes the mapping empirically for that CLI and account; Cursor's
documentation defines the two product pools but does not document the CLI's `Auto`/`API`
labels. Keep a live same-account comparison in the acceptance gate when the CLI layout or
labels change.

`Included` remains capture evidence and a compatibility fallback, not a third usage lane and
not a documented sum, maximum, or authoritative aggregate. The parser applies this matrix to
one coherent completed panel candidate:

| Completed candidate | Subscription result |
|---|---|
| `Auto` and `API` present | Cursor Models and Other Models, in that order; omit Included |
| Exactly one recognized named row present | Publish that named pool only |
| No named row, but Included present | Publish one Included compatibility window |
| Candidate ends before the later On-Demand row | Treat as incomplete and return stale |
| Unknown sibling usage row is present | Treat as unsupported and return stale |
| Named rows occur only across different incomplete repaints | Return stale; never synthesize a pair |

The On-Demand row is the positive completion marker because it paints after the subscription
table. Subscription completeness is decoded separately from on-demand state so a malformed or
partial subscription table cannot corrupt a valid spend result.

The shipping diagnostic was reverified on 2026-09-22 against the same CLI version and returned
the same redacted result:

```text
$ swift run Pacemark --probe-cursor
cursor-agent CLI: available
RESULT: live Cursor snapshot via official /usage panel
  plan: Pro+
  • Cursor Models  1% used  reset-evidence=scheduled
  • Other Models  3% used  reset-evidence=scheduled
  on-demand: disabled
```

The diagnostic intentionally prints no raw panel, credential, token, email, account identifier,
or private endpoint. Its output reconciled with the same-account Plan & Usage screen; there was
no value or label mismatch.

## September 2026 startup screens

Pacemark 1.4.1 could fail before `/usage` even when `cursor-agent status` reported a
valid login. A new `CursorProbe` directory opens Cursor Agent's **Workspace Trust Required**
screen. Pacemark must report that state separately and offer to open the exact probe
workspace in the official CLI for the user to approve. The background probe must never
send the trust key. It does pass `--trust`, which covers only Pacemark's own empty
workspace; the classifier and handoff exist for CLI builds that ignore the flag.

The reported Cursor Agent `2026.09.15-d2fe57e` session displayed `Plan, search,
build anything`; other sessions still display `Ask (shift+tab to cycle)`. Both are
accepted only with the Cursor Agent
banner and without an approval screen. The probe still requires the selected `/usage`
autocomplete row before it sends the one Kitty Enter. Cursor can also pause on an MCP
server approval screen when external tools are configured. Pacemark classifies that
separately and offers an official CLI handoff for the user's decision; neither the
background probe nor the handoff auto-approves servers. Fake PTY fixtures verify
trust, MCP approval, and current-prompt paths without contacting Cursor.

**The gate can paint after the ready frame.** Boot detection returns on the first
frame that carries the banner and an input placeholder, but Cursor can draw the trust
menu or the MCP dialog a moment later. The probe therefore keeps reading the PTY for
its 1.5 s settle window (it used to sleep through it) and classifies the accumulated
screen again before the first keystroke. This matters because `/usage` contains `a`,
the trust menu's approve key: typing it into a late gate would trust the workspace on
the user's behalf. `cursor-agent-late-trust.zsh` and `cursor-agent-late-mcp.zsh` pin
that ordering and assert no input reaches the fake CLI.

**Exiting the handoff session.** The interactive CLI exits on `/quit` or a double
Ctrl+C; a single Ctrl+C is swallowed by the TUI. The trust and MCP handoff scripts say
so. Either way the wrapper may report a nonzero status, which is why the coordinator
settles those handoffs on the next live probe rather than on the exit code.

**`--trust` stays on the probe.** A live check on Cursor Agent `2026.09.15-d2fe57e`
(below) showed the flag bypasses the menu in interactive mode and persists trust for
the path, so on current builds users never see the trust handoff at all. The flag is
scoped to Pacemark's own empty, owner-only `CursorProbe` directory and approves
nothing the user owns. Older builds that ignore the flag (auto-trust was an open
feature request, forum.cursor.com/t/162011) fall through to the trust classifier and
the Open Cursor Workspace handoff. That is also why the 1.4.1 report, captured with
`--trust` present on this same CLI version, was most likely the new input placeholder
rather than the trust screen.

**MCP approval is fixture-verified only.** The `MCP Server Approval Required` text
comes from a reported older CLI screen, and no machine with an unapproved server was
available for a live run. Cursor documents a persisted "local approved list" for
servers, so one handoff should clear the gate for later probes, but that has not been
observed. Before advertising the path, add a throwaway entry to `~/.cursor/mcp.json`,
run `--probe-cursor` (expect `MCP server approval required`), complete the Review
Cursor Tools handoff, and confirm the next probe reaches the panel. See `BUGS.md`.

A 2026-09-18 offscreen `--probe-cursor` run against the locally authenticated CLI
also parsed a live Pro+ panel (1% included usage, on-demand disabled). An earlier run
that day returned a transient capture failure; its stage was not recorded, so the
first failure should not be attributed to a panel-layout change.

The same live probe succeeded with `PATH=/usr/bin:/bin`; a fresh temporary workspace
opened the real trust screen. Cursor sign-in scripts clear `CURSOR_API_KEY` and
`CURSOR_API_ENDPOINT` to match the subscription probe, and clipboard fallback commands
use the executable Pacemark resolved. A completed login can lead to trust, then MCP
approval, then usage; the setup coordinator retries after each user decision.

## PR 125 local verification (2026-09-18)

Cursor Agent `2026.09.15-d2fe57e` returned `RESULT: live Cursor snapshot via official /usage panel` with Pro+, Monthly 1% used, scheduled reset evidence, and on-demand disabled. `swift build`, the 29 Cursor tests, the full 870-test Swift suite, and the Xcode app tests passed. Replacing only `CursorUsageCLIProbe.swift` with its `84538b9` version made both late-gate cases fail at `CursorProviderTests.swift:206` (`Expectation failed: await probe.capturePanel() == expected`) and line 207 (`Expectation failed: !FileManager.default.fileExists(atPath: workspace.appendingPathComponent("unexpected-input").path)`). Restoring the PR version made both pass. The failure proves the tests detect input sent into a gate after the ready frame.

Moving aside the existing `~/Library/Application Support/Pacemark/CursorProbe` and probing the recreated empty directory still returned live usage. That specific path was already trusted outside the directory itself, so its trust handoff and retry timing could not be tested. The original directory was restored. A new throwaway workspace did display this screen (the path line contained `/tmp/pacemark-pr125-cursor-workspace.PCRD0p`):

```text
  ╭──────────────────────────────────────────────────────────────────────────╮
  │                                                                          │
  │  ⚠ Workspace Trust Required                                              │
  │                                                                          │
  │  Cursor Agent can execute code and access files in this directory.       │
  │                                                                          │
  │  Do you trust the contents of this directory?                            │
  │                                                                          │
  │    /tmp/pacemark-pr125-cursor-workspace.PCRD0p                           │
  │                                                                          │
  │                                                                          │
  │  ▶ [a] Trust this workspace                                              │
  │    [q] Quit                                                              │
  │                                                                          │
  │  Use arrow keys to navigate, Enter to select, or press the key shown     │
  │                                                                          │
  ╰──────────────────────────────────────────────────────────────────────────╯
```

`q` declined the screen and exited with status 0. A later interactive launch with `--trust` bypassed the menu for that throwaway workspace; a subsequent launch without `--trust` also skipped it. Running that flag was a verification mistake because the plan's hard rule prohibited it, even though a later step asked to test it. The workspace was empty and was removed after the test; no Pacemark code or normal workspace used the flag. This contradicts the earlier note that `--trust` does not reliably skip the menu on this CLI version, and it is why the probe passes the flag again for its own workspace (see above). On the trusted workspace, `/quit` exited with status 0. One Ctrl+C left the CLI running and printed `Press Ctrl+C again to exit`; a second Ctrl+C exited, but the PTY runner aborted before it reported the process status.

Adding `pacemark-probe-test` (`/usr/bin/true`) to `~/.cursor/mcp.json` did **not** trigger an approval screen: the next Pacemark probe returned live usage. Only the `privacyCache/updatedAt` and `serverConfigCache/updatedAt` fields changed in `cli-config.json`; no approval decision or persistence was observed. `cursor-agent --help` lists `--approve-mcps`, which would approve automatically, but shows no option to start without MCP servers. Both config files were restored byte for byte from backups. The MCP classifier wording and app handoff remain unverified live.

The unsigned PR app built and launched as a separate process. Native UI control timed out while attaching to Pacemark, so the card labels, waiting clock, Check Now, decline path, and retry timing have no live acceptance result from this run. The test copy was closed without terminating the user's existing app.

## PTY details that are load-bearing

Cursor Agent uses Ink and enables the Kitty keyboard protocol. A raw pseudo-terminal must:

- answer the OSC 11 terminal-background query or the initial paint can stall;
- send Enter as Kitty CSI-u (`ESC [ 13 u`), including a pause between accepting slash-command
  autocomplete and executing the command;
- impose hard boot and panel deadlines; and
- terminate the process group with a bounded nonblocking reap, because the bundled Node
  runtime can linger while exiting.

Removing any of these can turn a valid authenticated session into a timeout or an unbounded
probe.

## Data limitations

The panel renders reset precision only as `MMM d`. Pacemark keeps that label verbatim and uses
the end of the displayed UTC day as the continuity-expiry boundary. This avoids discarding a
last-known meter at midnight on the reset day while not inventing a user-visible time.

Cursor remains single-account because this verification found no supported config-home
isolation equivalent to `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, or `GROK_HOME`.

## Official references

- [Cursor CLI installation](https://docs.cursor.com/en/cli/installation)
- [Cursor CLI authentication](https://docs.cursor.com/en/cli/reference/authentication)
- [Cursor CLI overview](https://docs.cursor.com/en/cli/overview)
- [Cursor usage and limits](https://prod.cursor.com/help/models-and-usage/usage-limits)
- [Cursor available models](https://prod.cursor.com/help/models-and-usage/available-models)
