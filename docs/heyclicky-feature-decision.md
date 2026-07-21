# HeyClicky feature decision

Date: 2026-07-21

## Product boundary

HeyClicky is a general screen-aware voice and agent companion. Codex Notch Pet
is a Codex-specific, read-only telemetry companion. The useful overlap is the
sense of presence, not screen capture, voice input, retained AI context, or
delegated action.

HeyClicky's official pages say screen capture occurs on an explicit hotkey and
that screenshots and voice/transcript/prompt data pass through its backend to
third-party AI providers. It says screenshots are not stored, while basic text
summaries may be retained for context. The exact permission set of the current
private build is not publicly documented; permissions visible in the legacy
open-source build are historical evidence only.

## Adopt

| Capability | Decision for Codex Notch Pet |
| --- | --- |
| Persistent character presence | Core: notch pet, deterministic state animation, click-to-expand. |
| Contextual reactions | Core: fixed local microcopy such as `Waiting for you`, `Usage low`, and `Offline`; no model call and no prompt access. |
| Menu bar and non-activating panel | Core: matches the existing AppKit boundary. |

## Later

| Capability | Safe form |
| --- | --- |
| Cursor-side companion | Explicit hotkey opens a small read-only status bubble; no constant cursor chasing. |
| Cursor awareness | After the shell works, eyes/head may look toward the local cursor; disable with Reduce Motion and never capture the screen. |
| Return to Codex task | Navigate through a supported Codex task link/API only; never send a turn or approve work. |
| Spoken status | Optional macOS system TTS with fixed templates; no microphone and no cloud. |
| Character/personality packs | Continue the local v2 pet-package path without expanding data permissions. |

## Reject from this product

- push-to-talk, dictation, and voice Q&A;
- screenshots, ScreenCaptureKit understanding, and screen-content memory;
- cross-app arrows, automated clicks, or Accessibility-driven actions;
- generic AI chat or retained prompt/transcript summaries;
- background agents that build, research, email, or approve on the user's behalf.

Those features change the app from a monitor into an agent, add high-risk
permissions, duplicate Codex, and violate the privacy, no-cloud, read-only, and
authority boundaries. CDP injection remains separately prohibited but is not
required by native ScreenCaptureKit, Accessibility, or `NSPanel` overlays. If
pursued, these agent capabilities need a separate product and permission
onboarding.

## Local feasibility evidence

The installed HeyClicky build runs a bundled Codex child as an app-server over
stdio. This confirms its process architecture, not which JSON-RPC methods
HeyClicky calls. Separately, this project's live probe against the ChatGPT-
bundled Codex runtime confirmed that the same stdio architecture can obtain
quota and recent-task history. A separately launched copy of HeyClicky's
bundled Codex runtime also returned `notLoaded` for other processes' threads;
neither observation solves the cross-process live-status blocker.
Codex Notch Pet must use the user's supported Codex/ChatGPT executable; it must
not discover or depend on HeyClicky's private bundled runtime.

## Current primary sources

- [HeyClicky product and FAQ](https://www.heyclicky.com/)
- [HeyClicky privacy policy](https://www.heyclicky.com/privacy-policy)
- [HeyClicky public releases](https://github.com/farzaa/clicky-releases/releases)
- [HeyClicky legacy open-source macOS app](https://github.com/farzaa/clicky)

The public source repository represents an older version; current implementation
details not confirmed by the product, privacy, or release pages are treated as
inference rather than current fact.
