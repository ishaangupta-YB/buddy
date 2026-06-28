import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Errors raised while talking to a running OpenCode server.
public enum OpenCodeError: Error, Equatable {
    case malformedSessionResponse
    case malformedMessageResponse
    case httpError(statusCode: Int, body: String)
}

/// A minimal HTTP client for a locally running OpenCode server (`opencode serve`).
///
/// Buddy routes coding-agent requests to OpenCode so the agent's tools (file editing, shell,
/// search) run against the user's project, while the model behind it stays a Cloudflare
/// Workers AI model selected through `OpenCodeConfiguration`. This client creates a session
/// and sends a prompt, returning the assistant's text reply.
///
/// As with `WorkersAIClient`, all networking goes through the injected `HTTPTransport`, and
/// the request-construction and response-parsing logic is pure so it can be unit-tested.
public final class OpenCodeClient: Sendable {
    private let serverBaseURL: URL
    private let providerIdentifier: String
    private let modelIdentifier: String
    private let transport: HTTPTransport

    public init(
        serverBaseURL: URL,
        chatModel: WorkersAIChatModel = WorkersAIModelCatalog.defaultModel,
        providerIdentifier: String = OpenCodeConfiguration.providerIdentifier,
        transport: HTTPTransport
    ) {
        self.serverBaseURL = serverBaseURL
        self.providerIdentifier = providerIdentifier
        self.modelIdentifier = chatModel.modelIdentifier
        self.transport = transport
    }

    /// Creates a new OpenCode session and returns its identifier.
    public func createSession() async throws -> String {
        let request = makeCreateSessionRequest()
        let (responseData, metadata) = try await transport.performRequest(request)
        guard metadata.isSuccess else {
            throw OpenCodeError.httpError(
                statusCode: metadata.statusCode,
                body: String(data: responseData, encoding: .utf8) ?? ""
            )
        }
        return try Self.decodeSessionIdentifier(from: responseData)
    }

    /// Sends a prompt to an existing session and returns the assistant's combined text reply.
    public func sendPrompt(_ promptText: String, toSession sessionIdentifier: String) async throws -> String {
        let request = try makeSendMessageRequest(promptText: promptText, sessionIdentifier: sessionIdentifier)
        let (responseData, metadata) = try await transport.performRequest(request)
        guard metadata.isSuccess else {
            throw OpenCodeError.httpError(
                statusCode: metadata.statusCode,
                body: String(data: responseData, encoding: .utf8) ?? ""
            )
        }
        return try Self.decodeAssistantText(from: responseData)
    }

    // MARK: - Request Construction (pure, unit-tested)

    func makeCreateSessionRequest() -> URLRequest {
        var request = URLRequest(url: serverBaseURL.appendingPathComponent("session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func makeSendMessageRequest(promptText: String, sessionIdentifier: String) throws -> URLRequest {
        let messageURL = serverBaseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionIdentifier)
            .appendingPathComponent("message")

        let requestBody: [String: Any] = [
            "providerID": providerIdentifier,
            "modelID": modelIdentifier,
            "parts": [["type": "text", "text": promptText]]
        ]

        var request = URLRequest(url: messageURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [.sortedKeys])
        return request
    }

    // MARK: - Response Parsing (pure, unit-tested)

    static func decodeSessionIdentifier(from responseData: Data) throws -> String {
        guard
            let rootObject = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let sessionIdentifier = rootObject["id"] as? String
        else {
            throw OpenCodeError.malformedSessionResponse
        }
        return sessionIdentifier
    }

    /// Extracts and concatenates every text part from an OpenCode assistant message.
    static func decodeAssistantText(from responseData: Data) throws -> String {
        guard
            let rootObject = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else {
            throw OpenCodeError.malformedMessageResponse
        }

        // OpenCode returns either `{ parts: [...] }` or `{ info: ..., parts: [...] }`.
        guard let parts = rootObject["parts"] as? [[String: Any]] else {
            throw OpenCodeError.malformedMessageResponse
        }

        let textParts = parts.compactMap { part -> String? in
            guard (part["type"] as? String) == "text" else { return nil }
            return part["text"] as? String
        }

        return textParts.joined(separator: "")
    }
}
