import Foundation

/// Errors raised when a Workers AI response cannot be understood.
public enum WorkersAIResponseError: Error, Equatable {
    case malformedChatCompletion
    case malformedTranscription
    case malformedSpeechSynthesis
    case httpError(statusCode: Int, body: String)
}

/// Decodes the various Cloudflare Workers AI response shapes into plain Swift values.
///
/// The same decoder handles both endpoint modes:
///   * The Buddy Worker proxy returns already-unwrapped JSON.
///   * The direct Cloudflare REST API wraps payloads in `{ "result": { ... } }`.
/// Each decoder therefore checks the unwrapped shape first and falls back to `result`.
public enum WorkersAIResponseDecoders {
    /// Extracts the assistant text from a non-streaming OpenAI-compatible chat completion.
    public static func decodeChatCompletionText(from responseData: Data) throws -> String {
        guard
            let rootObject = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else {
            throw WorkersAIResponseError.malformedChatCompletion
        }

        let payloadObject = (rootObject["result"] as? [String: Any]) ?? rootObject

        guard
            let choices = payloadObject["choices"] as? [[String: Any]],
            let firstChoice = choices.first
        else {
            throw WorkersAIResponseError.malformedChatCompletion
        }

        // OpenAI-compatible chat shape: choices[].message.content
        if let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        // Some Workers AI models echo the raw `response` field instead.
        if let response = payloadObject["response"] as? String {
            return response
        }

        throw WorkersAIResponseError.malformedChatCompletion
    }

    /// Extracts the transcribed text from a Whisper response.
    public static func decodeTranscriptionText(from responseData: Data) throws -> String {
        guard
            let rootObject = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else {
            throw WorkersAIResponseError.malformedTranscription
        }

        let payloadObject = (rootObject["result"] as? [String: Any]) ?? rootObject

        guard let transcribedText = payloadObject["text"] as? String else {
            throw WorkersAIResponseError.malformedTranscription
        }

        return transcribedText
    }

    /// Extracts MP3 audio bytes from a MeloTTS response.
    ///
    /// Accepts either raw audio bytes (when the proxy streams `audio/mpeg` straight through)
    /// or a JSON body carrying base64 audio under `audio` (the raw Cloudflare shape).
    public static func decodeSynthesizedSpeechAudio(
        from responseData: Data,
        contentType: String?
    ) throws -> Data {
        if let contentType, contentType.lowercased().contains("audio") {
            return responseData
        }

        guard
            let rootObject = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else {
            // No JSON envelope and not declared as audio — treat the bytes as the audio.
            return responseData
        }

        let payloadObject = (rootObject["result"] as? [String: Any]) ?? rootObject

        guard
            let base64Audio = payloadObject["audio"] as? String,
            let audioData = Data(base64Encoded: base64Audio)
        else {
            throw WorkersAIResponseError.malformedSpeechSynthesis
        }

        return audioData
    }
}
