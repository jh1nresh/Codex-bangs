# Codex-bangs

A macOS notch companion for Codex status, usage, voice-first read-only pet tasks,
one-shot screen guidance, and Codex-compatible v2 pets.

## Current status

The first native macOS app slice is implemented. It builds a menu-bar app and a
top-center AppKit panel with hidden, compact, and expanded SwiftUI states, real Codex
usage windows, recent-task metadata, stale/offline handling, settings, and local
Codex v2 pets. `⌃⌥Space` summons Talk to pet and starts an explicit voice
question. The on-device transcript is shown for review before `Voice Ask`
creates a persisted Codex task in a read-only filesystem sandbox. `Look & guide`
takes a single explicit screenshot only after confirmation, sends it through
Codex, and removes the local image after the ephemeral response. On a notched
display the resting surface is invisible; hovering
the camera area reveals a compact black island with the pet inside it, and
`Open details` keeps that island's width and top edge fixed while extending the
panel downward. Notched placement uses the full screen, safe-area insets, and
auxiliary top areas; the no-notch fallback uses
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

## Install a release

After a release passes every distribution gate, its notarized
`Codex-bangs.dmg` appears on
[GitHub Releases](https://github.com/jh1nresh/Codex-bangs/releases). Drag
`Codex-bangs.app` into Applications, open it, then hover the camera housing.
No public build is published until the workflow verifies its Developer ID
signature, notarization ticket, stapling, DMG contents, and Gatekeeper checks.

## Pets

Every installation includes **Bloop**, an original built-in pet. To use a
personal Codex v2 pet, open Settings and choose `Import .codexpet…`, drop a
package onto the settings window or notch island, or double-click a `.codexpet`
package in Finder. A valid package is installed locally under
`~/.codex/pets/<pet-id>` and selected immediately.

`Create My Pet…` includes the Apache-2.0 `$hatch-pet` runtime needed by a fresh
download. If `~/.codex/skills/hatch-pet` is absent, the explicit
`Install Skill & Continue in Codex` action installs the bundled skill before
opening a bounded, reviewable request in the verified Codex desktop app. An
existing file, directory, or symlink is never replaced. Codex-bangs never sends
the Create My Pet prompt automatically; the user reviews and sends it in Codex.

See [Custom pet packages](docs/pets.md) for the format and safety contract.

## Implemented app slice

- real multi-bucket usage and reset times;
- recent task metadata with privacy controls;
- connection, stale state, and Codex RTT;
- a hover-revealed notch island plus no-notch capsule fallback;
- hidden, hover-compact, and pinned-expanded presentation states;
- restrained macOS 26 Liquid Glass controls with material fallbacks on macOS 14–15;
- single-click wave, double-click jump, and panel-local pointer gaze;
- outside-click, Escape, and explicit-button collapse back into the notch;
- a voice-first `Talk to pet` flow with review-before-send, direct read-only Ask,
  cancel, response, and a separate `Open in Codex` path for editable work;
- a permission-free `⌃⌥Space` global shortcut that expands the notch and starts
  an explicit voice question;
- explicit one-shot `Look & guide` screen capture with app exclusion, a 2560-pixel
  cap, private temporary storage, ephemeral task execution, and cleanup;
- local Skills discovery and per-agent skill selection without reading skill
  instructions;
- truthful configured-Plugin discovery with management handed back to Codex;
- Builder, Reviewer, and Guide profiles that can each summon a different pet;
- menu-bar Show/Hide, Refresh, Settings, and Quit controls;
- strict local v2 pet discovery with atlas and path validation;
- secure `.codexpet` import with symlink, traversal, conflict, and size checks;
- an original built-in Bloop pet plus a reviewable `$hatch-pet` creation handoff;
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

The app never opens `~/.codex/auth.json`, starts a network listener, approves an
elevated command, controls another app, or logs raw app-server envelopes. The
microphone is active only during a user-started recording; speech recognition is
required to stay on-device, audio is never written to disk, and the transcript is
reviewed before sending. `Voice Ask` passes that explicit transcript plus the
active role and selected skill invocation
through the supported local Codex executable on stdin, supplies the selected
task folder, uses `-s read-only -a never --ignore-user-config`, and stores only
the bounded final answer in memory; the resulting Codex task is persisted. Codex
may load the selected skill and read files its read-only sandbox permits. `Look
& guide` runs the same role/skill boundary as an ephemeral task with one attached
screenshot, excludes Codex-bangs itself, and deletes its private temporary
directory on success, error, or cancellation. Direct tasks ignore configured
plugins and MCP servers; `Open in Codex` is the explicit path for using them.

`Open in Codex` passes the active role, selected skill names, and reviewed
transcript to the locally registered Codex desktop URL handler, where the user still
reviews and presses Send. The handler must match the expected OpenAI code
signature and Codex bundle identifier. Drafts and displayed answers are
byte/character bounded and are not logged by Codex-bangs.

See [Phase 0 protocol receipt](docs/phase-0-protocol-receipt.md) and
[HeyClicky feature decision](docs/heyclicky-feature-decision.md).
