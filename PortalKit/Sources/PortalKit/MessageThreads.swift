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

    /// Whether an event is shown on the screen that has `viewThreadRootMessageId` open. What a run says as it works (text, tool
    /// calls) belongs to the thread it answers in alone; a chat message, a card or the end of a run reaches every screen, and
    /// each reads its own list again.
    public static func isEventForView(_ event: ConversationEvent, viewThreadRootMessageId: String?) -> Bool {
        guard let kind = event.kind, runContentKinds.contains(kind) else { return true }
        return normalized(event.threadRootMessageId) == normalized(viewThreadRootMessageId)
    }

    /// Whether the event is something a run says as it works.
    public static func isRunContent(_ event: ConversationEvent) -> Bool {
        guard let kind = event.kind else { return false }
        return runContentKinds.contains(kind)
    }

    /// The thread an event shows the assistant working in: the id, or nil for a run in the main history and for any other event.
    public static func workingThreadRootMessageId(of event: ConversationEvent) -> String? {
        guard isRunContent(event) else { return nil }
        return normalized(event.threadRootMessageId)
    }

    /// Whether the screen shows a run at work: the thread it answers in, or, on the main history, a run that answers in no thread.
    public static func isViewRunning(isRunning: Bool, workingThreadRootMessageId: String?, viewThreadRootMessageId: String?) -> Bool {
        guard isRunning else { return false }
        return normalized(workingThreadRootMessageId) == normalized(viewThreadRootMessageId)
    }

    /// Whether a persisted message is listed on the screen: a thread lists its root and its replies, the main history everything
    /// that is not a reply in a thread. A reply written before threads existed has no thread and stays in the main history.
    public static func belongs(_ message: ConversationMessage, toViewWithThreadRootMessageId viewThreadRootMessageId: String?) -> Bool {
        belongs(messageId: message.id, threadRootMessageId: message.threadRootMessageId, toViewWithThreadRootMessageId: viewThreadRootMessageId)
    }

    public static func belongs(messageId: String, threadRootMessageId: String?, toViewWithThreadRootMessageId viewThreadRootMessageId: String?) -> Bool {
        guard let view = normalized(viewThreadRootMessageId) else { return normalized(threadRootMessageId) == nil }
        return messageId == view || normalized(threadRootMessageId) == view
    }

    /// The message a send replies to. A thread's composer replies to the message the person picked, else to the thread's root, which
    /// is what puts the message in the thread. The main history replies only to a message picked, which is what a server without
    /// threads understood.
    public static func replyToMessageId(pickedMessageId: String?, viewThreadRootMessageId: String?) -> String? {
        if let pickedMessageId, !pickedMessageId.isEmpty { return pickedMessageId }
        return normalized(viewThreadRootMessageId)
    }

    /// The newest message said in a chat among rows read oldest first, which is what the read mark follows. The main history leaves
    /// replies out, so the newest of the chat can be a reply that only a read of everything shows.
    public static func newestChatMessageId(in rows: [ConversationMessage]) -> String? {
        rows.last { $0.isChatMessage == true && ($0.role == "user" || $0.role == "assistant") }?.id
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

    /// The history of a conversation: the main history without replies, or one thread. Used only where the server offers threads.
    public static let listMessagesInThreads = """
        query ListConversationMessages(
          $conversationId: String!, $latestMessageCount: Int, $beforeMessageId: String, $shouldCollapseThreads: Boolean, $threadRootMessageId: String
        ) {
          ListConversationMessages(
            conversationId: $conversationId, latestMessageCount: $latestMessageCount, beforeMessageId: $beforeMessageId,
            shouldCollapseThreads: $shouldCollapseThreads, threadRootMessageId: $threadRootMessageId
          ) {
            id role content toolCalls toolCallId toolName stopReason createdAt metadata viewingKind viewingId viewingLabel
            \(chatMessageFields)
            reactions { id messageId reactorKind reactorUserId emoji isAcknowledgment createdAt }
          }
        }
        """

    public static let countMessagesInThreads = """
        query CountConversationMessages($conversationId: String, $shouldCollapseThreads: Boolean) {
          CountConversationMessages(conversationId: $conversationId, shouldCollapseThreads: $shouldCollapseThreads) { messageCount }
        }
        """

    static var messageThreadDocuments: [String] { [listMessagesInThreads, countMessagesInThreads] }
}

extension ServerCapabilities {
    /// Whether the server has message threads: it reads one thread, or the main history without replies. A server without them
    /// refuses a query that names the arguments or the fields.
    public var offersMessageThreads: Bool {
        listMessageArgumentNames.contains("threadRootMessageId") && listMessageArgumentNames.contains("shouldCollapseThreads")
    }
}
