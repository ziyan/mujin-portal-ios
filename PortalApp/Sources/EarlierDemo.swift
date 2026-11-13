import Foundation

/// EarlierDemo stages the row at the top of a conversation for the screenshot run and the UI tests: a conversation longer than one
/// page, read a page at a time as the server does, whose earlier page arrives, never arrives, or is refused.
enum EarlierDemo {
    static let conversationId = "conversation01"
    /// How many messages the staged conversation holds: more than one page, less than two.
    static let messageCount = 40
    static let failureMessage = "The server is not answering."

    static func owns(_ screen: String?) -> Bool { ["earlier-more", "earlier-loading", "earlier-failed"].contains(screen ?? "") }

    /// The staged conversation: a question and its answer, over and over, the oldest first.
    static func rows(stamp: (TimeInterval) -> String) -> [[String: Any]] {
        (1...messageCount).map { index in
            let isQuestion = index % 2 == 1
            return [
                "id": String(format: "e%02d", index), "role": isQuestion ? "user" : "assistant",
                "content": isQuestion ? "Question \(index / 2 + 1) about the pick rate." : "Answer \(index / 2): the pick rate held steady.",
                "createdAt": stamp(Double(messageCount - index + 1) * 60),
            ]
        }
    }

    /// A page as the server reads it: the latest messages, or those before a message, at most the count asked for.
    static func page(_ rows: [[String: Any]], variables: [String: Any]) -> [[String: Any]] {
        var held = rows
        if let before = variables["beforeMessageId"] as? String, let index = held.firstIndex(where: { ($0["id"] as? String) == before }) {
            held = Array(held[..<index])
        }
        if let count = variables["latestMessageCount"] as? Int { held = Array(held.suffix(count)) }
        return held
    }

    /// Whether a read is of an earlier page: the one the screen holds back or refuses.
    static func isEarlierRead(operation: String, variables: [String: Any]) -> Bool {
        operation == "ListConversationMessages" && (variables["conversationId"] as? String) == conversationId && variables["beforeMessageId"] != nil
    }
}
