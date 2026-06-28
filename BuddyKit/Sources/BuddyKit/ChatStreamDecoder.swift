import Foundation

/// Incrementally decodes the OpenAI-compatible Server-Sent Events stream returned by the
/// Cloudflare Workers AI `/chat/completions` endpoint when `stream: true`.
///
/// Each SSE line looks like `data: {"choices":[{"delta":{"content":"..."}}]}` and the
/// stream terminates with a literal `data: [DONE]`. This decoder is fed one raw line at a
/// time and returns the incremental text chunk contained in that line, if any. Keeping it
/// line-driven makes it trivially unit-testable without a live network connection.
public struct ChatStreamDecoder {
    public init() {}

    /// The marker Cloudflare sends to indicate the stream is complete.
    public static let streamDoneMarker = "[DONE]"

    /// Decodes a single SSE line, returning the text delta it carries.
    ///
    /// Returns `nil` for lines that carry no text — comments, blank lines, the `[DONE]`
    /// marker, or events without a content delta (such as the final `finish_reason` chunk).
    public func decodeTextChunk(fromServerSentEventLine serverSentEventLine: String) -> String? {
        let trimmedLine = serverSentEventLine.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.hasPrefix("data:") else {
            return nil
        }

        let payloadString = trimmedLine
            .dropFirst("data:".count)
            .trimmingCharacters(in: .whitespaces)

        guard payloadString != Self.streamDoneMarker, !payloadString.isEmpty else {
            return nil
        }

        guard
            let payloadData = payloadString.data(using: .utf8),
            let payloadObject = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let choices = payloadObject["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let delta = firstChoice["delta"] as? [String: Any],
            let textChunk = delta["content"] as? String,
            !textChunk.isEmpty
        else {
            return nil
        }

        return textChunk
    }

    /// Returns whether a line is the terminating `[DONE]` marker.
    public func isStreamDoneMarker(_ serverSentEventLine: String) -> Bool {
        let trimmedLine = serverSentEventLine.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.hasPrefix("data:") else { return false }
        let payloadString = trimmedLine
            .dropFirst("data:".count)
            .trimmingCharacters(in: .whitespaces)
        return payloadString == Self.streamDoneMarker
    }
}
