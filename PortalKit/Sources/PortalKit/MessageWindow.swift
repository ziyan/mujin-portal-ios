import Foundation

/// MessageWindow is the part of a long conversation the screen holds: the
/// latest messages, grown backwards a page at a time.
public struct MessageWindow: Equatable, Sendable {
    public static let pageSize = 30

    public private(set) var messages: [ConversationMessage] = []
    public private(set) var totalCount: Int?

    public init() {}

    /// How many messages sit before the ones held, when the total is known.
    public var earlierCount: Int {
        guard let totalCount else { return 0 }
        return max(0, totalCount - messages.count)
    }

    /// The id to page backwards from.
    public var firstMessageId: String? { messages.first?.id }

    /// How many of the latest messages a reload asks for: everything held
    /// plus room for what arrived since, so the window stays in one piece.
    public var reloadCount: Int { max(Self.pageSize, messages.count + 20) }

    public mutating func replace(with latest: [ConversationMessage], totalCount: Int?) {
        messages = latest
        if let totalCount { self.totalCount = totalCount }
    }

    /// Adds an older page in front, skipping messages already held.
    public mutating func prepend(_ earlier: [ConversationMessage]) {
        let held = Set(messages.map(\.id))
        messages = earlier.filter { !held.contains($0.id) } + messages
    }
}
