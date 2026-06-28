import Foundation

/// A single Cloudflare Workers AI text-generation model that Buddy can talk to.
///
/// Buddy is intentionally locked to the Cloudflare Workers AI catalog — no other
/// inference provider is ever used. Every model identifier in this file is the exact
/// string Cloudflare expects in both the OpenAI-compatible endpoint
/// (`/accounts/{id}/ai/v1/chat/completions`) and the raw run endpoint
/// (`/accounts/{id}/ai/run/{model}`).
public struct WorkersAIChatModel: Equatable, Hashable, Sendable {
    /// The Cloudflare model identifier, e.g. `@cf/moonshotai/kimi-k2.7-code`.
    public let modelIdentifier: String

    /// A short human-friendly name shown in the menu bar model picker.
    public let displayName: String

    /// Whether the model accepts image input. Buddy sends a screenshot with every
    /// companion turn, so only vision-capable models are valid companion models.
    public let supportsVisionInput: Bool

    /// Whether the model supports tool/function calling. Required for the OpenCode
    /// agentic coding workflow.
    public let supportsToolCalling: Bool

    /// The maximum context window in tokens, used for documentation and guardrails.
    public let contextWindowInTokens: Int

    public init(
        modelIdentifier: String,
        displayName: String,
        supportsVisionInput: Bool,
        supportsToolCalling: Bool,
        contextWindowInTokens: Int
    ) {
        self.modelIdentifier = modelIdentifier
        self.displayName = displayName
        self.supportsVisionInput = supportsVisionInput
        self.supportsToolCalling = supportsToolCalling
        self.contextWindowInTokens = contextWindowInTokens
    }
}

/// The catalog of Cloudflare Workers AI models Buddy ships with.
///
/// The two Kimi models are the primary models: they are the only catalog entries that
/// support both vision input (needed for the screen-aware companion) and tool calling
/// (needed for the OpenCode coding agent). The remaining vision model is kept as an
/// explicit fallback for accounts that do not yet have Kimi access.
public enum WorkersAIModelCatalog {
    /// Kimi K2.7 Code — the default model. Vision + tool calling, 262k context.
    public static let kimiK27Code = WorkersAIChatModel(
        modelIdentifier: "@cf/moonshotai/kimi-k2.7-code",
        displayName: "Kimi K2.7 Code",
        supportsVisionInput: true,
        supportsToolCalling: true,
        contextWindowInTokens: 262_144
    )

    /// Kimi K2.6 — vision + tool calling, 262k context.
    public static let kimiK26 = WorkersAIChatModel(
        modelIdentifier: "@cf/moonshotai/kimi-k2.6",
        displayName: "Kimi K2.6",
        supportsVisionInput: true,
        supportsToolCalling: true,
        contextWindowInTokens: 262_144
    )

    /// Llama 4 Scout — vision + tool calling fallback for accounts without Kimi access.
    public static let llama4Scout = WorkersAIChatModel(
        modelIdentifier: "@cf/meta/llama-4-scout-17b-16e-instruct",
        displayName: "Llama 4 Scout",
        supportsVisionInput: true,
        supportsToolCalling: true,
        contextWindowInTokens: 131_072
    )

    /// The model Buddy uses when the user has not chosen one explicitly.
    public static let defaultModel = kimiK27Code

    /// Every model Buddy is allowed to use, in menu-picker order.
    public static let allModels: [WorkersAIChatModel] = [
        kimiK27Code,
        kimiK26,
        llama4Scout
    ]

    /// Only the models valid for the screen-aware companion (must accept image input).
    public static let visionCapableModels: [WorkersAIChatModel] = allModels.filter { model in
        model.supportsVisionInput
    }

    /// Looks up a model by its Cloudflare identifier, returning the default if unknown.
    public static func model(forIdentifier modelIdentifier: String) -> WorkersAIChatModel {
        allModels.first(where: { candidateModel in
            candidateModel.modelIdentifier == modelIdentifier
        }) ?? defaultModel
    }
}

/// The Cloudflare Workers AI speech models Buddy uses for the voice pipeline.
/// These run through the raw `/ai/run/{model}` endpoint rather than the
/// OpenAI-compatible chat endpoint.
public enum WorkersAISpeechModel {
    /// Speech-to-text. `@cf/openai/whisper-large-v3-turbo` accepts base64 audio and
    /// returns a transcription.
    public static let speechToTextModelIdentifier = "@cf/openai/whisper-large-v3-turbo"

    /// Text-to-speech. `@cf/myshell-ai/melotts` accepts a text prompt and returns
    /// base64-encoded MP3 audio.
    public static let textToSpeechModelIdentifier = "@cf/myshell-ai/melotts"
}
