import Foundation

/// ThreadSummary is what a message with a thread says of it in the main history: how many replies it holds and when the last came.
public struct ThreadSummary: Equatable, Sendable {
    public let replyCount: Int
    public let lastReplyAt: String?

    public init(replyCount: Int, lastReplyAt: String? = nil) {
        self.replyCount = replyCount
        self.lastReplyAt = lastReplyAt
    }

    public var lastReplyDate: Date? { PortalDate.parse(lastReplyAt) }

    /// A thread of one reply, such as a question with its answer, needs no count under its root.
    public var isCountShown: Bool { replyCount >= 2 }

    /// The summary a message carries, or nil when it has no thread.
    public init?(_ message: ConversationMessage) {
        guard let count = message.threadReplyCount, count > 0 else { return nil }
        self.init(replyCount: count, lastReplyAt: message.threadLastReplyAt)
    }
}

/// ThreadRouting decides where a thing belongs when a conversation has threads. A screen shows either the main history, or one thread.
/// It names the thread it shows by the id of the message the thread hangs from; the main history has none (nil, or empty).
public enum ThreadRouting {
    /// How many of a thread's latest messages it opens with, the most one read returns. A thread does not page.
    public static let threadMessageCount = 500

    /// The events a run emits while it works. Each belongs to the thread the run answers in; everything else reaches every screen.
    static let runContentKinds: Set<ConversationEvent.Kind> = [.textDelta, .toolCall, .toolResult, .roundRetry, .modelSwitch]

    /// An id, or nil for the empty string the server uses for "no thread".
    public static func normalized(_ threadRootMessageId: String?) -> String? {
        guard let threadRootMessageId, !threadRootMessageId.isEmpty else { return nil }
        return threadRootMessageId
    }

    /// Whether the quote of a reply would only repeat the root of its thread, which the reply sits under. While the root is not on
    /// the screen the quote is all that says what the reply answers, so it stays.
    public static func quoteRepeatsRoot(replyToMessageId: String, threadRootMessageId: String?, isRootShown: Bool) -> Bool {
        isRootShown && replyToMessageId == normalized(threadRootMessageId)
    }

    /// Whether an event is shown on the screen that has `viewThreadRootMessageId` open. The main history shows every event, a run in
    /// a thread included. A thread shows what a run says as it works (text, tool calls) only when the run answers in it; a chat
    /// message, a card or the end of a run reaches it as it reaches every screen.
    public static func isEventForView(_ event: ConversationEvent, viewThreadRootMessageId: String?) -> Bool {
        guard let view = normalized(viewThreadRootMessageId) else { return true }
        guard let kind = event.kind, runContentKinds.contains(kind) else { return true }
        return normalized(event.threadRootMessageId) == view
    }

    /// Whether the event is something a run says as it works.
    public static func isRunContent(_ event: ConversationEvent) -> Bool {
        guard let kind = event.kind else { return false }
        return runContentKinds.contains(kind)
    }

    /// The thread an event shows the assistant working in: the id, or nil for a run in no thread and for any other event.
    public static func workingThreadRootMessageId(of event: ConversationEvent) -> String? {
        guard isRunContent(event) else { return nil }
        return normalized(event.threadRootMessageId)
    }

    /// Whether a call with the assistant reads aloud what this event says: a call in a thread speaks only the runs answering in that
    /// thread, and a call on the main history only the runs answering there. Anything that is not a run's words is for every call.
    public static func isHeardInCall(_ event: ConversationEvent, callThreadRootMessageId: String?) -> Bool {
        guard isRunContent(event) else { return true }
        return normalized(event.threadRootMessageId) == normalized(callThreadRootMessageId)
    }

    /// Whether the screen shows a run at work: any run on the main history, and on a thread the run that answers in it.
    public static func isViewRunning(isRunning: Bool, workingThreadRootMessageId: String?, viewThreadRootMessageId: String?) -> Bool {
        guard isRunning else { return false }
        guard let view = normalized(viewThreadRootMessageId) else { return true }
        return normalized(workingThreadRootMessageId) == view
    }

    /// Whether a persisted message is listed on the screen: a thread lists its root and its replies, the main history lists every message.
    public static func belongs(_ message: ConversationMessage, toViewWithThreadRootMessageId viewThreadRootMessageId: String?) -> Bool {
        belongs(messageId: message.id, threadRootMessageId: message.threadRootMessageId, toViewWithThreadRootMessageId: viewThreadRootMessageId)
    }

    public static func belongs(messageId: String, threadRootMessageId: String?, toViewWithThreadRootMessageId viewThreadRootMessageId: String?) -> Bool {
        guard let view = normalized(viewThreadRootMessageId) else { return true }
        return messageId == view || normalized(threadRootMessageId) == view
    }

    /// The thread a tap on a message opens: the thread it is a reply in, else its own when it has replies, else none.
    public static func threadToOpen(messageId: String, threadRootMessageId: String?, replyCount: Int) -> String? {
        if let root = normalized(threadRootMessageId) { return root }
        return replyCount > 0 ? messageId : nil
    }

