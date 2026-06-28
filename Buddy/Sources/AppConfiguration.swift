import Foundation
import BuddyKit

/// Reads Buddy's runtime configuration from the app bundle and user defaults, and builds the
/// `BuddyConfiguration` the rest of the app uses to talk to Cloudflare Workers AI.
///
/// The proxy URL ships in `Info.plist` (`BuddyProxyURL`) but can be overridden at runtime
/// with the `BuddyProxyURL` user default, which is handy for pointing a dev build at a local
/// `wrangler dev` instance. The selected model persists across launches.
///
/// When the Worker proxy is locked with a shared `BUDDY_PROXY_SECRET`, the matching bearer
/// token is read from the `BuddyProxySecret` user default (set it with
/// `defaults write com.ishaangupta.buddy BuddyProxySecret "<secret>"`) so the secret never
/// has to be committed into the app bundle.
enum AppConfiguration {
    private static let proxyURLInfoPlistKey = "BuddyProxyURL"
    private static let proxyURLUserDefaultsKey = "BuddyProxyURL"
    private static let proxySecretUserDefaultsKey = "BuddyProxySecret"
    private static let selectedModelUserDefaultsKey = "BuddySelectedModelIdentifier"

    /// The Worker proxy base URL, preferring a user-default override over the bundled value.
    static func workerProxyBaseURL() -> URL {
        if let overrideURLString = UserDefaults.standard.string(forKey: proxyURLUserDefaultsKey),
           let overrideURL = URL(string: overrideURLString) {
            return overrideURL
        }
        if let bundledURLString = Bundle.main.object(forInfoDictionaryKey: proxyURLInfoPlistKey) as? String,
           let bundledURL = URL(string: bundledURLString) {
            return bundledURL
        }
        // A clearly-invalid placeholder so a misconfigured build fails loudly rather than silently.
        return URL(string: "https://buddy-proxy.invalid")!
    }

    /// The shared bearer secret the app sends to a locked Worker proxy, or `nil` when the
    /// proxy is unauthenticated. Read from the `BuddyProxySecret` user default; an empty
    /// value is treated as no secret.
    static func workerProxySecret() -> String? {
        guard let secret = UserDefaults.standard.string(forKey: proxySecretUserDefaultsKey),
              !secret.isEmpty else {
            return nil
        }
        return secret
    }

    /// The model the user last selected, defaulting to Kimi K2.7 Code.
    static func selectedChatModel() -> WorkersAIChatModel {
        guard let storedIdentifier = UserDefaults.standard.string(forKey: selectedModelUserDefaultsKey) else {
            return WorkersAIModelCatalog.defaultModel
        }
        return WorkersAIModelCatalog.model(forIdentifier: storedIdentifier)
    }

    /// Persists the user's model selection.
    static func saveSelectedChatModel(_ chatModel: WorkersAIChatModel) {
        UserDefaults.standard.set(chatModel.modelIdentifier, forKey: selectedModelUserDefaultsKey)
    }

    /// Assembles the full configuration used to construct the Workers AI client.
    static func makeBuddyConfiguration() -> BuddyConfiguration {
        BuddyConfiguration(
            endpointMode: .workerProxy(baseURL: workerProxyBaseURL(), proxySecret: workerProxySecret()),
            chatModel: selectedChatModel()
        )
    }
}
