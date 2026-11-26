# Subscription warm-up

In Settings › Warm-up, enable the 5-hour limit, the overall Weekly
limit, or both for each Claude or Codex account. Antigravity offers the Gemini 5-hour and weekly limits. Every limit starts off. Named model pools
such as Fable, Sonnet, and Spark are excluded because the low-cost model cannot start those
pools. Pacemark drops any saved selections for those pools when it loads settings.
When a selected limit looks idle,
Pacemark sends one short message through the official client. For a window anchored by
first use, that starts the clock earlier and brings the next reset forward. All eligible
limits on the same account share one attempt. Settings shows the last attempt for each
verified login.

Warm-up is the user's explicit opt-in to use their own subscription through the official
client. It consumes plan quota. It is separate from usage reading. Claude usage reads
still go through the official CLI's `/usage` path. Warm-up keeps its own settings and
attempt ledger on the Mac and stores no prompt output, email address, or token.

| Provider | MVP capability |
| --- | --- |
| Claude | Official CLI print mode. Haiku, one turn, tools off, session persistence off. A separate login uses the same `CLAUDE_CONFIG_DIR` as its usage probe. |
| Codex | Official `codex exec`. GPT-6 Luna, read-only sandbox and ephemeral session. Separate and attached logins use their selected `CODEX_HOME`. |
| Antigravity | One Gemini 3.8 Flash prompt in the selected official CLI home, with the browser shim and sign-in guard from the usage probe. |
| GitHub Copilot | Usage reads only. Its renewal follows a calendar period. |
| OpenCode | Pending support for its isolated XDG homes. |
| Grok | Messages cannot advance its billing periods. |
| Cursor | Messages cannot advance its billing periods. |

## When it runs

- A live snapshot and live window must have observations no more than 15 minutes old.
  A candidate must show exactly 0% used. The reset may be absent, elapsed when the window
  was observed, or far enough away that the remaining time is within 3% of the window
  duration, with a maximum margin of 10 minutes. Invalid reset evidence is ineligible.
- A successful send records a deadline for each eligible limit on the verified login.
  Pacemark uses the upcoming reset shown at launch or the send completion time plus the
  full window duration when there is no upcoming reset. The limit becomes eligible again only after
  that deadline passes and a newer reading shows it idle.
- The default active hours are 07:00–23:00 local time. The start is inclusive and the end
  is exclusive. Overnight schedules and **Any time** are supported.
- Each account waits at least 30 minutes between attempts and gets at most four per
  local calendar day. The ledger also applies these guards across rows with the same
  verified login. The attempt is reserved before starting the CLI, so a timeout,
  failure, or interruption still counts. A reservation left behind by a crash appears as
  **Interrupted**. An unreadable ledger pauses warm-up.
- Claude and Codex consent is scoped to a verified login and window. It cannot follow the row to a
  different login. The runner checks opt-in, setup status, usage and active hours again
  before launch. Removing a row, stopping tracking, or resetting sign-in clears its
  selections. Antigravity exposes no account identity, so consent applies to its single tracked row. If two rows merge, the visible row represents both sets of selections.
- One client runs at a time in a Pacemark working folder with a 60-second
  deadline. The engine queues a fresh read of the visible account after the client runs.
  Demos, renders, benchmarks, capture mode and the test host keep warm-up inert.

## Qualification limits

The installed `claude --help` and `codex exec --help` were checked with temporary
homes. Claude help omits `--max-turns`, which is included from the checked-in CLI
research to enforce the turn cap. Neither listing confirms the chosen model is
available on a particular plan. An unsupported option or unavailable model can fail
the attempt. The sender has no fallback model.

A successful client exit records that the message completed. The next usage reading
supplies the reset time. The idle heuristic, actual quota charge and reset movement
have no authenticated end-to-end verification. Some weekly windows have fixed reset
times. Codex's current usage mapper can omit a bucket with no reset
timestamp, leaving warm-up without a reading for it. Managed CLI configuration can
affect runtime behavior, and the login can change between the final usage check and
client startup.

To inspect the resolved command and environment key names without sending a message, run
`swift run Pacemark --dry-run-warm-up <claude|codex|antigravity>`.

To render the Warm-up pane with example opt-ins and outcomes, run
`.build/debug/Pacemark --render-popover .build/warm-up-shots --warm-up-only`.