    /// The thread a tap on a message of a chat's main history opens: the thread it is a reply in, else its own, replies or not. A
    /// message that has none yet opens as the message and a composer that starts its thread. A deleted message opens nothing.
    public static func chatThreadToOpen(messageId: String, threadRootMessageId: String?, isDeleted: Bool) -> String? {
        if let root = normalized(threadRootMessageId) { return root }
        return isDeleted ? nil : messageId
    }

    /// How long after its last reply a thread the person took part in is offered to continue from the main history.
    public static let continueWindow: TimeInterval = 30 * 60

    /// The thread the main history's composer offers to continue: the most recently active thread of the chat that the person took part
    /// in (wrote its root or a reply in it) and that had a reply in the last 30 minutes. Worked out from the messages the screen has
    /// loaded; the server keeps nothing for it.
    public static func threadToContinue(_ messages: [ChatMessage], currentUserId: String, now: Date = Date()) -> ChatMessage? {
        var participated = Set<String>()
        for message in messages where message.authorUserId == currentUserId && !message.isDeleted {
            if let root = normalized(message.threadRootMessageId) { participated.insert(root) } else { participated.insert(message.id) }
        }
        return messages
            .filter { root in
                normalized(root.threadRootMessageId) == nil && !root.isDeleted && root.threadReplyCount > 0 && participated.contains(root.id)
            }
            .compactMap { root -> (ChatMessage, Date)? in
                guard let last = PortalDate.parse(root.threadLastReplyAt), now.timeIntervalSince(last) <= continueWindow else { return nil }
                return (root, last)
            }
            .max { $0.1 < $1.1 }?.0
    }

    /// The first words of a thread's root, for the hint that offers to continue it.
    public static func excerpt(_ text: String, maximumCharacters: Int = 40) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard flat.count > maximumCharacters else { return flat }
        let cut = flat.prefix(maximumCharacters)
        // Cut at the end of a word: where the cut already ends one, there; else at the last space before it.
        let endsAWord = flat[flat.index(flat.startIndex, offsetBy: maximumCharacters)] == " "
        let atWord = endsAWord ? cut : (cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut)
        return atWord.trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// The message a send replies to. A thread's composer replies to the message the person picked, else to the thread's root, which
    /// is what puts the message in the thread. The main history replies only to a message picked.
    public static func replyToMessageId(pickedMessageId: String?, viewThreadRootMessageId: String?) -> String? {
        if let pickedMessageId, !pickedMessageId.isEmpty { return pickedMessageId }
        return normalized(viewThreadRootMessageId)
    }
}

extension Documents {
    /// The fields a message and an event add when the server has threads. Sent only to a server that offers them.
    static let threadMessageFields = "threadRootMessageId threadReplyCount threadLastReplyAt"

    /// A document with the thread fields added wherever it asks for a message's fields, and for the event a run emits.
    public static func withThreads(_ document: String) -> String {
        document
            .replacingOccurrences(of: "linkPreviewsRemovedAt", with: "linkPreviewsRemovedAt \(threadMessageFields)")
            .replacingOccurrences(
                of: "OnConversationEvent(conversationId: $conversationId) {", with: "OnConversationEvent(conversationId: $conversationId) { threadRootMessageId")
    }

    /// One thread of a conversation, its root first. Used only where the server offers threads.
    public static let listMessagesInThread = """
        query ListConversationMessages($conversationId: String!, $latestMessageCount: Int, $threadRootMessageId: String) {
          ListConversationMessages(
            conversationId: $conversationId, latestMessageCount: $latestMessageCount, threadRootMessageId: $threadRootMessageId
          ) {
            id role content toolCalls toolCallId toolName stopReason createdAt metadata viewingKind viewingId viewingLabel
            \(chatMessageFields)
            reactions { id messageId reactorKind reactorUserId emoji isAcknowledgment createdAt }
          }
        }
        """

    /// The thread an old answer joined when it was first replied to.
    public static let getMessageThreadRoot = """
        query GetMessageThreadRoot($conversationId: String, $messageId: String) {
          GetMessageThreadRoot(conversationId: $conversationId, messageId: $messageId) { threadRootMessageId }
        }
        """

    static var messageThreadDocuments: [String] { [listMessagesInThread, getMessageThreadRoot] }
}

extension ServerCapabilities {
    /// Whether the server has message threads: it reads one thread. A server without them refuses a query that names the argument
    /// or the fields.
    public var offersMessageThreads: Bool { listMessageArgumentNames.contains("threadRootMessageId") }
}

extension Connection {
    /// The thread a message belongs to now: an old answer with no thread joins its question's thread on its first reply. Nil when
    /// the server does not say or the message is in none.
    public func messageThreadRoot(conversationId: String, messageId: String) async -> String? {
        struct Answer: Decodable, Sendable {
            struct Root: Decodable, Sendable { let threadRootMessageId: String? }
            let GetMessageThreadRoot: Root?
        }
        let answer = try? await execute(
            Documents.getMessageThreadRoot, variables: ["conversationId": .string(conversationId), "messageId": .string(messageId)], as: Answer.self)
        return ThreadRouting.normalized(answer?.GetMessageThreadRoot?.threadRootMessageId)
    }
}
