# Buddy

Buddy is a fast, native macOS voice companion that lives in your menu bar. Hold a push-to-talk
shortcut, ask a question out loud, and Buddy sees your screen, thinks, answers you in a spoken
voice, and can fly a glowing cursor to point at whatever it is talking about — on any connected
display.

Every model call runs on **Cloudflare Workers AI**, and only Cloudflare Workers AI:

| Stage | Model | Cloudflare Workers AI ID |
|-------|-------|--------------------------|
| Speech-to-text | Whisper Large v3 Turbo | `@cf/openai/whisper-large-v3-turbo` |
| Chat + vision  | Kimi K2.7 Code (default) / Kimi K2.6 | `@cf/moonshotai/kimi-k2.7-code`, `@cf/moonshotai/kimi-k2.6` |
| Text-to-speech | MeloTTS | `@cf/myshell-ai/melotts` |

No other AI provider is used anywhere in the codebase. The app ships **no credentials** — all
model calls go through a small Cloudflare Worker proxy that runs the models on the account's
bound `AI` binding, so the Cloudflare token never leaves Cloudflare's edge.

Buddy also ships an [`opencode.json`](./opencode.json) that pins the
[OpenCode](https://opencode.ai) coding agent to the same Cloudflare Workers AI Kimi models, so
you can drive an agentic coding workflow on the exact same backend.

## Architecture at a glance

```
                 hold Ctrl+Option, speak, release
                              │
            ┌─────────────────▼──────────────────┐
            │            Buddy.app (macOS)        │
            │  GlobalPushToTalkHotkeyMonitor      │
            │  PushToTalkRecorder (AVAudioEngine) │
            │  ScreenCaptureService (SCKit)       │
            │  CursorOverlayController (NSPanel)  │
            │  CompanionController (state machine)│
            └─────────────────┬──────────────────┘
                              │ uses
            ┌─────────────────▼──────────────────┐
            │   BuddyKit (pure Swift package)     │
            │  WorkersAIClient · PointTagParser   │
            │  ScreenCoordinateMapper · prompts   │
            │  OpenCode config · conversation log │
            └─────────────────┬──────────────────┘
                  HTTPS (no credentials in app)
            ┌─────────────────▼──────────────────┐
            │   Buddy Worker (Cloudflare)         │
            │  /chat  /transcribe  /tts  /health  │
            │  bound AI binding · bearer secret   │
            └─────────────────┬──────────────────┘
                              │
                  Cloudflare Workers AI (Whisper · Kimi · MeloTTS)
```

The repository has three independently-testable layers:

- **`BuddyKit/`** — a platform-independent Swift package containing *all* business logic: the
  Workers AI client, response decoders, the `[POINT:x,y:label:screenN]` parser, the
  screenshot-pixel → display-point coordinate mapper, the system prompt, conversation history,
  and the OpenCode configuration builder. It has no AppKit dependency and is unit tested with a
  mock transport (29 tests).
- **`Buddy/`** — the native macOS app (SwiftUI + AppKit) that owns the menu bar item, the
  push-to-talk capture, multi-monitor screenshots, audio playback, and the cursor overlay. It
  delegates every decision to BuddyKit.
- **`worker/`** — the Cloudflare Worker proxy (TypeScript) with `/chat`, `/transcribe`, `/tts`,
  and `/health` routes, locked to an allowlist of Workers AI models and a shared bearer secret.
  Unit tested with vitest (17 tests).

See [`docs/architecture.md`](./docs/architecture.md) for the full report, and the phased build
log in [`docs/phase-1.md`](./docs/phase-1.md) … [`docs/phase-5.md`](./docs/phase-5.md).

## Requirements

- macOS 14.2 or later (ScreenCaptureKit screenshot API)
- Xcode 15.4+ and Swift 5.9+
- [XcodeGen](https://github.com/yonsei/XcodeGen) (`brew install xcodegen`) to generate the project
- Node.js 18+ for the Cloudflare Worker
- A Cloudflare account with Workers AI enabled

## Build and run the macOS app

```bash
# 1. Generate Buddy.xcodeproj from the committed project.yml
./scripts/bootstrap.sh        # or: xcodegen generate

# 2. Open it, set your signing team on the Buddy target, then Cmd+R
open Buddy.xcodeproj
```

On first launch Buddy asks for **Microphone**, **Screen Recording**, and **Accessibility**
permissions (the last is required for the global push-to-talk shortcut). The menu bar panel has
quick links to each System Settings pane.

Point the app at your deployed Worker by setting the proxy URL — either edit `BuddyProxyURL` in
`Buddy/Resources/Info.plist`, or override it at runtime without rebuilding:

```bash
defaults write com.ishaangupta.buddy BuddyProxyURL "https://buddy-proxy.<your-subdomain>.workers.dev"
```

## Deploy the Cloudflare Worker

```bash
cd worker
npm install

# Lock the proxy with a shared secret that the app must send as a bearer token.
npx wrangler secret put BUDDY_PROXY_SECRET

# Deploy. The AI binding in wrangler.toml gives the Worker access to Workers AI.
npx wrangler deploy

# Local development against a real account:
#   create worker/.dev.vars with BUDDY_PROXY_SECRET=...
npx wrangler dev
```

The Worker only ever invokes models on its allowlist (`@cf/moonshotai/kimi-k2.7-code`,
`@cf/moonshotai/kimi-k2.6`, plus a Llama vision fallback). Any other requested model is coerced
back to the default, so the proxy can never be used to reach a non-Cloudflare model.

## Use the OpenCode integration

```bash
export CLOUDFLARE_ACCOUNT_ID="<your account id>"
export CLOUDFLARE_API_KEY="<a Workers AI scoped token>"
opencode            # picks up opencode.json, runs on Kimi via Workers AI
```

## Testing

```bash
# BuddyKit (29 unit tests)
cd BuddyKit && swift test

# Worker (17 unit tests) + typecheck
cd worker && npm test && npm run typecheck
```

## Project layout

```
buddy/
├── BuddyKit/            Swift package: all platform-independent logic + tests
├── Buddy/               macOS app (SwiftUI + AppKit) source, Info.plist, entitlements, assets
├── worker/              Cloudflare Worker proxy (TypeScript) + vitest tests
├── docs/                architecture report + phased build documentation
├── opencode.json        OpenCode pinned to Cloudflare Workers AI Kimi models
├── project.yml          XcodeGen project definition (the .xcodeproj is generated, not committed)
├── agents.md            agent behavior + integration contract
└── claude.md            symlinked to agents.md (single source of truth)
```

## License

[MIT](./LICENSE) © Ishaan Gupta
