# Buddy — Agent Instructions

<!-- Single source of truth for AI coding agents working in this repo. claude.md is a symlink to this file. -->

## Overview

Buddy is a macOS menu bar voice companion. It lives entirely in the status bar (`LSUIElement`,
no dock icon, no main window). Hold **Control + Option**, speak, and release: Buddy records the
audio, transcribes it with Whisper, captures a screenshot of every display, sends the transcript
plus the screenshots to a Kimi vision model, streams the answer back, speaks it with MeloTTS,
and can fly a cursor overlay to point at a referenced UI element.

**Every AI call runs on Cloudflare Workers AI and nothing else.** There is no Anthropic, OpenAI,
ElevenLabs, or AssemblyAI dependency anywhere. Do not add one. If a capability is needed, find it
in the Cloudflare Workers AI catalog or build it on top of the existing models.

No API credentials ship in the app. The app talks to a Cloudflare Worker proxy that holds the
account token as a secret and runs models via its bound `AI` binding.

## Architecture

- **App type**: Menu-bar-only (`LSUIElement=true`), accessory activation policy.
- **Layers**:
  - `BuddyKit` — platform-independent Swift package with all business logic (no AppKit). Unit tested.
  - `Buddy` — macOS app (SwiftUI + AppKit) for I/O: menu bar, audio, screenshots, overlay.
  - `worker` — Cloudflare Worker proxy (TypeScript) in front of Workers AI.
- **Chat + vision**: Kimi K2.7 Code (default) or Kimi K2.6 via the Worker `/chat` route (OpenAI-compatible SSE streaming).
- **Speech-to-text**: Whisper Large v3 Turbo via the Worker `/transcribe` route.
- **Text-to-speech**: MeloTTS via the Worker `/tts` route.
- **Screen capture**: ScreenCaptureKit, all displays, one labeled JPEG each.
- **Push-to-talk**: listen-only `CGEvent` tap for Control+Option (reliable in the background).
- **Element pointing**: the model appends `[POINT:x,y:label:screenN]` to a response; `PointTagParser`
  splits the spoken text from the tag, and `ScreenCoordinateMapper` maps the screenshot pixel to a
  global AppKit point on the correct display.
- **Concurrency**: `@MainActor` isolation for all UI/state; `async/await` throughout.

## Worker routes

| Route | Method | Workers AI model | Purpose |
|-------|--------|------------------|---------|
| `/chat` | POST | Kimi (allowlist) | Streaming vision chat (OpenAI-compatible SSE). |
| `/transcribe` | POST | `@cf/openai/whisper-large-v3-turbo` | Base64 audio → `{ text }`. |
| `/tts` | POST | `@cf/myshell-ai/melotts` | `{ prompt, lang }` → `audio/mpeg` bytes. |
| `/health` | GET | — | Unauthenticated liveness probe. |

Worker secret: `BUDDY_PROXY_SECRET` (shared bearer token). Worker var: `DEFAULT_CHAT_MODEL`.
The Worker enforces a model allowlist — requests for anything off-list are coerced to the default.

## Key files

| File | Purpose |
|------|---------|
| `Buddy/Sources/BuddyApp.swift` | SwiftUI `@main` entry; adapts `BuddyAppDelegate`. |
| `Buddy/Sources/BuddyAppDelegate.swift` | Wires up the controller, menu bar, and overlay at launch. |
| `Buddy/Sources/CompanionController.swift` | Central state machine for the full voice pipeline. |
| `Buddy/Sources/MenuBarController.swift` | `NSStatusItem` + floating `NSPanel` control panel. |
| `Buddy/Sources/CompanionPanelView.swift` | SwiftUI panel: status, model picker, permissions, quit. |
| `Buddy/Sources/ScreenCaptureService.swift` | Multi-monitor ScreenCaptureKit screenshots + geometry. |
| `Buddy/Sources/PushToTalkRecorder.swift` | Microphone capture → WAV payload for Whisper. |
| `Buddy/Sources/SpeechPlaybackService.swift` | Plays MeloTTS MP3 via `AVAudioPlayer`. |
| `Buddy/Sources/GlobalPushToTalkHotkeyMonitor.swift` | Control+Option `CGEvent` tap. |
| `Buddy/Sources/CursorOverlayController.swift` | Full-screen transparent overlay panel + model. |
| `Buddy/Sources/CursorOverlayView.swift` | SwiftUI cursor dot + response bubble. |
| `Buddy/Sources/AppConfiguration.swift` | Builds `BuddyConfiguration` from Info.plist/UserDefaults. |
| `BuddyKit/Sources/BuddyKit/WorkersAIClient.swift` | The Workers AI client (chat/STT/TTS). |
| `BuddyKit/Sources/BuddyKit/PointTagParser.swift` | Parses `[POINT:...]` tags. |
| `BuddyKit/Sources/BuddyKit/ScreenCoordinateMapper.swift` | Screenshot pixel → global AppKit point. |
| `BuddyKit/Sources/BuddyKit/SystemPrompts.swift` | The companion system prompt + POINT grammar. |
| `BuddyKit/Sources/BuddyKit/OpenCodeConfiguration.swift` | Generates `opencode.json`. |
| `worker/src/index.ts` | The Cloudflare Worker proxy. |

## Build, run, test

```bash
# macOS app
xcodegen generate && open Buddy.xcodeproj   # set signing team, Cmd+R

# BuddyKit tests
cd BuddyKit && swift test

# Worker tests + typecheck
cd worker && npm install && npm test && npm run typecheck
```

Do **not** run `xcodebuild` from the terminal — it invalidates the app's TCC permissions
(Screen Recording, Accessibility) and forces the user to re-grant them.

## Conventions

- Optimize names for clarity over concision. No single-character variable names. A reader with
  zero context should understand a name on sight (`screenshotPixelCoordinate`, not `pt`).
- All UI state mutates on `@MainActor`. Use `async/await` for all asynchronous work.
- SwiftUI for all UI unless a feature is AppKit-only (`NSPanel`, `NSStatusItem`, `CGEvent` tap).
- Every interactive control shows the pointing-hand cursor on hover.
- Comments explain *why*, especially for AppKit bridging and coordinate math — not *what*.
- Keep business logic in `BuddyKit` (testable, no AppKit). The app layer should be thin I/O glue.

## Hard rules

- **Cloudflare Workers AI only.** Never introduce another AI/STT/TTS provider or SDK.
- **No credentials in the app.** All model access flows through the Worker proxy.
- The Worker must keep its model allowlist; never let an arbitrary model identifier through.
- Do not commit the generated `Buddy.xcodeproj`, `node_modules`, `.build`, or any secret/`.dev.vars`.

## Integration contract (BuddyKit ⇄ app ⇄ worker)

1. The app builds a `BuddyConfiguration` (proxy URL + selected model) via `AppConfiguration`.
2. `WorkersAIClient.transcribeSpeech(audioData:)` → `POST /transcribe` → `{ text }`.
3. `ScreenCaptureService` produces `[LabeledScreenImage]` + `[CapturedDisplayGeometry]`.
4. `WorkersAIClient.streamCompanionResponse(...)` → `POST /chat` (SSE) → accumulated text.
5. `PointTagParser.parse(from:)` splits spoken text from an optional `[POINT:...]` tag.
6. `WorkersAIClient.synthesizeSpeech(text:)` → `POST /tts` → MP3 bytes → `SpeechPlaybackService`.
7. If a coordinate was parsed, `ScreenCoordinateMapper` maps it and `CursorOverlayController`
   animates the cursor to the global point on the indicated display.
