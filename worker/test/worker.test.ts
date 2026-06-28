import { describe, it, expect } from "vitest";
import {
  handleRequest,
  isAuthorized,
  timingSafeEqual,
  resolveChatModel,
  base64ToBytes,
  DEFAULT_CHAT_MODEL,
  type Env,
} from "../src/index";

/** Builds a fake `Env` whose `AI.run` returns a scripted value and records its call. */
function makeEnv(options: {
  secret?: string;
  defaultModel?: string;
  aiRun?: (model: string, inputs: Record<string, unknown>) => unknown;
  calls?: Array<{ model: string; inputs: Record<string, unknown> }>;
}): Env {
  return {
    AI: {
      run: async (model: string, inputs: Record<string, unknown>) => {
        options.calls?.push({ model, inputs });
        return options.aiRun ? options.aiRun(model, inputs) : {};
      },
    },
    BUDDY_PROXY_SECRET: options.secret,
    DEFAULT_CHAT_MODEL: options.defaultModel,
  };
}

function postRequest(path: string, body: unknown, headers: Record<string, string> = {}): Request {
  return new Request(`https://buddy.example.workers.dev${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

describe("authorization", () => {
  it("allows requests when no secret is configured", () => {
    expect(isAuthorized(postRequest("/chat", {}), makeEnv({}))).toBe(true);
  });

  it("rejects requests with a missing or wrong bearer secret", () => {
    const env = makeEnv({ secret: "topsecret" });
    expect(isAuthorized(postRequest("/chat", {}), env)).toBe(false);
    expect(isAuthorized(postRequest("/chat", {}, { Authorization: "Bearer wrong" }), env)).toBe(false);
  });

  it("accepts the correct bearer secret", () => {
    const env = makeEnv({ secret: "topsecret" });
    expect(isAuthorized(postRequest("/chat", {}, { Authorization: "Bearer topsecret" }), env)).toBe(true);
  });

  it("timingSafeEqual compares correctly", () => {
    expect(timingSafeEqual("abc", "abc")).toBe(true);
    expect(timingSafeEqual("abc", "abd")).toBe(false);
    expect(timingSafeEqual("abc", "abcd")).toBe(false);
  });
});

describe("model allowlist", () => {
  const env = makeEnv({});
  it("falls back to default for unknown or missing models", () => {
    expect(resolveChatModel(undefined, env)).toBe(DEFAULT_CHAT_MODEL);
    expect(resolveChatModel("@cf/some/unapproved-model", env)).toBe(DEFAULT_CHAT_MODEL);
  });
  it("passes through allowed Kimi models", () => {
    expect(resolveChatModel("@cf/moonshotai/kimi-k2.6", env)).toBe("@cf/moonshotai/kimi-k2.6");
  });
});

describe("routing and behavior", () => {
  it("health check responds without auth", async () => {
    const response = await handleRequest(
      new Request("https://buddy.example.workers.dev/health"),
      makeEnv({ secret: "s" })
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });

  it("returns 401 on a protected route without the secret", async () => {
    const response = await handleRequest(postRequest("/chat", {}), makeEnv({ secret: "s" }));
    expect(response.status).toBe(401);
  });

  it("chat forwards messages to the resolved model and streams SSE", async () => {
    const calls: Array<{ model: string; inputs: Record<string, unknown> }> = [];
    const sseStream = new ReadableStream();
    const env = makeEnv({ calls, aiRun: () => sseStream });
    const response = await handleRequest(
      postRequest("/chat", { model: "@cf/moonshotai/kimi-k2.6", messages: [{ role: "user", content: "hi" }] }),
      env
    );
    expect(response.headers.get("Content-Type")).toBe("text/event-stream");
    expect(calls[0].model).toBe("@cf/moonshotai/kimi-k2.6");
    expect(calls[0].inputs.stream).toBe(true);
  });

  it("chat coerces an unapproved model down to the default", async () => {
    const calls: Array<{ model: string; inputs: Record<string, unknown> }> = [];
    const env = makeEnv({ calls, aiRun: () => ({ choices: [] }) });
    await handleRequest(postRequest("/chat", { model: "@cf/evil/model", messages: [], stream: false }), env);
    expect(calls[0].model).toBe(DEFAULT_CHAT_MODEL);
  });

  it("transcribe unwraps Whisper output to { text }", async () => {
    const env = makeEnv({ aiRun: () => ({ text: "hello world", word_count: 2 }) });
    const response = await handleRequest(postRequest("/transcribe", { audio: "AAAA", language: "en" }), env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ text: "hello world" });
  });

  it("transcribe rejects a missing audio field", async () => {
    const response = await handleRequest(postRequest("/transcribe", {}), makeEnv({}));
    expect(response.status).toBe(400);
  });

  it("tts returns decoded mp3 audio bytes", async () => {
    const originalBytes = new Uint8Array([0x49, 0x44, 0x33, 0x04]);
    const base64Audio = btoa(String.fromCharCode(...originalBytes));
    const env = makeEnv({ aiRun: () => ({ audio: base64Audio }) });
    const response = await handleRequest(postRequest("/tts", { prompt: "hello" }), env);
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe("audio/mpeg");
    const returnedBytes = new Uint8Array(await response.arrayBuffer());
    expect(Array.from(returnedBytes)).toEqual(Array.from(originalBytes));
  });

  it("tts rejects a missing prompt", async () => {
    const response = await handleRequest(postRequest("/tts", {}), makeEnv({}));
    expect(response.status).toBe(400);
  });

  it("unknown route returns 404", async () => {
    const response = await handleRequest(postRequest("/nope", {}), makeEnv({}));
    expect(response.status).toBe(404);
  });

  it("non-POST on a route returns 405", async () => {
    const response = await handleRequest(
      new Request("https://buddy.example.workers.dev/chat", { method: "PUT" }),
      makeEnv({})
    );
    expect(response.status).toBe(405);
  });
});

describe("base64ToBytes", () => {
  it("round-trips bytes", () => {
    const bytes = new Uint8Array([1, 2, 3, 250, 0, 128]);
    const base64 = btoa(String.fromCharCode(...bytes));
    expect(Array.from(base64ToBytes(base64))).toEqual(Array.from(bytes));
  });
});
