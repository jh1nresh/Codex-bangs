# Codex-bangs

A read-only macOS companion for Codex status, usage windows, recent tasks, and
Codex-compatible v2 pets.

## Current status

The first native macOS app slice is implemented. It builds a menu-bar app and a
top-center AppKit panel with hidden, compact, and expanded SwiftUI states, real Codex
usage windows, recent-task metadata, stale/offline handling, settings, and local
Codex v2 pets. On a notched display the resting surface is invisible; hovering
the camera area reveals a compact black island with the pet inside it, and
`Open details` expands the full panel. Notched placement uses the full screen,
safe-area insets, and auxiliary top areas; the no-notch fallback uses
`visibleFrame` only to measure the menu-bar height.

The protocol gate still matters: a separately spawned app-server can read real
rate limits and recent task history, but cannot normally see live status owned
by another Codex process. The UI therefore shows `Live unavailable` for
`notLoaded`; it never infers Working, Waiting, or Approval from recency.

## Run the app

Requirements: macOS 14+, Xcode 26, and a supported Codex executable. Open
`CodexBangs.xcodeproj` and run the `CodexBangs` scheme, or build from the command
line:

```bash
xcodebuild \
  -project CodexBangs.xcodeproj \
  -scheme CodexBangs \
  -destination 'platform=macOS' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/CodexBangs \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The development build is an unsigned local app. Developer-only UI fixture mode
is explicit and visibly labeled:

```bash
~/Library/Developer/Xcode/DerivedData/CodexBangs/Build/Products/Debug/Codex-bangs.app/Contents/MacOS/Codex-bangs \
  --preview --expanded
```

## Implemented app slice

- real multi-bucket usage and reset times;
- recent task metadata with privacy controls;
- connection, stale state, and Codex RTT;
- a hover-revealed notch island plus no-notch capsule fallback;
- hidden, hover-compact, and pinned-expanded presentation states;
- restrained macOS 26 Liquid Glass controls with material fallbacks on macOS 14–15;
- single-click wave, double-click jump, and panel-local pointer gaze;
- outside-click, Escape, and explicit-button collapse back into the notch;
- a `Talk to pet` text composer that opens a reviewable prompt in Codex;
- menu-bar Show/Hide, Refresh, Settings, and Quit controls;
- strict local v2 pet discovery with atlas and path validation;
- Reduce Motion and accessibility labels;
- `Live status unavailable` unless a shared-runtime capability is later proven.

## Development checks

Core logic and fake-process integration remain host-runnable through SwiftPM:

```bash
swift test
swift build -c release
swift run codex-notch-pet-spike \
  --codex /Applications/ChatGPT.app/Contents/Resources/codex \
  --listen-seconds 3
```

The command prints a sanitized JSON summary. It does not print thread titles,
prompts, cwd paths, tool output, raw stderr, or credentials.

## Core coverage

- regular-executable discovery with broken-symlink fallback;
- line-delimited JSON-RPC process transport;
- `initialize` / `initialized` handshake;
- `account/rateLimits/read` and multi-bucket mapping;
- `thread/list` with `recency_at` to `updated_at` compatibility fallback;
- state-DB-only recent-task reads and partial output when task history is slow;
- tolerant decoding for unknown and missing optional fields;
- explicit `notLoaded -> Live status unavailable` handling;
- frozen and validated Codex v2 pet contract (`8x11`, `192x208`, `1536x2288`);
- tested notch/no-notch geometry and nonzero display origins;
- anonymous decoder and fake-process integration fixtures.

## Privacy boundary

The app never opens `~/.codex/auth.json`, starts a network listener, sends a
turn, approves a tool, modifies a thread, or logs raw app-server envelopes.
`Open in Codex` passes only the text the user explicitly entered to the locally
registered Codex desktop URL handler, where the user still reviews and presses
Send. The handler must match the expected OpenAI code signature and Codex
bundle identifier. The draft is byte-bounded, not persisted, and not logged.

See [Phase 0 protocol receipt](docs/phase-0-protocol-receipt.md) and
[HeyClicky feature decision](docs/heyclicky-feature-decision.md).
