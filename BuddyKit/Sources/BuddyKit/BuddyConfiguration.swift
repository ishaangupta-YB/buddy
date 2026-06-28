import Foundation

/// How Buddy reaches Cloudflare Workers AI.
///
/// In production the macOS app talks to a small Cloudflare Worker proxy that holds the
/// Cloudflare API token as a secret, so no credentials ship inside the app binary. For
/// local development or tests it is sometimes convenient to talk to the Cloudflare REST
/// API directly with an account id + token; that path is supported too but should never
/// be used to ship credentials in a distributed build.
public enum WorkersAIEndpointMode: Equatable, Sendable {
    /// Talk to the Buddy Worker proxy at the given base URL (recommended for shipping).
    /// The proxy exposes `/chat`, `/transcribe`, and `/tts` routes. When the proxy is
    /// locked with a shared `BUDDY_PROXY_SECRET`, `proxySecret` is the matching bearer
    /// token the app must present; pass `nil` for an unauthenticated proxy.
    case workerProxy(baseURL: URL, proxySecret: String?)

    /// Talk directly to the Cloudflare REST API for the given account using a bearer token.
    /// Intended for development only — never embed a real token in a shipped app.
    case directCloudflare(accountIdentifier: String, apiToken: String)
}

/// Top-level configuration for the Buddy companion: which Workers AI endpoint to use,
/// which model to talk to, and the language settings for the voice pipeline.
public struct BuddyConfiguration: Equatable, Sendable {
    public var endpointMode: WorkersAIEndpointMode

    /// The Workers AI chat model used for companion responses. Must be vision-capable.
    public var chatModel: WorkersAIChatModel

    /// ISO 639-1 language hint passed to Whisper for transcription (e.g. "en").
    /// `nil` lets Whisper auto-detect the spoken language.
    public var speechToTextLanguageCode: String?

    /// Language code passed to MeloTTS for spoken responses (e.g. "en").
    public var textToSpeechLanguageCode: String

    /// The maximum number of tokens Buddy asks the chat model to generate per turn.
    public var maximumResponseTokens: Int

    /// How many prior user/assistant exchanges Buddy keeps as conversation context.
    public var conversationHistoryLimit: Int

    public init(
        endpointMode: WorkersAIEndpointMode,
        chatModel: WorkersAIChatModel = WorkersAIModelCatalog.defaultModel,
        speechToTextLanguageCode: String? = "en",
        textToSpeechLanguageCode: String = "en",
        maximumResponseTokens: Int = 1024,
        conversationHistoryLimit: Int = 10
    ) {
        self.endpointMode = endpointMode
        self.chatModel = chatModel
        self.speechToTextLanguageCode = speechToTextLanguageCode
        self.textToSpeechLanguageCode = textToSpeechLanguageCode
        self.maximumResponseTokens = maximumResponseTokens
        self.conversationHistoryLimit = conversationHistoryLimit
    }
}

/// Resolves the concrete URLs and authorization headers for each Workers AI route,
/// hiding the difference between the worker-proxy and direct-Cloudflare modes from the
/// rest of the client code.
public struct WorkersAIEndpointResolver: Sendable {
    public let endpointMode: WorkersAIEndpointMode

    public init(endpointMode: WorkersAIEndpointMode) {
        self.endpointMode = endpointMode
    }

    /// The URL for the OpenAI-compatible streaming chat-completions route.
    public func chatCompletionsURL() -> URL {
        switch endpointMode {
        case .workerProxy(let baseURL, _):
            return baseURL.appendingPathComponent("chat")
        case .directCloudflare(let accountIdentifier, _):
            return cloudflareBaseURL(forAccount: accountIdentifier)
                .appendingPathComponent("ai/v1/chat/completions")
        }
    }

    /// The URL for the speech-to-text (Whisper) route.
    public func speechToTextURL() -> URL {
        switch endpointMode {
        case .workerProxy(let baseURL, _):
            return baseURL.appendingPathComponent("transcribe")
        case .directCloudflare(let accountIdentifier, _):
            return cloudflareBaseURL(forAccount: accountIdentifier)
                .appendingPathComponent("ai/run/\(WorkersAISpeechModel.speechToTextModelIdentifier)")
        }
    }

    /// The URL for the text-to-speech (MeloTTS) route.
    public func textToSpeechURL() -> URL {
        switch endpointMode {
        case .workerProxy(let baseURL, _):
            return baseURL.appendingPathComponent("tts")
        case .directCloudflare(let accountIdentifier, _):
            return cloudflareBaseURL(forAccount: accountIdentifier)
                .appendingPathComponent("ai/run/\(WorkersAISpeechModel.textToSpeechModelIdentifier)")
        }
    }

    /// The bearer token to send. In proxy mode this is the shared `BUDDY_PROXY_SECRET`
    /// (the proxy injects the real Cloudflare credential server-side), or `nil` when the
    /// proxy is unauthenticated. In direct mode it is the Cloudflare API token.
    public func bearerToken() -> String? {
        switch endpointMode {
        case .workerProxy(_, let proxySecret):
            return proxySecret
        case .directCloudflare(_, let apiToken):
            return apiToken
        }
    }

    private func cloudflareBaseURL(forAccount accountIdentifier: String) -> URL {
        // The canonical Cloudflare REST base for Workers AI.
        return URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountIdentifier)")!
    }
}
