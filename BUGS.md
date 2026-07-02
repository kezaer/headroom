# Deferred / Follow-up

Non-blocking items surfaced during code review, deferred deliberately. None block the
current build (42 tests pass).

## Reliability

- **No backoff on repeated endpoint failures.** `PollingEngine` re-polls every 3–5 min
  even when an undocumented endpoint fails persistently (reliability P2). The interval is
  already moderate, but exponential backoff on consecutive transient/429 failures would
  avoid hammering a down endpoint. Design choice — deferred.

## Testing (integration-level, need real resources)

- **`RedirectBlockingHTTPClient` has no live integration test.** Provider tests inject the
  `UsageFetching` mock; the delegate policy is unit-tested directly, but nothing asserts a
  real 3xx is surfaced as-is against a local redirecting server (security testing gap).
- **`SystemKeychain.writeOwnClaude` attributes untested.** No test asserts the written item
  sets `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and omits `kSecAttrSynchronizable`,
  so a future regression removing the device-local/non-sync guarantee would pass CI. Needs
  a real-Keychain integration test (excluded from the unit suite by design).

## U9-gated (re-verify before enabling Claude self-refresh)

- Confirm Anthropic's refresh token is **non-rotating** before enabling self-refresh, else
  it desyncs Claude Code (the P0 risk). `ReauthOnlyRefresher` keeps it disabled until then.
- `ClaudeVersion.detected()` runs `claude` via PATH (`/usr/bin/env`). For a personal
  non-sandboxed app this is low risk, but prefer an absolute/validated path if hardening.
- Redaction covers `sk-ant-`/`sess-`/JWT/≥40-char shapes only; if a future change ever
  interpolates a caught error into a `FailureReason`, short OpenAI tokens could slip
  through. Today no live path interpolates errors (all failure messages are literals).

## Minor (advisory)

- `MenuBarLabel` uses a fixed `Font.system(size:)` (menu bar height is OS-constrained, so
  Dynamic Type has limited effect there).
- Codex DTO tolerates several percent field names (`used_percent`/`usage_percent`/
  `utilization`) — intentional leniency for the undocumented endpoint; confirm the real
  field against a live `wham/usage` capture and tighten.
