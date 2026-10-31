import Foundation

/// ConversationOrdering decides the order of the Messages list.
public enum ConversationOrdering {
    /// The main chat first, then the rest in the order given.
    public static func pinningMain(_ rows: [ConversationSummary]) -> [ConversationSummary] {
        rows.filter { $0.isMain == true } + rows.filter { $0.isMain != true }
    }
}
