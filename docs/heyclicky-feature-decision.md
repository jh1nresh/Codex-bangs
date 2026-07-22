# HeyClicky feature decision

Date: 2026-07-22

## Product boundary

HeyClicky is a general screen-aware voice and agent companion. Codex-bangs stays
Codex-specific, but now adopts a bounded assistant layer on top of telemetry:
read-only tasks, an explicit push-to-talk shortcut, one-shot screen guidance,
and agent-pet profiles. It still does not continuously watch, listen, click, type,
approve tools, or act in other apps.

HeyClicky's official pages say screen capture occurs on an explicit hotkey and
that screenshots and voice/transcript/prompt data pass through its backend to
third-party AI providers. It says screenshots are not stored, while basic text
summaries may be retained for context. The exact permission set of the current
private build is not publicly documented; permissions visible in the legacy
open-source build are historical evidence only.

## Adopt

| Capability | Decision for Codex Notch Pet |
| --- | --- |
| Persistent character presence | Core: hidden at rest, pet inside a hover-revealed compact notch island, deterministic state animation, explicit detail expansion. |
| Contextual reactions | Core: truthful status labels plus deterministic semantic pet animations; no model call and no prompt access. |
| Menu bar and non-activating panel | Core: matches the existing AppKit boundary. |
| Pet interaction | Core: single-click wave, double-click jump, and panel-local pointer gaze; no global tracking. |
| Talk to pet | Core: a user-started recording is transcribed on-device and reviewed before `Voice Ask` runs a persisted local Codex task with a read-only filesystem sandbox; `Open in Codex` remains the editable/approval path. |
| Global shortcut | Core: `Control-Option-Space` uses the macOS Carbon hot-key API to open the panel and start recording; it needs no Accessibility permission. |
| Screen guidance | Core: explicit one-shot capture only, excludes Codex-bangs, caps resolution, uses an ephemeral Codex task, then deletes the private local image. |
| Skills and agents | Core: read-only skill-name discovery, per-role skill selection, and Builder/Reviewer/Guide profiles with separately assigned pets. |
| Plugins | Core: display configured plugin identifiers; installation, removal, enablement, and permissions stay in Codex. |

## Later

| Capability | Safe form |
| --- | --- |
| Return to an existing Codex task | Navigate through a documented task link/API if one becomes available; never guess an internal thread route. |
| Spoken status | Optional macOS system TTS with fixed templates; separate from user-started voice questions. |
| Character/personality packs | Continue the local v2 pet-package path without expanding data permissions. |
| Approval-aware editable tasks | Requires a long-lived controller for approvals, user input, cancellation, and recovery. Until then editable work opens in Codex. |

## Reject from this product

- background dictation, wake words, and always-listening voice Q&A;
- continuous screenshots, screen-content memory, and background observation;
- cross-app arrows, automated clicks, or Accessibility-driven actions;
- background agents that build, research, email, or approve on the user's behalf.
- one-click editable task execution without a long-lived approval, input,
  cancellation, and recovery controller.

Those rejected features add standing authority or ambient collection. The
implemented assistant path is deliberately user-triggered and bounded: the app
records only after an explicit action, requires on-device recognition, stops on
finish, cancel, timeout, or collapse, and lets the user review the transcript.
Codex receives that transcript, the active role and selected skill invocation,
plus one attached screenshot only for `Look & guide`. The filesystem is read-only, screen
guidance is ephemeral, and Codex-bangs exposes Stop but no approval button.
Direct tasks use `--ignore-user-config`, so configured plugins and MCP servers are
not loaded; `Open in Codex` remains the explicit path for using them.

## Local feasibility evidence

The installed HeyClicky build runs a bundled Codex child as an app-server over
stdio. This confirms its process architecture, not which JSON-RPC methods
HeyClicky calls. Separately, this project's live probe against the ChatGPT-
bundled Codex runtime confirmed that the same stdio architecture can obtain
quota and recent-task history, but not cross-process live status.
Codex Notch Pet must use the user's supported Codex/ChatGPT executable; it must
not discover or depend on HeyClicky's private bundled runtime.

The currently installed Codex desktop app also registers a local
`codex://new?prompt=...` route. Codex-bangs uses it only as an explicit review
handoff: it pre-fills a new composer and does not start a turn. Because the
route is not publicly documented, failure to open is surfaced and this remains
a compatibility risk rather than a task-execution contract. Before opening,
Codex-bangs binds the handoff to a valid app signed by OpenAI's current team and
registered with the expected Codex bundle identifier.

Direct Voice Ask uses the supported local `codex exec` CLI contract instead. The
prompt is written on stdin rather than command-line arguments, user configuration
is ignored, output parsing is bounded to final JSONL agent messages, cancellation
terminates the child, and stderr is never surfaced. Look & guide adds `--ephemeral -i
<private-png>` and removes the UUID-scoped directory on every terminal path.

## Current primary sources

- [HeyClicky product and FAQ](https://www.heyclicky.com/)
- [HeyClicky privacy policy](https://www.heyclicky.com/privacy-policy)
- [HeyClicky public releases](https://github.com/farzaa/clicky-releases/releases)
- [HeyClicky legacy open-source macOS app](https://github.com/farzaa/clicky)
- [Apple DynamicIsland API](https://developer.apple.com/documentation/widgetkit/dynamicisland)
- [Apple Live Activities design guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities)

The public source repository represents an older version; current implementation
details not confirmed by the product, privacy, or release pages are treated as
inference rather than current fact.

WidgetKit's `DynamicIsland` is an iPhone Live Activity API, not a macOS notch
API. Codex-bangs borrows only its minimal/compact/expanded presentation model;
the macOS implementation remains public AppKit and SwiftUI.
