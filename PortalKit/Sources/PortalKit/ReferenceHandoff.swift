import Foundation

/// ReferenceHandoff carries the resource an Ask button names from the screen to the main chat's composer. It is set before
/// the chat opens and taken by the chat that is shown, however the chat came to be on screen: freshly made, or already open.
public struct ReferenceHandoff: Equatable, Sendable {
    public struct Pending: Equatable, Sendable {
        public let conversationId: String
        public let viewing: Viewing
        public let subject: String
    }

    public private(set) var pending: Pending?

    public init() {}

    /// The conversation the reference waits for, so a screen can watch for it.
    public var conversationId: String? { pending?.conversationId }

    public mutating func set(conversationId: String, viewing: Viewing, subject: String) {
        pending = Pending(conversationId: conversationId, viewing: viewing, subject: subject)
    }

    /// The reference for this conversation, once: it is cleared as it is taken. Another conversation gets nothing and leaves it waiting.
    public mutating func take(for conversationId: String) -> Pending? {
        guard let found = pending, found.conversationId == conversationId else { return nil }
        pending = nil
        return found
    }

    /// What the chip says: the kind of thing, then its name, as in "Site: Example".
    public static func chipText(kindName: String, subject: String) -> String {
        subject.isEmpty ? kindName : "\(kindName): \(subject)"
    }
}
