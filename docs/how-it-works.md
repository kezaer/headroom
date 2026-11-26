# How Pacemark reads your usage

Pacemark's rule: you always sign in through each provider's official client, and Pacemark reads
the usage that client reports. For Claude, Cursor, Antigravity, Copilot and OpenCode the client makes the
request itself; Codex and Grok are read with the sign-in their CLI saved, as described below.
Pacemark never creates its own sign-ins, reads browser cookies or scrapes private dashboards,
and polling never sends a model prompt or spends your allowance.

## Per provider

- **Claude** reads the 5-hour and weekly windows (and per-model weekly limits, such as Fable)
  from the official `claude` CLI's `/usage` report. Recent CLIs print it with
  `claude -p "/usage"`; older ones get the interactive panel in a pseudo-terminal. Both are a
  free status fetch, not a model call. Pacemark deliberately does **not** reuse or mint Claude
  subscription OAuth tokens: Anthropic's Feb 2026 policy prohibits that and enforces it
  server-side. The CLI notes its figures are approximate, based on local sessions on this
  machine, but it carries the official reset windows.
- **Codex/ChatGPT** reads `~/.codex/auth.json` and calls the `wham/usage` endpoint (the same
  data Codex's `/status` shows). If that local session is missing or expires, Pacemark shows a
  **Connect/Reconnect Codex** action that opens Terminal and runs the official `codex login`.
  Sign-in stays in the Codex CLI and browser; Pacemark never receives passwords, browser
  callbacks or tokens from the flow, and never writes or refreshes the auth file itself.
- **Grok** asks the official `grok` CLI for billing-period usage, preferring its ACP billing
  method and falling back to the CLI's billing HTTP transport. Sign-in stays in `grok login`;
  Pacemark only reads the CLI-owned auth and the redacted usage result.
- **Cursor** drives the official `cursor-agent` `/usage` panel in a pseudo-terminal and parses
  its included-usage period. Pacemark does not read Cursor's app database or reuse private
  dashboard sessions.
- **Antigravity** is off by default; turn it on in Settings → Accounts. The official `agy` CLI
  1.5.9 or newer reports the Gemini and Claude & GPT quota pools, each with 5-hour and weekly
  windows, plus any AI-credits balance. Pacemark reads only `/usage` and `/credits` and checks
  that each answer used no model turn or tokens. “Show 5-hour windows” in Settings → Appearance
  applies across the popover, menu bar and reminders. A signed-out read opens no
  sign-in page; Pacemark then waits for Refresh, the row’s Try Again or a sign-in through
  Pacemark. The CLI starts configured MCP servers and writes its own local logs during checks.
  Pacemark reads no Antigravity credential or Keychain item. These are Antigravity allowances,
  not Gemini app, Gemini CLI or Gemini API usage.
- **GitHub Copilot** is off by default; turn it on in Settings → Accounts. It shows one monthly
  AI credit meter for the account signed in to the official `copilot` CLI. Pacemark asks the
  CLI's local server for the monthly allowance (no prompt, no session, no credits spent) and
  scans the CLI's session logs under `~/.copilot/session-state/` for usage records. Those logs
  also hold your prompts and tool output: Pacemark decodes only the usage records and keeps no
  prompt or tool content. It never reads a Copilot or `gh` token. The logs advance only when
  the CLI runs, so a reading more than 15 minutes old shows as last known with its age, and use
  from VS Code or github.com appears only once the CLI next records it; until then the meter can
  show more room left than you have.
- **OpenCode** is off by default; turn it on in Settings → Accounts. It shows the OpenCode Go
  5-hour, weekly and monthly windows for each Console account signed in to the official
  `opencode` CLI, version 2.2 or newer. Pacemark runs the CLI's own usage read
  (`opencode api --standalone experimental.usage.limits`); the CLI makes the request, and
  Pacemark never reads an OpenCode credential, calls OpenCode itself or sends a model request. A
  window OpenCode reports as limited reads as fully used. A workspace without a Go plan says so.
  An OpenCode 1.x install shows **About OpenCode 2** instead: moving to 2.x is a one-way upgrade
  of your OpenCode data, so Pacemark never runs the read on 1.x and leaves the upgrade to you.
- **API spend** is optional and off by default. When enabled in Settings, Pacemark stores
  provider admin or reporting keys in the macOS Keychain and reads official cost-report
  endpoints: OpenAI organization costs, Anthropic organization cost reports and xAI team
  billing. These keys are separate from CLI subscription login.

> **First launch:** macOS asks "Pacemark would like to access data from other apps". That's
> Pacemark reading CLI-owned files and driving the official status surfaces. Click **Allow**; if
> you click Don't Allow, affected usage won't appear. Re-grant it later in System Settings →
> Privacy & Security.

## Multiple accounts

Pacemark shows any number of Claude, Codex, Grok and OpenCode subscriptions side by side,
tested up to 20 per provider. Each account refreshes on its own schedule, so one slow read
delays the others by at most one read, and Settings → General shows when a provider's accounts
run slower than the interval you chose.

The built-in account uses the CLI's normal `~/.claude`, `~/.codex`, `~/.grok` or
`~/.local/share/opencode` home, so existing installs need no setup. Additional accounts use
Pacemark-owned, owner-only config homes selected with `CLAUDE_CONFIG_DIR`, `CODEX_HOME`,
`GROK_HOME` or (for OpenCode) the four `XDG_*_HOME` variables, and sign in through the same
official CLIs in Terminal. Pacemark never copies one account's credentials into another home.
Codex and Grok also offer device-code sign-in for each account; OpenCode signs in with the
Console device code. OpenCode reports only the active Console workspace, so track a second
workspace as a second account.

Cursor is single-account because Cursor Agent has no isolated config-home mechanism. Copilot is
single-account too: its usage comes from the session logs of the CLI's default home, which a
separate Pacemark-owned home would never receive.
Antigravity is single-account because its CLI keeps sign-in in its own home and the Keychain;
isolating another account has not been proven.

An attached Codex home stays under its owner’s control. Pacemark reads its limits through the official app-server. Detaching the account leaves its files in place.

Add, rename or remove accounts in **Settings → Accounts**. Removing an additional account
deletes only its Pacemark-owned home; it does not touch the subscription, the built-in CLI login
or other accounts. Menu Bar settings let you choose which accounts and windows to display.

## Staying reliable

- Every CLI read has a hard deadline and a guaranteed kill of its whole process group, so a hung
  CLI can never stall the app.
- CLIs are found through your login shell's `PATH`, so a Finder-launched app still finds
  Homebrew, npm, nvm, asdf or mise installs.
- Reads are scheduled per account. Each CLI runs one read at a time, and timer reads back off
  when a CLI is busy, so polling never piles up. The default interval is 5 minutes, with a
  2-minute minimum.
- A failed read keeps the last known numbers, dimmed and labelled with their age, and retries
  on the next cycle. A number past its reset time is hidden rather than shown as current.
- Missing CLIs, signed-out accounts and other setup problems show a specific message and a
  next step. See [Troubleshooting](troubleshooting.md).
