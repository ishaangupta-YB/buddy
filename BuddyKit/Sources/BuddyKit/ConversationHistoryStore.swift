import Foundation

/// Keeps a bounded window of recent user/assistant exchanges so the companion model has
/// context without the request growing without bound. Oldest exchanges are dropped first.
public struct ConversationHistoryStore: Equatable, Sendable {
    public private(set) var exchanges: [ConversationExchange]
    public let limit: Int

    public init(limit: Int) {
        // Guard against a non-positive limit so the store always behaves sensibly.
        self.limit = max(1, limit)
        self.exchanges = []
    }

    /// Records a completed exchange, trimming the oldest entries beyond the limit.
    public mutating func record(userText: String, assistantText: String) {
        exchanges.append(ConversationExchange(userText: userText, assistantText: assistantText))
        if exchanges.count > limit {
            exchanges.removeFirst(exchanges.count - limit)
        }
    }

    /// Clears all recorded exchanges (for example when the user starts a fresh conversation).
    public mutating func reset() {
        exchanges.removeAll()
    }
}
