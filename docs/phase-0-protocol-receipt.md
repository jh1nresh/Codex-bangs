# Phase 0 protocol receipt

Date: 2026-07-21

## Decision

Phase 0 is complete. Real quota and recent-task history are viable. Full live
Working / Waiting / Approval status is blocked for an independent monitor
process on the currently installed Codex runtime.

Proceed only with the static notch shell and truthful read-only data. Keep live
status UI behind a capability gate; otherwise render `Live status unavailable`.

## Verified local context

- Codex executable: ChatGPT app bundle, regular signed arm64 file.
- CLI version: `codex-cli 0.145.0-alpha.27`.
- Runtime support is currently pinned to this verified protocol generation and
  explicit `app-server --stdio`; HeyClicky's private bundled Codex is not a
  runtime dependency or fallback candidate.
- Xcode: 26.6 (`17F113`).
- Swift: 6.3.3.
- Five local pet packages were checked without opening auth data. Every package
  uses `spriteVersionNumber: 2`, a safe relative `spritesheet.webp`, and a
  `1536x2288` atlas.
- The PATH-installed Codex wrapper's vendor executable is missing, so bounded
  `--version` validation fails and the locator skips it.

## Live app-server probe

The Swift spike successfully performed:

1. `initialize`, followed by the canonical parameterless `initialized` notice;
2. `account/rateLimits/read`;
3. `thread/list` sorted by `recency_at`;
4. a bounded notification listen.

The sanitized sample returned two rate-limit buckets with real windows, zero
malformed protocol lines, and 20 recent threads. All 20 thread statuses were
`notLoaded`; the separate server observed zero active threads and no
`thread/status/changed` event during its listen window.

A focused cross-process check was also run while the current Codex task was
actively executing. A fresh app-server could read that exact thread with turns
excluded, but its status was still `notLoaded`, its active flags were empty,
`thread/loaded/list` returned zero IDs, and a five-second listener saw no
matching status change.

This is sufficient evidence that current runtime status is process-scoped for
this architecture. Recency must not be used as a synthetic Working signal.

## Protocol decisions frozen by the spike

- Status values: `notLoaded`, `idle`, `systemError`, and `active`.
- Active flags: `waitingOnApproval` and `waitingOnUserInput`.
- `notLoaded` maps to monitor state `unavailable`, not `idle`.
- `account/rateLimits/updated` is sparse; a future store must merge it into the
  last snapshot or refetch instead of clearing absent values.
- Rate-limit windows are data-driven. Missing windows remain absent.
- Percentages clamp to `0...100`; remaining is `100 - used`.
- A duration near 10,080 minutes may be labeled Weekly; no other window may be.
- Current sorting uses `recency_at`; older compatible runtimes may require
  `updated_at`, so the spike retries only on JSON-RPC invalid-request error.
- Thread decoders whitelist the fields needed for selection and never log raw
  thread envelopes.
- Recent-task reads use the state DB only, a 10-second data timeout, and a safe
  partial-error result so a slow history query never erases a valid quota
  snapshot.

## Verification

```bash
swift test
swift run codex-notch-pet-spike \
  --codex /Applications/ChatGPT.app/Contents/Resources/codex \
  --listen-seconds 3
```

Expected test receipt: 13 tests, 0 failures. The runtime command emits only a
sanitized local JSON summary.

Final stability gate: three consecutive state-DB-only live probes all returned
`connection: connected`, two usage buckets, 20 recent threads, zero malformed
lines, and `selectedState: unavailable`; none fabricated an active thread.

## Next engineering slice

Build a static AppKit `NSPanel` + SwiftUI shell with fake status fixtures, real
quota/recent-task data, stale/offline handling, v2 pet loading, and an explicit
live-status-unavailable state. Do not claim full MVP status until a supported
same-runtime connection or other official live-status surface is proven.
