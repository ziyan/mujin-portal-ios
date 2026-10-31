import Foundation

/// The person signed in, as the server knows them.
public struct Me: Codable, Equatable, Sendable {
    public let id: String
    public let email: String?
    public let name: String?
    public let organizationId: String?
    public let permissions: [String]?

    public init(id: String, email: String? = nil, name: String? = nil, organizationId: String? = nil, permissions: [String]? = nil) {
        self.id = id
        self.email = email
        self.name = name
        self.organizationId = organizationId
        self.permissions = permissions
    }
}

public struct Agent: Codable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let isMain: Bool?
    public let isEnabled: Bool?

    public init(id: String, name: String? = nil, isMain: Bool? = nil, isEnabled: Bool? = nil) {
        self.id = id
        self.name = name
        self.isMain = isMain
        self.isEnabled = isEnabled
    }
}

/// ConversationSummary is one row of the conversation list.
public struct ConversationSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let agentId: String?
    public let title: String?
    public let summary: String?
    public let lastMessageAt: String?
    public let activeRunId: String?
    public let archivedAt: String?
    public let createdAt: String?
    public let modifiedAt: String?
    public let isTitleCustom: Bool?
    /// `assistant` or `chat`.
    public let conversationKind: String?
    public let chatId: String?
    public let chat: ChatRoom?

    public init(
        id: String, agentId: String? = nil, title: String? = nil, summary: String? = nil, lastMessageAt: String? = nil,
        activeRunId: String? = nil, archivedAt: String? = nil, createdAt: String? = nil, modifiedAt: String? = nil, isTitleCustom: Bool? = nil,
        conversationKind: String? = nil, chatId: String? = nil, chat: ChatRoom? = nil
    ) {
        self.conversationKind = conversationKind
        self.chatId = chatId
        self.chat = chat
        self.isTitleCustom = isTitleCustom
        self.id = id
        self.agentId = agentId
        self.title = title
        self.summary = summary
        self.lastMessageAt = lastMessageAt
        self.activeRunId = activeRunId
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// When the conversation last moved, for sorting and for showing.
    public var lastActivity: Date? {
        PortalDate.parse(lastMessageAt) ?? PortalDate.parse(modifiedAt) ?? PortalDate.parse(createdAt)
    }

    public var isRunning: Bool { !(activeRunId ?? "").isEmpty }
}

/// ConversationMessage is one persisted row of a conversation.
public struct ConversationMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let role: String
    public let content: JSONValue?
    public let toolCalls: JSONValue?
    public let toolCallId: String?
    public let toolName: String?
    public let stopReason: String?
    public let createdAt: String?
    /// An object, or a string holding one: read it with `objectValue`.
    public let metadata: JSONValue?
    public let reactions: [Reaction]?
    public let viewingKind: String?
    public let viewingId: String?
    public let viewingLabel: String?
    // What a message said in a chat adds. A message with `isChatMessage` false is a private tool row.
    public let isChatMessage: Bool?
    public let authorUserId: String?
    public let authorName: String?
    public let authorOrganizationId: String?
    public let authorOrganizationName: String?
    public let onBehalfOfUserId: String?
    public let onBehalfOfUserName: String?
    public let replyToMessageId: String?
    public let replyToExcerpt: String?
    public let replyToAuthorName: String?
    public let isAddressingAssistant: Bool?
    public let editedAt: String?
    public let deletedAt: String?
    public let linkPreviewsRemovedAt: String?

    public init(
        id: String, role: String, content: JSONValue? = nil, toolCalls: JSONValue? = nil, toolCallId: String? = nil,
        toolName: String? = nil, stopReason: String? = nil, createdAt: String? = nil, metadata: JSONValue? = nil,
        reactions: [Reaction]? = nil, viewingKind: String? = nil, viewingId: String? = nil, viewingLabel: String? = nil,
        isChatMessage: Bool? = nil, authorUserId: String? = nil, authorName: String? = nil, authorOrganizationId: String? = nil,
        authorOrganizationName: String? = nil, onBehalfOfUserId: String? = nil, onBehalfOfUserName: String? = nil,
        replyToMessageId: String? = nil, replyToExcerpt: String? = nil, replyToAuthorName: String? = nil,
        isAddressingAssistant: Bool? = nil, editedAt: String? = nil, deletedAt: String? = nil, linkPreviewsRemovedAt: String? = nil
    ) {
        self.isChatMessage = isChatMessage
        self.authorUserId = authorUserId
        self.authorName = authorName
        self.authorOrganizationId = authorOrganizationId
        self.authorOrganizationName = authorOrganizationName
        self.onBehalfOfUserId = onBehalfOfUserId
        self.onBehalfOfUserName = onBehalfOfUserName
        self.replyToMessageId = replyToMessageId
        self.replyToExcerpt = replyToExcerpt
        self.replyToAuthorName = replyToAuthorName
        self.isAddressingAssistant = isAddressingAssistant
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.linkPreviewsRemovedAt = linkPreviewsRemovedAt
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.stopReason = stopReason
        self.createdAt = createdAt
        self.metadata = metadata
        self.reactions = reactions
        self.viewingKind = viewingKind
        self.viewingId = viewingId
        self.viewingLabel = viewingLabel
    }
}

/// QuestionCard is a question the assistant asked and the person has not answered.
public struct QuestionCard: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let question: String
    public let choices: [String]
    public let allowOther: Bool
    /// When the assistant asked. Missing for a card that arrived live.
    public let askedAt: String?

    public init(id: String, question: String, choices: [String] = [], allowOther: Bool = true, askedAt: String? = nil) {
        self.id = id
        self.question = question
        self.choices = choices
        self.allowOther = allowOther
        self.askedAt = askedAt
    }
}

/// ApprovalCard is a tool call that waits for the person's yes or no.
public struct ApprovalCard: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let toolCallId: String
    public let toolName: String
    public let policyReason: String
    public let risk: String
    public let arguments: String

    public init(id: String, toolCallId: String = "", toolName: String, policyReason: String = "", risk: String = "", arguments: String = "") {
        self.id = id
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.policyReason = policyReason
        self.risk = risk
        self.arguments = arguments
    }
}

/// PortalDate reads the timestamps Portal sends (RFC 3339, with or without
/// fractional seconds).
public enum PortalDate {
    public static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
