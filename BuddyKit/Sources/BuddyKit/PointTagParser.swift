import Foundation

/// The result of parsing a `[POINT:...]` tag out of a model response.
///
/// Buddy's companion model is instructed to append a pointing tag at the very end of its
/// reply so the on-screen cursor can fly to a specific UI element. This parser separates
/// the spoken text (everything before the tag) from the pointing instruction.
public struct PointTagParseResult: Equatable, Sendable {
    /// The response text with the pointing tag removed — this is what gets spoken aloud.
    public let spokenText: String

    /// The parsed pixel coordinate in the screenshot's coordinate space, or `nil` when the
    /// model emitted `[POINT:none]` or no tag at all.
    public let coordinate: BuddyPoint?

    /// A short 1–3 word label describing the element being pointed at, when present.
    public let elementLabel: String?

    /// The 1-based screen index the coordinate refers to, or `nil` to default to the
    /// screen the cursor is currently on.
    public let screenNumber: Int?

    public init(
        spokenText: String,
        coordinate: BuddyPoint?,
        elementLabel: String?,
        screenNumber: Int?
    ) {
        self.spokenText = spokenText
        self.coordinate = coordinate
        self.elementLabel = elementLabel
        self.screenNumber = screenNumber
    }
}

/// Parses `[POINT:x,y:label:screenN]` and `[POINT:none]` tags from the end of a model
/// response. The grammar matches Buddy's companion system prompt exactly.
public enum PointTagParser {
    /// Matches a trailing tag of one of these shapes:
    ///   `[POINT:none]`
    ///   `[POINT:123,456]`
    ///   `[POINT:123,456:label]`
    ///   `[POINT:123,456:label:screen2]`
    private static let pointTagPattern =
        #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$"#

    public static func parse(from responseText: String) -> PointTagParseResult {
        guard
            let regularExpression = try? NSRegularExpression(pattern: pointTagPattern),
            let match = regularExpression.firstMatch(
                in: responseText,
                range: NSRange(responseText.startIndex..., in: responseText)
            ),
            let matchedTagRange = Range(match.range, in: responseText)
        else {
            // No pointing tag present — the whole response is spoken text.
            return PointTagParseResult(
                spokenText: responseText,
                coordinate: nil,
                elementLabel: nil,
                screenNumber: nil
            )
        }

        let spokenText = String(responseText[..<matchedTagRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // When the x/y capture groups are absent the model emitted `[POINT:none]`.
        guard
            let horizontalPixelRange = Range(match.range(at: 1), in: responseText),
            let verticalPixelRange = Range(match.range(at: 2), in: responseText),
            let horizontalPixel = Double(responseText[horizontalPixelRange]),
            let verticalPixel = Double(responseText[verticalPixelRange])
        else {
            return PointTagParseResult(
                spokenText: spokenText,
                coordinate: nil,
                elementLabel: "none",
                screenNumber: nil
            )
        }

        var elementLabel: String?
        if let labelRange = Range(match.range(at: 3), in: responseText) {
            elementLabel = String(responseText[labelRange])
                .trimmingCharacters(in: .whitespaces)
        }

        var screenNumber: Int?
        if let screenNumberRange = Range(match.range(at: 4), in: responseText) {
            screenNumber = Int(responseText[screenNumberRange])
        }

        return PointTagParseResult(
            spokenText: spokenText,
            coordinate: BuddyPoint(x: horizontalPixel, y: verticalPixel),
            elementLabel: elementLabel,
            screenNumber: screenNumber
        )
    }
}
