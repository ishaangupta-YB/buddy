import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The client Buddy uses to talk to Cloudflare Workers AI for all three legs of the voice
/// pipeline: speech-to-text (Whisper), chat/vision (Kimi), and text-to-speech (MeloTTS).
///
/// The client itself contains no networking primitives — it composes the pure request
/// builders, decoders, and the injected `HTTPTransport`. That keeps every behavior here
/// testable with a deterministic mock transport.
public final class WorkersAIClient: Sendable {
    private let configuration: BuddyConfiguration
    private let endpointResolver: WorkersAIEndpointResolver
    private let transport: HTTPTransport

    public init(configuration: BuddyConfiguration, transport: HTTPTransport) {
        self.configuration = configuration
        self.endpointResolver = WorkersAIEndpointResolver(endpointMode: configuration.endpointMode)
        self.transport = transport
    }

    // MARK: - Chat / Vision

    /// Streams a companion response from the chat model, invoking `onAccumulatedText` with
    /// the full text-so-far each time a new chunk arrives. Returns the complete response.
    public func streamCompanionResponse(
        labeledScreenImages: [LabeledScreenImage],
        userPrompt: String,
        conversationHistory: [ConversationExchange],
        onAccumulatedText: @Sendable (String) -> Void
    ) async throws -> String {
        let request = try makeChatRequest(
            labeledScreenImages: labeledScreenImages,
            userPrompt: userPrompt,
            conversationHistory: conversationHistory,
            stream: true
        )

        let (metadata, lineStream) = try await transport.performStreamingRequest(request)
        guard metadata.isSuccess else {
            let errorBody = try await collectLines(lineStream)
            throw WorkersAIResponseError.httpError(statusCode: metadata.statusCode, body: errorBody)
        }

        let streamDecoder = ChatStreamDecoder()
        var accumulatedText = ""
        for try await serverSentEventLine in lineStream {
            if streamDecoder.isStreamDoneMarker(serverSentEventLine) {
                break
            }
            if let textChunk = streamDecoder.decodeTextChunk(fromServerSentEventLine: serverSentEventLine) {
                accumulatedText += textChunk
                onAccumulatedText(accumulatedText)
            }
        }
        return accumulatedText
    }

    /// Requests a non-streaming companion response. Used where progressive display is not
    /// needed (for example a quick connectivity preflight).
    public func fetchCompanionResponse(
        labeledScreenImages: [LabeledScreenImage],
        userPrompt: String,
        conversationHistory: [ConversationExchange]
    ) async throws -> String {
        let request = try makeChatRequest(
            labeledScreenImages: labeledScreenImages,
            userPrompt: userPrompt,
            conversationHistory: conversationHistory,
            stream: false
        )

        let (responseData, metadata) = try await transport.performRequest(request)
        guard metadata.isSuccess else {
            throw WorkersAIResponseError.httpError(
                statusCode: metadata.statusCode,
                body: String(data: responseData, encoding: .utf8) ?? ""
            )
        }
        return try WorkersAIResponseDecoders.decodeChatCompletionText(from: responseData)
    }

    // MARK: - Speech-to-Text (Whisper)

    /// Transcribes push-to-talk audio using the Whisper model. `audioData` is the raw audio
    /// (for example MP3 or WAV) that the client base64-encodes for Cloudflare.
    public func transcribeSpeech(audioData: Data) async throws -> String {
        var requestBody: [String: Any] = [
            "audio": audioData.base64EncodedString()
        ]
        if let speechToTextLanguageCode = configuration.speechToTextLanguageCode {
            requestBody["language"] = speechToTextLanguageCode
        }

        let request = try makeJSONRequest(
            url: endpointResolver.speechToTextURL(),
            requestBody: requestBody
        )

        let (responseData, metadata) = try await transport.performRequest(request)
        guard metadata.isSuccess else {
            throw WorkersAIResponseError.httpError(
                statusCode: metadata.statusCode,
                body: String(data: responseData, encoding: .utf8) ?? ""
            )
        }
        return try WorkersAIResponseDecoders.decodeTranscriptionText(from: responseData)
    }

    // MARK: - Text-to-Speech (MeloTTS)

    /// Synthesizes spoken audio for `text` using MeloTTS, returning MP3 audio bytes.
    public func synthesizeSpeech(text: String) async throws -> Data {
        let requestBody: [String: Any] = [
            "prompt": text,
            "lang": configuration.textToSpeechLanguageCode
        ]

        let request = try makeJSONRequest(
            url: endpointResolver.textToSpeechURL(),
            requestBody: requestBody,
            acceptHeader: "audio/mpeg"
        )

        let (responseData, metadata) = try await transport.performRequest(request)
        guard metadata.isSuccess else {
            throw WorkersAIResponseError.httpError(
                statusCode: metadata.statusCode,
                body: String(data: responseData, encoding: .utf8) ?? ""
            )
        }
        return try WorkersAIResponseDecoders.decodeSynthesizedSpeechAudio(
            from: responseData,
            contentType: metadata.contentType
        )
    }

    // MARK: - Request Construction

    private func makeChatRequest(
        labeledScreenImages: [LabeledScreenImage],
        userPrompt: String,
        conversationHistory: [ConversationExchange],
        stream: Bool
    ) throws -> URLRequest {
        let bodyData = try ChatCompletionRequestBuilder.makeRequestBodyData(
            model: configuration.chatModel,
            systemPrompt: SystemPrompts.companionVoiceResponse,
            conversationHistory: conversationHistory,
            labeledScreenImages: labeledScreenImages,
            userPrompt: userPrompt,
            maximumResponseTokens: configuration.maximumResponseTokens,
            stream: stream
        )

        var request = URLRequest(url: endpointResolver.chatCompletionsURL())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorizationHeaderIfNeeded(to: &request)
        request.httpBody = bodyData
        return request
    }

    private func makeJSONRequest(
        url: URL,
        requestBody: [String: Any],
        acceptHeader: String? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let acceptHeader {
            request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        }
        applyAuthorizationHeaderIfNeeded(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [.sortedKeys])
        return request
    }

    private func applyAuthorizationHeaderIfNeeded(to request: inout URLRequest) {
        if let bearerToken = endpointResolver.bearerToken() {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private func collectLines(_ lineStream: AsyncThrowingStream<String, Error>) async throws -> String {
        var collectedLines: [String] = []
        for try await line in lineStream {
            collectedLines.append(line)
        }
        return collectedLines.joined(separator: "\n")
    }
}
