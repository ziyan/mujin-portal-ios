import Foundation

/// ConversationOrdering decides the order of the Messages list. Every path that
/// fills the list (a fresh read and a held copy) goes through `ordered`, so the
/// order never depends on where the rows came from.
public enum ConversationOrdering {
    /// When a conversation last moved: the latest of its last message, its chat's last message and its
    /// modification, falling back to its creation only when it has none of those.
    public static func activity(_ conversation: ConversationSummary) -> Date {
        let moments = [
            PortalDate.parse(conversation.lastMessageAt), PortalDate.parse(conversation.chat?.lastMessageAt), PortalDate.parse(conversation.modifiedAt),
        ].compactMap { $0 }
        return moments.max() ?? PortalDate.parse(conversation.createdAt) ?? .distantPast
    }

    /// The main chat first, then what waits for the person, then the rest, each group newest first.
    public static func ordered(_ rows: [ConversationSummary], waitingIds: Set<String> = []) -> [ConversationSummary] {
        func rank(_ row: ConversationSummary) -> Int {
            if row.isMain == true { return 0 }
            return waitingIds.contains(row.id) ? 1 : 2
        }
        return rows.sorted { first, second in
            if rank(first) != rank(second) { return rank(first) < rank(second) }
            let firstActivity = activity(first)
            let secondActivity = activity(second)
            if firstActivity != secondActivity { return firstActivity > secondActivity }
            return first.id < second.id
        }
    }

    /// The main chat first, then the rest in the order given.
    public static func pinningMain(_ rows: [ConversationSummary]) -> [ConversationSummary] {
        rows.filter { $0.isMain == true } + rows.filter { $0.isMain != true }
    }
}
