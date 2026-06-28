# Phase 1 — BuddyKit core (platform-independent logic)

## Constraints

- No AppKit / SwiftUI / Foundation-GUI dependency — must build and test headless.
- Cloudflare Workers AI is the only backend; model identifiers are pinned in code.
- All network access goes through an injectable `HTTPTransport` so logic is testable offline.

## Logic delivered

- `WorkersAIClient` — chat (SSE streaming), speech-to-text, text-to-speech.
- `ChatCompletionRequestBuilder` — OpenAI-compatible body: system prompt + history + transcript +
  one base64 data-URI image part per screenshot.
- `ChatStreamDecoder` — turns SSE `data:` lines into accumulated text; detects `[DONE]`.
- `PointTagParser` — extracts a trailing `[POINT:x,y:label:screenN]` tag.
- `ScreenCoordinateMapper` — screenshot pixel → global AppKit point (clamp, scale, flip, translate).
- `ConversationHistoryStore` — bounded FIFO of exchanges.
- `WorkersAIModelCatalog`, `SystemPrompts`, `OpenCodeConfiguration`, `WorkersAIResponseDecoders`.

## Key variables

| Name | Value |
|------|-------|
| Default chat model | `@cf/moonshotai/kimi-k2.7-code` |
| Alternate chat model | `@cf/moonshotai/kimi-k2.6` |
| STT model | `@cf/openai/whisper-large-v3-turbo` |
| TTS model | `@cf/myshell-ai/melotts` |
| Default context window | 262,144 tokens |
| Default max response tokens | 1024 |
| Default conversation history limit | 10 exchanges |

## Tests

`swift test` — 29 cases (parser, mapper, decoder, client via `MockHTTPTransport`, OpenCode config).

## Commit

`Phase 1: BuddyKit core — Cloudflare Workers AI client, OpenCode integration, POINT parser, coordinate mapper`
