---
title: Preserve per-window freshness in partial Claude usage captures
date: 2026-07-27
category: logic-errors
module: PacemarkCore/UsageStore
problem_type: logic_error
component: service_object
symptoms:
  - A partial Claude refresh made fresh current-session and overall-weekly meters appear stale
  - A retained Fable percentage could look newly fetched even though Claude omitted that row
  - Repeated partial captures could keep an expired model-specific percentage visible too long
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [claude, fable, freshness, continuity]
---

# Preserve per-window freshness in partial Claude usage captures

## Problem

The official Claude `/usage` panel can produce a valid capture containing fresh
current-session and overall-weekly limits while omitting a separately rendered model limit
such as `Weekly (Fable)`. Treating freshness only at the snapshot level either discarded useful
continuity or mislabeled some of the card's data.

## Symptoms

- Marking the mixed snapshot stale correctly warned about the retained Fable value, but also
  dimmed Claude's freshly captured main limits.
- Marking the mixed snapshot live made the retained Fable percentage look freshly observed.
- Replacing the snapshot timestamp on every partial poll could renew old data indefinitely.
- Dropping Fable immediately caused the row to disappear on transient omissions and after an app
  relaunch, even though its last observation was still within the same reset window.

## What Didn't Work

- **Snapshot-only freshness:** one status cannot describe a fresh provider capture containing
  one retained row with older provenance.
- **Refreshing the retained row's timestamp:** the latest successful poll is not evidence that
  Claude returned the omitted limit, so it cannot advance that row's observation time.
- **Keeping the old percentage after reset:** continuity stops being truthful once the source's
  validity window has ended.
- **Dropping the row on the first omission:** Claude can omit or render the model-specific row
  independently of the main limits, so absence in one otherwise valid capture is not proof that
  the allowance no longer exists.

## Solution

Represent provenance on every `UsageWindow`, independently of snapshot freshness:

1. A row present in the current provider capture is `.live`.
2. A missing Claude weekly sub-limit may be retained as `.stale(observedAt:)`, preserving the
   original observation time.
3. Once that row's reset or bounded validity time passes, it becomes
   `.unavailable(since:)`; consumers keep the label but hide the percentage and meter value.
4. After one bounded fallback lifetime, remove the unavailable row.
5. If Claude returns the row again, replace the retained state with the fresh `.live` row.

`UsageWindowFreshness` defines those states and explicitly requires consumers to hide an
unavailable value
([`UsageModels.swift`](../../../Sources/PacemarkCore/Models/UsageModels.swift#L63-L70)).
`UsageContinuityPolicy` applies the same expiry rules during cache restoration, provider
failures, and successful partial merges
([`UsageContinuityCache.swift`](../../../Sources/PacemarkCore/Engine/UsageContinuityCache.swift#L153-L200),
[`UsageContinuityCache.swift`](../../../Sources/PacemarkCore/Engine/UsageContinuityCache.swift#L246-L323)).

The resulting mixed snapshot remains globally `.live`: its main windows came from the current
capture, while the retained sub-limit carries its own stale or unavailable provenance.

## Why This Works

Freshness now answers two separate questions:

- **Snapshot freshness:** did the provider return a usable capture now?
- **Window freshness:** was this particular limit observed in that capture, retained from an
  earlier capture, or retained only as an unavailable label?

Keeping the original observation anchor prevents repeated polls and relaunch restoration from
silently extending stale data. The reset boundary removes the numeric claim, and the second
bounded lifetime removes the tombstone. The cache fails closed when no trustworthy observation
anchor exists.

Tests cover the full lifecycle: partial capture, fresh recovery, relaunch restoration, reset-to-unavailable, and eventual removal even when later provider requests fail
([`UsageStoreTests.swift`](../../../Tests/PacemarkCoreTests/UsageStoreTests.swift#L79-L195),
[`UsageStoreTests.swift`](../../../Tests/PacemarkCoreTests/UsageStoreTests.swift#L197-L295)).

## Prevention

- Model provenance at the narrowest independently refreshed unit; do not generalize one stale
  sub-limit to the whole provider card.
- Never advance an observation timestamp unless the source actually returned that value.
- Give retained values an explicit reset/validity boundary and a separate bounded tombstone
  lifetime.
- Preserve per-window freshness across persistence and display.
- Bump serialized schemas when older consumers could otherwise interpret new freshness states as
  live data.
- Keep lifecycle tests spanning partial capture, process restart, reset, repeated failures, and
  fresh recovery.

## Related Issues

- [Codex window kind must come from source metadata](../codex-window-kind-mislabel.md) documents
  the same broader rule: provider data should preserve source truth instead of relying on
  structural assumptions.
