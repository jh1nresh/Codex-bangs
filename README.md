# Codex-bangs

A read-only macOS companion for Codex status, usage windows, recent tasks, and
Codex-compatible v2 pets.

## Current status

Phase 0 protocol spike is implemented. This repository is intentionally not yet
a notch UI app: the protocol gate showed that a newly spawned app-server can
read real rate limits and recent task history, but cannot see live status owned
by another Codex process on the currently installed runtime.

The truthful first UI slice is therefore:

- real multi-bucket usage and reset times;
- recent task metadata with privacy controls;
- connection, stale state, and Codex RTT;
- a v2 pet shell;
- `Live status unavailable` unless a shared-runtime capability is later proven.

It must not infer Working, Waiting, or Approval from recency.

## Run the spike

Requirements: macOS 14+, Swift 6, and a supported Codex executable. Phase 0 is
verified against `codex-cli 0.145.0-alpha.27`; it does not borrow HeyClicky's
private bundled runtime.

```bash
swift test
swift run codex-notch-pet-spike \
  --codex /Applications/ChatGPT.app/Contents/Resources/codex \
  --listen-seconds 3
```

The command prints a sanitized JSON summary. It does not print thread titles,
prompts, cwd paths, tool output, raw stderr, or credentials.

## Implemented in Phase 0

- regular-executable discovery with broken-symlink fallback;
- line-delimited JSON-RPC process transport;
- `initialize` / `initialized` handshake;
- `account/rateLimits/read` and multi-bucket mapping;
- `thread/list` with `recency_at` to `updated_at` compatibility fallback;
- state-DB-only recent-task reads and partial output when task history is slow;
- tolerant decoding for unknown and missing optional fields;
- explicit `notLoaded -> Live status unavailable` handling;
- frozen Codex v2 pet contract (`8x11`, `192x208`, `1536x2288`);
- anonymous decoder and fake-process integration fixtures.

## Privacy boundary

The spike never opens `~/.codex/auth.json`, starts a network listener, sends a
turn, approves a tool, modifies a thread, or logs raw app-server envelopes.

See [Phase 0 protocol receipt](docs/phase-0-protocol-receipt.md) and
[HeyClicky feature decision](docs/heyclicky-feature-decision.md).
