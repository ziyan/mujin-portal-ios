import Foundation

/// WaitingItem is a question or an approval that waits for the person, in
/// any of their conversations.
public struct WaitingItem: Codable, Equatable, Identifiable, Sendable {
    public let conversationId: String
    public let organizationId: String?
    public let ownerUserId: String?
    public let conversationTitle: String?
    /// `question` or `approval`.
    public let waitingKind: String
    public let interactionId: String
    public let promptText: String?
    public let toolName: String?
    public let toolRisk: String?
    public let askedAt: String?
    public let expiresAt: String?

    public var id: String { "\(waitingKind):\(interactionId)" }
    public var isApproval: Bool { waitingKind == "approval" }
    public var isQuestion: Bool { waitingKind == "question" }

    public init(
        conversationId: String, organizationId: String? = nil, ownerUserId: String? = nil, conversationTitle: String? = nil,
        waitingKind: String, interactionId: String, promptText: String? = nil, toolName: String? = nil, toolRisk: String? = nil,
        askedAt: String? = nil, expiresAt: String? = nil
    ) {
        self.conversationId = conversationId
        self.organizationId = organizationId
        self.ownerUserId = ownerUserId
        self.conversationTitle = conversationTitle
        self.waitingKind = waitingKind
        self.interactionId = interactionId
        self.promptText = promptText
        self.toolName = toolName
        self.toolRisk = toolRisk
        self.askedAt = askedAt
        self.expiresAt = expiresAt
    }
}

extension Array where Element == WaitingItem {
    /// How many items wait in each conversation, for the badge on its row.
    public var countsByConversation: [String: Int] {
        reduce(into: [:]) { counts, item in counts[item.conversationId, default: 0] += 1 }
    }
}

extension Connection {
    /// The latest messages of a conversation, oldest first. With
    /// `beforeMessageId` it is the page before that message.
    public func messages(conversationId: String, latestCount: Int?, beforeMessageId: String? = nil) async throws -> [ConversationMessage] {
        struct Answer: Decodable, Sendable { let ListConversationMessages: [ConversationMessage]? }
        var variables: [String: JSONValue] = ["conversationId": .string(conversationId)]
        if let latestCount { variables["latestMessageCount"] = .number(Double(latestCount)) }
        if let beforeMessageId { variables["beforeMessageId"] = .string(beforeMessageId) }
        return try await execute(Documents.listMessages, variables: variables, as: Answer.self).ListConversationMessages ?? []
    }

    /// How many messages the conversation holds, for "N earlier messages".
    public func messageCount(conversationId: String) async throws -> Int {
        struct Answer: Decodable, Sendable {
            struct Count: Decodable, Sendable { let messageCount: Int? }
            let CountConversationMessages: Count?
        }
        let answer = try await execute(Documents.countMessages, variables: ["conversationId": .string(conversationId)], as: Answer.self)
        return answer.CountConversationMessages?.messageCount ?? 0
    }

    /// Searches the person's conversations by title and by what was said.
    public func conversations(userId: String, search: String) async throws -> [ConversationSummary] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let conversations: [ConversationSummary]? }
            let ListConversations: List
        }
        let answer = try await execute(
            Documents.listConversations, variables: ["userId": .string(userId), "search": .string(search)], as: Answer.self)
        return (answer.ListConversations.conversations ?? []).sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
    }

    @discardableResult
    public func renameConversation(id: String, title: String) async throws -> ConversationSummary? {
        struct Answer: Decodable, Sendable {
            struct Renamed: Decodable, Sendable { let conversation: ConversationSummary? }
            let RenameConversation: Renamed?
        }
        let answer = try await execute(
            Documents.renameConversation, variables: ["conversationId": .string(id), "title": .string(title)], as: Answer.self)
        return answer.RenameConversation?.conversation
    }

    /// Reacts to a message and returns the message's whole list of reactions
    /// after the change. An empty emoji takes the person's reaction back.
    public func react(conversationId: String, messageId: String, emoji: String) async throws -> [Reaction] {
        struct Answer: Decodable, Sendable {
            struct Reacted: Decodable, Sendable {
                struct Message: Decodable, Sendable { let reactions: [Reaction]? }
                let message: Message?
            }
            let ReactToConversationMessage: Reacted?
        }
        let answer = try await execute(
            Documents.reactToMessage,
            variables: ["conversationId": .string(conversationId), "messageId": .string(messageId), "emoji": .string(emoji)], as: Answer.self)
        return answer.ReactToConversationMessage?.message?.reactions ?? []
    }

    /// Every question and approval that waits for the person, oldest first.
    public func waiting(shouldIncludeOthers: Bool = false) async throws -> [WaitingItem] {
        struct Answer: Decodable, Sendable { let ListConversationWaiting: [WaitingItem]? }
        let answer = try await execute(
            Documents.listWaiting, variables: ["shouldIncludeOthers": .bool(shouldIncludeOthers)], as: Answer.self)
        return (answer.ListConversationWaiting ?? []).sorted { (PortalDate.parse($0.askedAt) ?? .distantPast) < (PortalDate.parse($1.askedAt) ?? .distantPast) }
    }
}
