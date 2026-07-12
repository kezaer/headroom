# Codex "5-hour" window mislabeled (really the weekly window); weekly row missing

**Anchor:** `#codex-window-kind` · **Date:** 2026-07-12 · **Area:** `CodexProvider` / `UsageDTOs`

## Symptom

The Codex card in the popover showed a single row: **"5-hour · Resets in 5d 19h · 67% left"**.
A 5-hour window resetting in 5+ days is impossible, and the weekly readout was gone entirely.
At the same time, the official Codex usage panel showed only a weekly allowance. That confirmed
the absent 5-hour row was valid upstream/account behavior; Headroom's bug was mislabeling the
weekly row that remained, not failing to recreate a missing five-hour allowance.

## Root cause

`CodexProvider.decode` assigned each window's `WindowKind` by **slot position**:
`rate_limit.primary_window` → `.fiveHour`, `secondary_window` → `.weekly`. That assumption is
false. The live `chatgpt.com/backend-api/wham/usage` response tags each window with its true
duration in **`limit_window_seconds`** (18000 = 5h, 604800 = 7d), and the slot a window lands in
is **plan-dependent**:

- On the `prolite` plan, the account's *weekly* window is returned in `primary_window`
  (`limit_window_seconds: 604800`) with `secondary_window: null`.
- So the weekly window was force-labeled "5-hour", showed the weekly reset ("5d 19h"), and no
  actual weekly row was produced. There was no 5-hour window in the response to show.

Do not assume every account or plan always returns both windows, and do not synthesize a missing
row. Render the windows Codex actually returns and identify each from its declared duration.

Contributing factor: `limit_window_seconds` wasn't in the DTO at all. The Codex DTO field names
were written speculatively (`BUGS.md` had flagged "Codex field-name verification" as never done),
so nobody had checked the real shape.

## Fix

Derive kind from `limit_window_seconds`, not slot position:

- Added `limit_window_seconds` to `CodexWindowDTO` / `CodexNamedWindowDTO`.
- Added `CodexWindowClassifier.kind(limitWindowSeconds:positionalDefault:)` — maps the verified
  18000-second and 604800-second values to `.fiveHour` and `.weekly`, respectively. Any other
  declared duration becomes `.other("Nh"/"Nd")` (honest, never force-fit), and the classifier
  falls back to the slot-based default only when the field is absent (keeps older/other response
  variants and pre-existing fixtures working).
- `CodexProvider` routes primary/secondary/additional windows through it. Additional allowance
  windows are now suffixed with their real duration (`"… Weekly"`) instead of a hardcoded `"5h"`.

Verified live: `swift run Headroom --probe-codex` now prints `weekly 33% used …` (was `fiveHour`).

## How to re-diagnose if it recurs

1. Capture the real response — the parser is only as correct as the shape it's pinned to:
   ```bash
   TOKEN=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.codex/auth.json')))['tokens']['access_token'])")
   ACCT=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.codex/auth.json')))['tokens'].get('account_id',''))")
   curl -s https://chatgpt.com/backend-api/wham/usage -H "Authorization: Bearer $TOKEN" -H "chatgpt-account-id: $ACCT" | python3 -m json.tool
   ```
   (Do not print the token.) Or run `swift run Headroom --probe-codex` to see the parsed windows.
2. Compare `limit_window_seconds` / field names in the live JSON against `UsageDTOs.swift`.
3. If Codex added a window duration, extend `CodexWindowClassifier` and update the fixtures in
   `CodexProviderTests.swift` to mirror the real shape.

## Lesson

Provider window identity must come from a **self-describing field the server sends**
(`limit_window_seconds`), never from positional assumptions about response structure — the same
principle behind Claude's parser keying on stable shapes rather than line positions. Speculative
DTO field names are a latent bug until verified against a live capture.
