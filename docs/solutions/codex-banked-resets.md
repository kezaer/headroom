# Codex banked resets are read-only metadata for the macOS popover

**Date:** 2026-09-22 · **Area:** `CodexProvider` / plan capsule

## Contract

ChatGPT Codex can bank spare rate-limit resets. The count arrives on the usage poll Pacemark
already makes, `GET chatgpt.com/backend-api/wham/usage`, as
`rate_limit_reset_credits.available_count`. The detail request is GET-only. Never call the sibling consume endpoint.

- A missing `rate_limit_reset_credits` key is not reported (`bankedResets == nil`).
- A present JSON `null` is reported zero, the same way this endpoint encodes an absent
  `secondary_window`.
- `available_count: 0` is also reported zero. A negative, fractional, or otherwise unusable
  present value is not reported.
- The shipping field is `available_count`. `applicable_available_count` is not read and is
  not printed by `--probe-codex`.

The macOS plan capsule shows `Plan •` at rest and `Plan · N reset(s)` on hover. It opens on
its own only while a live 5-hour or weekly window is Critical (≤15% remaining). Low does not
open it. The first live show of a higher count opens once, for four seconds, and that
acknowledgement is stored per account. A failed poll keeps the last known count. The menu bar and Settings specimens ignore the count.

Ledger shows the same credit count next to the 5-hour and weekly countdowns. A collapsed
row shows it when its selected window can be refreshed by those credits.

## Live observation (2026-09-22)

`swift run Pacemark --probe-codex` on the signed-in account printed `banked resets: 1`
(plan `prolite`, one weekly window). An integer on the shipping path verifies the field
name. This account was not at zero credits, so the zero encoding (`null` versus
`{"available_count": 0}`) is still unobserved. `applicable_available_count` was not printed;
the probe intentionally omits unread fields.

If a later zero-credit capture returns `null` while the account still holds credits, the
null-as-zero reading has to be revisited before relying on it. A body that returns
`{"available_count": 0}` needs no change: reported zero stays zero.

## Expiry details (2026-11-26)

One authenticated GET to `/backend-api/wham/rate-limit-reset-credits` returned an object
with numeric `available_count` and a `credits` array of objects. Each observed credit had
string `expires_at` and `granted_at` values in UTC with six fractional digits. For example,
a synthetic timestamp in the same format is `2030-01-02T12:34:56.123456Z`. The decoder
keeps only dates from available credits. Either date can be missing.

Each running account provider requests details when a positive count first appears, changes,
or six hours have elapsed since the last attempt. Zero credits require no detail request.
Borrowed homes use a separately identity-checked official app-server read with
`excludeResetCreditDetails: false`. Its camel-case dates are Unix seconds. A failed detail
read preserves usage and the last successful list. The Mac continuity cache carries its
original observation time so the tooltip can suppress dates at 24 hours. Expiry details stay
on the Mac.

For a live-window fixture capture, launch the QA controller with
`--scenario banked-resets --popover --bank-tip`. The flag pins the same PDS label and
expiry text under the built-in demo account’s chip.
