# Phase 4 — OpenCode integration

## Constraints

- OpenCode must run on Cloudflare Workers AI Kimi models only.
- The configuration must be deterministic and reproducible from BuddyKit.

## Logic delivered

- `BuddyKit/Sources/BuddyKit/OpenCodeConfiguration.swift` renders `opencode.json` for a given
  Cloudflare account id and model selection, pinning:
  - provider `cloudflare-workers-ai` via the `@ai-sdk/openai-compatible` npm adapter,
  - `baseURL = https://api.cloudflare.com/client/v4/accounts/{id}/ai/v1`,
  - the Kimi model whitelist and the default model.
- `OpenCodeClient` (in BuddyKit) can drive a local OpenCode server (`createSession`, `sendPrompt`,
  `fetchCompanionResponse`) for an agentic coding flow over the same backend.
- A ready-to-use `opencode.json` is committed at the repo root, parameterized by
  `${CLOUDFLARE_ACCOUNT_ID}` / `${CLOUDFLARE_API_KEY}` environment variables.

## Key variables

| Name | Value |
|------|-------|
| Provider id | `cloudflare-workers-ai` |
| Adapter | `@ai-sdk/openai-compatible` |
| Default model | `cloudflare-workers-ai/@cf/moonshotai/kimi-k2.7-code` |
| Env vars | `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_KEY` |

## Usage

```bash
export CLOUDFLARE_ACCOUNT_ID=... CLOUDFLARE_API_KEY=...
opencode
```

## Tests

OpenCode config generation and client request shaping are covered by BuddyKit's `OpenCodeTests`.

## Commit

Included with Phase 1 (BuddyKit) and finalized alongside the documentation commit.
