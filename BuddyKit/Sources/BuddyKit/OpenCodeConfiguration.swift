import Foundation

/// Generates the `opencode.json` configuration that wires the OpenCode coding agent to run
/// exclusively on Cloudflare Workers AI models.
///
/// OpenCode already ships the `cloudflare-workers-ai` provider via models.dev (it uses the
/// `@ai-sdk/openai-compatible` adapter against Cloudflare's OpenAI-compatible endpoint and
/// reads `CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_API_KEY` from the environment). Buddy emits an
/// explicit configuration so the provider, base URL, and the exact Kimi model whitelist are
/// pinned regardless of catalog drift — keeping Buddy locked to Workers AI only.
public enum OpenCodeConfiguration {
    public static let providerIdentifier = "cloudflare-workers-ai"
    public static let providerDisplayName = "Cloudflare Workers AI"
    public static let openAICompatibleNPMPackage = "@ai-sdk/openai-compatible"
    public static let configSchemaURL = "https://opencode.ai/config.json"

    /// The OpenAI-compatible base URL OpenCode points at for a given Cloudflare account.
    public static func openAICompatibleBaseURL(forAccount accountIdentifier: String) -> String {
        "https://api.cloudflare.com/client/v4/accounts/\(accountIdentifier)/ai/v1"
    }

    /// The fully-qualified `provider/model` string OpenCode uses to select a model.
    public static func qualifiedModelIdentifier(for chatModel: WorkersAIChatModel) -> String {
        "\(providerIdentifier)/\(chatModel.modelIdentifier)"
    }

    /// Builds the `opencode.json` object graph for the given account and model selection.
    public static func makeConfigurationObject(
        accountIdentifier: String,
        defaultModel: WorkersAIChatModel = WorkersAIModelCatalog.defaultModel,
        availableModels: [WorkersAIChatModel] = [
            WorkersAIModelCatalog.kimiK27Code,
            WorkersAIModelCatalog.kimiK26
        ]
    ) -> [String: Any] {
        var modelEntries: [String: Any] = [:]
        for chatModel in availableModels {
            modelEntries[chatModel.modelIdentifier] = ["name": chatModel.displayName]
        }

        let providerEntry: [String: Any] = [
            "npm": openAICompatibleNPMPackage,
            "name": providerDisplayName,
            "options": [
                "baseURL": openAICompatibleBaseURL(forAccount: accountIdentifier),
                // OpenCode reads the Workers AI scoped token from the environment at runtime.
                "apiKey": "${CLOUDFLARE_API_KEY}"
            ],
            "models": modelEntries
        ]

        return [
            "$schema": configSchemaURL,
            "model": qualifiedModelIdentifier(for: defaultModel),
            "provider": [providerIdentifier: providerEntry]
        ]
    }

    /// Renders the configuration as pretty-printed, deterministic JSON suitable for writing
    /// to `opencode.json`.
    public static func makeConfigurationJSON(
        accountIdentifier: String,
        defaultModel: WorkersAIChatModel = WorkersAIModelCatalog.defaultModel,
        availableModels: [WorkersAIChatModel] = [
            WorkersAIModelCatalog.kimiK27Code,
            WorkersAIModelCatalog.kimiK26
        ]
    ) throws -> String {
        let configurationObject = makeConfigurationObject(
            accountIdentifier: accountIdentifier,
            defaultModel: defaultModel,
            availableModels: availableModels
        )
        let jsonData = try JSONSerialization.data(
            withJSONObject: configurationObject,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: jsonData, as: UTF8.self)
    }
}
