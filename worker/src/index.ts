/**
 * Buddy Worker — a thin, secure Cloudflare Worker proxy in front of Cloudflare Workers AI.
 *
 * The macOS app never holds a Cloudflare API token. Instead it talks to this Worker, which
 * runs the model on the account's bound `AI` binding (no token in the data path at all) and
 * is locked down with a shared bearer secret + an allowlist of Workers AI models.
 *
 * Routes (all POST):
 *   /chat       OpenAI-compatible streaming chat/vision completions (Kimi by default).
 *   /transcribe Speech-to-text via Whisper. Body: { audio: base64, language? }.
 *   /tts        Text-to-speech via MeloTTS. Body: { prompt, lang? } -> audio/mpeg.
 *   /health     Liveness probe (no auth).
 */

export interface Env {
  /** Cloudflare Workers AI binding (configured in wrangler.toml). */
  AI: {
    run: (model: string, inputs: Record<string, unknown>, options?: Record<string, unknown>) => Promise<unknown>;
  };
  /** Shared secret the macOS app must present as `Authorization: Bearer <secret>`. */
  BUDDY_PROXY_SECRET?: string;
  /** Default chat model identifier, overridable per request from the allowlist. */
  DEFAULT_CHAT_MODEL?: string;
}

/** The only Workers AI models this proxy is permitted to invoke. */
export const ALLOWED_CHAT_MODELS = [
  "@cf/moonshotai/kimi-k2.7-code",
  "@cf/moonshotai/kimi-k2.6",
  "@cf/meta/llama-4-scout-17b-16e-instruct",
] as const;

export const WHISPER_MODEL = "@cf/openai/whisper-large-v3-turbo";
export const MELOTTS_MODEL = "@cf/myshell-ai/melotts";
export const DEFAULT_CHAT_MODEL = "@cf/moonshotai/kimi-k2.7-code";

const JSON_HEADERS = { "Content-Type": "application/json" } as const;

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), { status, headers: JSON_HEADERS });
}

/** Validates the shared bearer secret. When no secret is configured, auth is skipped. */
export function isAuthorized(request: Request, env: Env): boolean {
  if (!env.BUDDY_PROXY_SECRET) {
    return true;
  }
  const authorizationHeader = request.headers.get("Authorization") ?? "";
  const expected = `Bearer ${env.BUDDY_PROXY_SECRET}`;
  // Length check first so the comparison below only runs on equal-length inputs.
  if (authorizationHeader.length !== expected.length) {
    return false;
  }
  return timingSafeEqual(authorizationHeader, expected);
}

/** Constant-time string comparison to avoid leaking the secret via timing. */
export function timingSafeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) {
    return false;
  }
  let mismatch = 0;
  for (let index = 0; index < left.length; index += 1) {
    mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return mismatch === 0;
}

/** Picks the chat model from the request body, falling back to the default. Rejects models
 *  that are not on the allowlist so the proxy can only ever drive Workers AI Kimi models. */
export function resolveChatModel(requestedModel: unknown, env: Env): string {
  const fallback = env.DEFAULT_CHAT_MODEL ?? DEFAULT_CHAT_MODEL;
  if (typeof requestedModel !== "string" || requestedModel.length === 0) {
    return fallback;
  }
  return (ALLOWED_CHAT_MODELS as readonly string[]).includes(requestedModel) ? requestedModel : fallback;
}

async function handleChat(request: Request, env: Env): Promise<Response> {
  const requestBody = (await request.json()) as Record<string, unknown>;
  const model = resolveChatModel(requestBody.model, env);
  const stream = requestBody.stream !== false;

  const inputs: Record<string, unknown> = {
    messages: requestBody.messages,
    max_tokens: requestBody.max_tokens ?? 1024,
    stream,
  };

  const result = await env.AI.run(model, inputs);

  // When streaming, the binding returns a ReadableStream of OpenAI-compatible SSE bytes.
  if (stream && result instanceof ReadableStream) {
    return new Response(result, {
      headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
    });
  }
  return new Response(JSON.stringify(result), { headers: JSON_HEADERS });
}

async function handleTranscribe(request: Request, env: Env): Promise<Response> {
  const requestBody = (await request.json()) as Record<string, unknown>;
  if (typeof requestBody.audio !== "string" || requestBody.audio.length === 0) {
    return jsonError("missing base64 'audio' field", 400);
  }

  const inputs: Record<string, unknown> = { audio: requestBody.audio };
  if (typeof requestBody.language === "string") {
    inputs.language = requestBody.language;
  }

  const result = (await env.AI.run(WHISPER_MODEL, inputs)) as { text?: string };
  // Unwrap to a clean { text } shape so the app does not need to handle Cloudflare envelopes.
  return new Response(JSON.stringify({ text: result?.text ?? "" }), { headers: JSON_HEADERS });
}

async function handleTextToSpeech(request: Request, env: Env): Promise<Response> {
  const requestBody = (await request.json()) as Record<string, unknown>;
  if (typeof requestBody.prompt !== "string" || requestBody.prompt.length === 0) {
    return jsonError("missing 'prompt' text field", 400);
  }

  const inputs: Record<string, unknown> = {
    prompt: requestBody.prompt,
    lang: typeof requestBody.lang === "string" ? requestBody.lang : "en",
  };

  const result = (await env.AI.run(MELOTTS_MODEL, inputs)) as { audio?: string };
  if (!result?.audio) {
    return jsonError("speech synthesis returned no audio", 502);
  }

  // MeloTTS returns base64-encoded MP3; decode and stream raw audio bytes to the app.
  const audioBytes = base64ToBytes(result.audio);
  return new Response(audioBytes, { headers: { "Content-Type": "audio/mpeg" } });
}

export function base64ToBytes(base64: string): Uint8Array {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let index = 0; index < binaryString.length; index += 1) {
    bytes[index] = binaryString.charCodeAt(index);
  }
  return bytes;
}

export async function handleRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "GET" && url.pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok" }), { headers: JSON_HEADERS });
  }

  if (request.method !== "POST") {
    return jsonError("method not allowed", 405);
  }

  if (!isAuthorized(request, env)) {
    return jsonError("unauthorized", 401);
  }

  try {
    switch (url.pathname) {
      case "/chat":
        return await handleChat(request, env);
      case "/transcribe":
        return await handleTranscribe(request, env);
      case "/tts":
        return await handleTextToSpeech(request, env);
      default:
        return jsonError("not found", 404);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "internal error";
    return jsonError(message, 500);
  }
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  },
};
