import Foundation

/// A captured screen image plus a human-readable label describing which display it is.
public struct LabeledScreenImage: Equatable, Sendable {
    public let imageData: Data
    public let label: String

    public init(imageData: Data, label: String) {
        self.imageData = imageData
        self.label = label
    }

    /// Detects the image's MIME type by inspecting its magic bytes.
    ///
    /// ScreenCaptureKit hands us JPEG, but an image pasted from the clipboard may be PNG.
    /// The OpenAI-compatible endpoint rejects a data URI whose declared type does not match
    /// the actual bytes, so we detect rather than assume.
    public func detectedMimeType() -> String {
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        if imageData.count >= pngSignature.count {
            let leadingBytes = [UInt8](imageData.prefix(pngSignature.count))
            if leadingBytes == pngSignature {
                return "image/png"
            }
        }
        return "image/jpeg"
    }

    /// The `data:` URI used by the OpenAI-compatible `image_url` content block.
    public func base64DataURI() -> String {
        "data:\(detectedMimeType());base64,\(imageData.base64EncodedString())"
    }
}

/// A single prior exchange in the running conversation, kept so the model has context.
public struct ConversationExchange: Equatable, Sendable {
    public let userText: String
    public let assistantText: String

    public init(userText: String, assistantText: String) {
        self.userText = userText
        self.assistantText = assistantText
    }
}

/// Builds the JSON body for the Cloudflare Workers AI OpenAI-compatible
/// `/chat/completions` request, including a system prompt, prior conversation turns, and
/// the current turn's labeled screenshots plus the user's transcribed prompt.
public enum ChatCompletionRequestBuilder {
    public static func makeRequestBody(
        model: WorkersAIChatModel,
        systemPrompt: String,
        conversationHistory: [ConversationExchange],
        labeledScreenImages: [LabeledScreenImage],
        userPrompt: String,
        maximumResponseTokens: Int,
        stream: Bool
    ) -> [String: Any] {
        var messages: [[String: Any]] = []

        messages.append([
            "role": "system",
            "content": systemPrompt
        ])

        for exchange in conversationHistory {
            messages.append(["role": "user", "content": exchange.userText])
            messages.append(["role": "assistant", "content": exchange.assistantText])
        }

        // The current turn carries every labeled screenshot followed by the spoken prompt.
        var currentTurnContentBlocks: [[String: Any]] = []
        for labeledScreenImage in labeledScreenImages {
            currentTurnContentBlocks.append([
                "type": "image_url",
                "image_url": ["url": labeledScreenImage.base64DataURI()]
            ])
            currentTurnContentBlocks.append([
                "type": "text",
                "text": labeledScreenImage.label
            ])
        }
        currentTurnContentBlocks.append([
            "type": "text",
            "text": userPrompt
        ])
        messages.append(["role": "user", "content": currentTurnContentBlocks])

        return [
            "model": model.modelIdentifier,
            "max_tokens": maximumResponseTokens,
            "stream": stream,
            "messages": messages
        ]
    }

    /// Serializes `makeRequestBody` to JSON `Data`.
    public static func makeRequestBodyData(
        model: WorkersAIChatModel,
        systemPrompt: String,
        conversationHistory: [ConversationExchange],
        labeledScreenImages: [LabeledScreenImage],
        userPrompt: String,
        maximumResponseTokens: Int,
        stream: Bool
    ) throws -> Data {
        let requestBody = makeRequestBody(
            model: model,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            labeledScreenImages: labeledScreenImages,
            userPrompt: userPrompt,
            maximumResponseTokens: maximumResponseTokens,
            stream: stream
        )
        return try JSONSerialization.data(withJSONObject: requestBody, options: [.sortedKeys])
    }
}
