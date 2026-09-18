---
title: Cursor Agent usage is available through the official /usage panel
date: 2026-08-01
category: provider-integration
tags: [cursor, cli, usage, pty, compliance]
---

# Cursor Agent usage feasibility

## Decision

Cursor is feasible as a Headroom provider through the official `cursor-agent` CLI. Headroom
drives the CLI's interactive `/usage` panel in a pseudo-terminal, reads its rendered status,
and does not submit a model prompt. This follows the same official-client boundary used for
Claude: the vendor client owns authentication and the request; Headroom only parses output.

The prohibited alternatives remain prohibited: do not reuse `WorkosCursorSessionToken`, read
the IDE's `state.vscdb`, or call private dashboard endpoints.

## Verified surface

Verified on 2026-08-01 with Cursor Agent `2026.07.23-e383d2b` and an authenticated Pro+
account:

- `cursor-agent status --format json` reports authentication state but no usage; its
  `userInfo.email` field carries the signed-in address (verified 2026-08-01, used by
  `CursorStatusEmailProbe` for the account-identity display).
- `cursor-agent about --format json` reports plan metadata but no usage.
- The interactive `/usage` panel reports the plan, monthly included percentage, displayed
  reset day, and on-demand state/spend.
- Opening `/usage` does not send a model request.
- The permanent `swift run Headroom --probe-cursor` diagnostic parsed the live panel.

The redacted capture used by parser tests is
`Tests/HeadroomCoreTests/Fixtures/cursor-usage.txt`.

Reverified on 2026-08-31 with Cursor Agent `2026.08.25-3e8eec8`: the authenticated Pro+
panel still parsed as a live monthly window with on-demand disabled. The same probe succeeded
with `PATH=/usr/bin:/bin`, resolving the native `~/.local/bin/cursor-agent` install from a
Finder-like environment. An Apple Development-signed Headroom bundle on macOS 26.5.1 also
returned the live panel under that sparse path. Deterministic resolver tests pin
version-manager precedence, Homebrew fallback selection, missing and non-executable candidates,
and an executable disappearing before PTY input. Actual Homebrew/version-manager installs and
macOS 15 Sequoia remain separate runtime characterization work in `BUGS.md`.

## September 2026 startup screens

Headroom 1.4.1 could fail before `/usage` even when `cursor-agent status` reported a
valid login. A new `CursorProbe` directory opens Cursor Agent's **Workspace Trust Required**
screen. Headroom must report that state separately and offer to open the exact probe
workspace in the official CLI for the user to approve. The background probe must never
send the trust key, and interactive `--trust` does not reliably skip the menu.

The reported Cursor Agent `2026.09.15-d2fe57e` session displayed `Plan, search,
build anything`; other sessions still display `Ask (shift+tab to cycle)`. Both are
accepted only with the Cursor Agent
banner and without an approval screen. The probe still requires the selected `/usage`
autocomplete row before it sends the one Kitty Enter. Cursor can also pause on an MCP
server approval screen when external tools are configured. Headroom classifies that
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

**Interactive `--trust` is confirmed not to skip the menu.** Auto-trusting new
workspaces from the interactive CLI is an open Cursor feature request
(forum.cursor.com/t/162011), so the flag was removed from the probe rather than left
as a false reassurance.

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
use the executable Headroom resolved. A completed login can lead to trust, then MCP
approval, then usage; the setup coordinator retries after each user decision.

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

The panel renders reset precision only as `MMM d`. Headroom keeps that label verbatim and uses
the end of the displayed UTC day as the continuity-expiry boundary. This avoids discarding a
last-known meter at midnight on the reset day while not inventing a user-visible time.

Cursor remains single-account because this verification found no supported config-home
isolation equivalent to `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, or `GROK_HOME`.

## Official references

- [Cursor CLI installation](https://docs.cursor.com/en/cli/installation)
- [Cursor CLI authentication](https://docs.cursor.com/en/cli/reference/authentication)
- [Cursor CLI overview](https://docs.cursor.com/en/cli/overview)
