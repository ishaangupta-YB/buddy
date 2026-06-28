# Buddy — Architecture Report

## 1. Goal

Buddy is a rebuilt, from-scratch macOS voice companion inspired by the feature set of an earlier
prototype, but written fresh with three hard constraints:

1. **Cloudflare Workers AI is the only AI backend** — for speech-to-text, chat/vision, and
   text-to-speech. No other provider or SDK appears anywhere in the codebase.
2. **No credentials ship in the app.** A thin Cloudflare Worker proxy holds the account token and
   runs the models on its bound `AI` binding.
3. **Native, efficient macOS app** that runs entirely from the menu bar.

It additionally pins the OpenCode coding agent to the same Workers AI Kimi models so an agentic
coding workflow shares one backend.

## 2. Three-layer design

Buddy is split into three layers that can each be built and tested in isolation.

### 2.1 BuddyKit (platform-independent Swift package)

`BuddyKit` holds *all* business logic and has **no AppKit/SwiftUI dependency**, so it builds and
unit-tests on any Swift platform (it is tested headless on Linux CI). Components:

- **`WorkersAIClient`** — the single entry point for all three model interactions:
  - `streamCompanionResponse(...)` builds an OpenAI-compatible chat request (system prompt +
    conversation history + the user's transcript + one image part per screenshot), POSTs it to
    `/chat`, and decodes the streamed SSE deltas into accumulated text.
  - `transcribeSpeech(audioData:)` base64-encodes the recorded audio and POSTs it to `/transcribe`.
  - `synthesizeSpeech(text:)` POSTs the spoken text to `/tts` and returns MP3 bytes.
- **`HTTPTransport`** — a protocol abstracting the network so tests inject a `MockHTTPTransport`;
  `URLSessionHTTPTransport` is the production implementation (and supports streaming line reads).
- **`PointTagParser`** — parses a trailing `[POINT:x,y:label:screenN]` tag, returning the spoken
  text (tag stripped) plus the optional coordinate, label, and 1-based screen number.
- **`ScreenCoordinateMapper`** — converts a screenshot pixel (top-left origin) to a global AppKit
  point (bottom-left origin): clamp → scale by points/pixels → flip Y → translate by display origin.
- **`SystemPrompts`** — the companion persona, the strict POINT-tag grammar, and a spoken error fallback.
- **`ConversationHistoryStore`** — a bounded FIFO of recent exchanges for context.
- **`WorkersAIModelCatalog`** — the Kimi model definitions and the vision-capable subset.
- **`OpenCodeConfiguration`** — deterministically renders `opencode.json` pinned to Workers AI.
- **`ChatCompletionRequestBuilder` / `WorkersAIResponseDecoders`** — request/response (de)serialization.

### 2.2 Buddy (macOS app, SwiftUI + AppKit)

A thin I/O layer that delegates every decision to BuddyKit:

- **`CompanionController`** — the `@MainActor` state machine (`idle → listening → processing →
  responding → idle`) that orchestrates the pipeline and owns the services below.
- **`GlobalPushToTalkHotkeyMonitor`** — a listen-only `CGEvent` tap detecting Control+Option.
- **`PushToTalkRecorder`** — records 16 kHz mono WAV via `AVAudioRecorder`.
- **`ScreenCaptureService`** — ScreenCaptureKit screenshots of every display, labeled with screen
  number, pixel dimensions, and which display holds the cursor ("primary focus").
- **`SpeechPlaybackService`** — plays the returned MP3 via `AVAudioPlayer`.
- **`CursorOverlayController` / `CursorOverlayView`** — a full-screen, transparent, non-activating
  `NSPanel` hosting the animated cursor and response bubble; never steals focus, joins all Spaces.
- **`MenuBarController` / `CompanionPanelView`** — the `NSStatusItem` and floating control panel
  (status, model picker, permission shortcuts, quit).
- **`AppConfiguration`** — assembles `BuddyConfiguration` from Info.plist + UserDefaults.

### 2.3 worker (Cloudflare Worker proxy, TypeScript)

A ~190-line Worker exposing `/chat`, `/transcribe`, `/tts`, and `/health`. It:

- runs models on its bound `AI` binding (no token in the data path);
- requires a shared `BUDDY_PROXY_SECRET` bearer token (constant-time compared);
- enforces a **model allowlist** — off-list models are coerced to the default, so the proxy can
  never reach a non-Cloudflare model;
- streams `/chat` as `text/event-stream`, unwraps Whisper output to `{ text }`, and decodes the
  MeloTTS base64 to raw `audio/mpeg` bytes.

## 3. End-to-end data flow

```
Ctrl+Option down ─▶ CompanionController.listening ─▶ PushToTalkRecorder.start
Ctrl+Option up   ─▶ processing
   ─▶ WorkersAIClient.transcribeSpeech ─▶ POST /transcribe ─▶ Whisper ─▶ transcript
   ─▶ ScreenCaptureService.captureAllScreens ─▶ [LabeledScreenImage] + geometries
   ─▶ responding
   ─▶ WorkersAIClient.streamCompanionResponse ─▶ POST /chat (SSE) ─▶ Kimi ─▶ streamed text
   ─▶ PointTagParser.parse ─▶ (spokenText, coordinate?, screenN?, label?)
   ─▶ WorkersAIClient.synthesizeSpeech ─▶ POST /tts ─▶ MeloTTS ─▶ mp3 ─▶ SpeechPlaybackService
   ─▶ if coordinate: ScreenCoordinateMapper ─▶ CursorOverlayController.pointCursor
   ─▶ ConversationHistoryStore.record ─▶ idle (overlay fades out)
```

## 4. Coordinate mapping

Screenshots have a top-left origin and are in pixels; AppKit's global space has a bottom-left
origin and is in points. For a pixel `(px, py)` on a display with screenshot size `Sw×Sh`, point
size `Pw×Ph`, and frame origin `(Ox, Oy)`:

```
clamp px∈[0,Sw], py∈[0,Sh]
localX      = px * (Pw / Sw)
localYTop   = py * (Ph / Sh)
localYBottom= Ph - localYTop          # flip Y
globalX     = localX + Ox
globalY     = localYBottom + Oy
```

This logic lives in `ScreenCoordinateMapper` and is exhaustively unit tested (scaling, clamping,
Y-flip, multi-display origins).

## 5. Security model

- The Cloudflare token never leaves Cloudflare: the Worker uses the `AI` binding, not a token.
- The app authenticates to the Worker with a shared bearer secret; the Worker compares it in
  constant time and rejects mismatches with `401`.
- The Worker's model allowlist makes it impossible to proxy a non-Workers-AI model.
- `.gitignore` excludes `.dev.vars`, `.env`, and `*.env`; no secret is committed.
- Entitlements request only what is needed: audio input and network client (the app is unsandboxed
  because Screen Recording + a global event tap require it).

## 6. Testing

- **BuddyKit**: 29 XCTest cases covering the POINT parser, coordinate mapper, stream decoder,
  request builders, the Workers AI client (via mock transport), and OpenCode config generation.
- **worker**: 17 vitest cases covering auth, the model allowlist, routing, streaming `/chat`,
  Whisper unwrapping, MeloTTS decoding, and error paths, plus `tsc --noEmit`.

## 7. Why these choices

- **Worker proxy over embedded token**: keeps the distributed binary credential-free and lets the
  allowlist enforce the Workers-AI-only constraint server-side.
- **BuddyKit split**: makes the hard logic (parsing, coordinate math, request shaping) testable on
  CI without a Mac, which is where most regressions would otherwise hide.
- **CGEvent tap for push-to-talk**: modifier-only chords are detected far more reliably in the
  background than with an AppKit global monitor.
- **XcodeGen project.yml**: the `.xcodeproj` is generated, never committed, so it cannot drift.
