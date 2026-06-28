# Phase 2 — Cloudflare Worker proxy

## Constraints

- The Cloudflare API token must never enter the data path — use the bound `AI` binding.
- The app must authenticate with a shared secret; reject everything else.
- The proxy must be impossible to use for a non-Workers-AI model.

## Logic delivered

`worker/src/index.ts` exposes four routes:

| Route | Method | Behavior |
|-------|--------|----------|
| `/health` | GET | Unauthenticated `{ status: "ok" }`. |
| `/chat` | POST | Resolves model from allowlist, calls `AI.run`, streams SSE (`text/event-stream`). |
| `/transcribe` | POST | Validates base64 `audio`, calls Whisper, unwraps to `{ text }`. |
| `/tts` | POST | Validates `prompt`, calls MeloTTS, decodes base64 → `audio/mpeg` bytes. |

- `isAuthorized` / `timingSafeEqual` — constant-time bearer-secret check (`401` on mismatch).
- `resolveChatModel` — coerces any off-allowlist model to the default.
- `ALLOWED_CHAT_MODELS` — `kimi-k2.7-code`, `kimi-k2.6`, `llama-4-scout` (vision fallback).

## Key variables

| Name | Value |
|------|-------|
| Secret (wrangler) | `BUDDY_PROXY_SECRET` |
| Var (wrangler) | `DEFAULT_CHAT_MODEL = @cf/moonshotai/kimi-k2.7-code` |
| Binding | `AI` (Workers AI) |
| Default max tokens | 1024 |

## Tests

`npm test` — 17 vitest cases (auth, allowlist, routing, streaming, Whisper unwrap, MeloTTS decode,
error paths). `npm run typecheck` — `tsc --noEmit` passes.

## Commit

`Phase 2: Cloudflare Worker proxy — secure /chat, /transcribe, /tts routes over Workers AI binding + vitest suite`
