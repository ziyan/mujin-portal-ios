import Foundation

/// ChatMember is a person in a chat now, or who was.
public struct ChatMember: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let userName: String?
    public let organizationId: String?
    public let organizationName: String?
    public let isMujinUser: Bool?
    public let isAdmin: Bool?
    public let lastReadMessageId: String?
    public let leftAt: String?
    /// `all`, `mentions` or `none`.
    public let notificationLevel: String?

    public init(
        id: String, userId: String, userName: String? = nil, organizationId: String? = nil, organizationName: String? = nil,
        isMujinUser: Bool? = nil, isAdmin: Bool? = nil, lastReadMessageId: String? = nil, leftAt: String? = nil, notificationLevel: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.userName = userName
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.isMujinUser = isMujinUser
        self.isAdmin = isAdmin
        self.lastReadMessageId = lastReadMessageId
        self.leftAt = leftAt
        self.notificationLevel = notificationLevel
    }

    public var isPresent: Bool { (leftAt ?? "").isEmpty }
    public var shownName: String { (userName ?? "").isEmpty ? "Someone" : userName! }
}

/// ChatRoom is a chat as the list and the chat screen know it.
public struct ChatRoom: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let organizationId: String?
    /// `direct` or `group`.
    public let chatKind: String?
    public let name: String?
    /// The group's name, or for a direct chat the other person.
    public let displayName: String?
    public let isMemoryFilingEnabled: Bool?
    public let lastMessageAt: String?
    public let readerConversationId: String?
    /// `all`, `mentions` or `none`.
    public let readerNotificationLevel: String?
    public let isReaderAdmin: Bool?
    /// False when the person left: they read what was said, and cannot write.
    public let isReaderMember: Bool?
    public let readerUnreadMessageCount: Int64?
    public let readerLastReadMessageId: String?
    public let lastMessageExcerpt: String?
    public let lastMessageAuthorName: String?
    public let members: [ChatMember]?

    public init(
        id: String, organizationId: String? = nil, chatKind: String? = nil, name: String? = nil, displayName: String? = nil,
        isMemoryFilingEnabled: Bool? = nil, lastMessageAt: String? = nil, readerConversationId: String? = nil,
        readerNotificationLevel: String? = nil, isReaderAdmin: Bool? = nil, isReaderMember: Bool? = nil, readerUnreadMessageCount: Int64? = nil,
        readerLastReadMessageId: String? = nil, lastMessageExcerpt: String? = nil, lastMessageAuthorName: String? = nil, members: [ChatMember]? = nil
    ) {
        self.id = id
        self.organizationId = organizationId
        self.chatKind = chatKind
        self.name = name
        self.displayName = displayName
        self.isMemoryFilingEnabled = isMemoryFilingEnabled
        self.lastMessageAt = lastMessageAt
        self.readerConversationId = readerConversationId
        self.readerNotificationLevel = readerNotificationLevel
        self.isReaderAdmin = isReaderAdmin
        self.isReaderMember = isReaderMember
        self.readerUnreadMessageCount = readerUnreadMessageCount
        self.readerLastReadMessageId = readerLastReadMessageId
        self.lastMessageExcerpt = lastMessageExcerpt
        self.lastMessageAuthorName = lastMessageAuthorName
        self.members = members
    }

    public var isGroup: Bool { chatKind == "group" }
    public var title: String { (displayName ?? name ?? "").isEmpty ? "Chat" : (displayName ?? name ?? "") }
    public var unreadCount: Int { Int(readerUnreadMessageCount ?? 0) }
    public var canWrite: Bool { isReaderMember != false }
    public var lastActivity: Date? { PortalDate.parse(lastMessageAt) }
    public var currentMembers: [ChatMember] { (members ?? []).filter(\.isPresent) }
}

/// ChatCandidate is a person the caller may start a chat with.
public struct ChatCandidate: Codable, Equatable, Identifiable, Sendable {
    public let userId: String
    public let userName: String?
    public let email: String?
    public let organizationId: String?
    public let organizationName: String?
    public let isMujinUser: Bool?
    public var id: String { userId }

    public init(userId: String, userName: String? = nil, email: String? = nil, organizationId: String? = nil, organizationName: String? = nil, isMujinUser: Bool? = nil) {
        self.userId = userId
        self.userName = userName
        self.email = email
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.isMujinUser = isMujinUser
    }

    public var shownName: String { (userName ?? "").isEmpty ? (email ?? "") : userName! }
}

public enum ChatRules {
    public static let minimumGroupSize = 3
    public static let maximumGroupSize = 50
    public static let maximumMessageCharacters = 16_000

    /// Whether a group of `selected` people plus the caller may be made.
    public static func canCreateGroup(selectedCount: Int, name: String) -> Bool {
        let size = selectedCount + 1
        return size >= minimumGroupSize && size <= maximumGroupSize && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Candidates grouped by organization, for the picker a Mujin user sees:
    /// the staff first, then each customer organization by name.
    public static func groupedByOrganization(_ candidates: [ChatCandidate]) -> [(organization: String, people: [ChatCandidate])] {
        var order: [String] = []
        var groups: [String: [ChatCandidate]] = [:]
        for candidate in candidates.sorted(by: { ($0.shownName).localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }) {
            let name = candidate.organizationName ?? ""
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(candidate)
        }
        let staffNames = Set(candidates.filter { $0.isMujinUser == true }.map { $0.organizationName ?? "" })
        let sorted = order.sorted { first, second in
            let firstStaff = staffNames.contains(first), secondStaff = staffNames.contains(second)
            if firstStaff != secondStaff { return firstStaff }
            return first.localizedCaseInsensitiveCompare(second) == .orderedAscending
        }
        return sorted.map { ($0, groups[$0] ?? []) }
    }

    /// Whether a message addresses the assistant: `@assistant`, any case, at a word boundary.
    public static func isAddressingAssistant(_ text: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: #"(^|[^A-Za-z0-9_])@assistant(?![A-Za-z0-9_])"#, options: [.caseInsensitive]) else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// TypingThrottle spaces the typing signal: at most one every three seconds.
public struct TypingThrottle: Sendable {
    public static let interval: TimeInterval = 3
    private var lastSentAt: Date?

    public init() {}

    public mutating func shouldSend(now: Date = Date()) -> Bool {
        if let lastSentAt, now.timeIntervalSince(lastSentAt) < Self.interval { return false }
        lastSentAt = now
        return true
    }
}

/// LinkPreviewCard is a card under a message that holds a link.
public struct LinkPreviewCard: Codable, Equatable, Identifiable, Sendable {
    public let urlHash: String
    public let url: String?
    public let finalUrl: String?
    /// `external`, or a Portal resource: ticket, controller, virtual_controller, site, incident, page, release.
    public let linkKind: String?
    public let resourceId: String?
    public let title: String?
    public let description: String?
    public let siteName: String?
    public let statusText: String?
    /// For a Portal resource, where it opens on the server.
    public let path: String?
    /// A path on the Portal host for the card's picture.
    public let imageUrl: String?
    public var id: String { urlHash }
    public var isExternal: Bool { (linkKind ?? "external") == "external" }
}

public struct MessagePreviews: Codable, Equatable, Sendable {
    public let messageId: String
    public let isPending: Bool?
    public let linkPreviews: [LinkPreviewCard]?
}

public enum LinkPreviewRules {
    public static let pendingRetryInterval: TimeInterval = 3
    public static let maximumRetries = 20
    public static let maximumMessagesPerRequest = 50

    /// Whether a message's text holds a link worth asking about: a web
    /// address or a Portal path such as `/ticket/42`.
    public static func mayHoldLink(_ text: String) -> Bool {
        if text.contains("http://") || text.contains("https://") { return true }
        guard let expression = try? NSRegularExpression(
            pattern: #"(^|\s)/(ticket|site|controller|virtual-controller|virtualcontroller|incident|page|release)/[^\s]+"#)
        else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// ChatMessage is one message said in a room, ready to draw.
public struct ChatMessage: Equatable, Identifiable, Sendable {
    public let id: String
    public let authorUserId: String?
    public let authorName: String?
    public let authorOrganizationName: String?
    public let isAssistant: Bool
    public let onBehalfOfUserName: String?
    public let text: String
    public let createdAt: String?
    public let isEdited: Bool
    public let isDeleted: Bool
    public let replyToMessageId: String?
    public let replyToExcerpt: String?
    public let replyToAuthorName: String?
    public let isAddressingAssistant: Bool
    public let hasPreviewsRemoved: Bool

    public init(_ message: ConversationMessage) {
        id = message.id
        authorUserId = message.authorUserId
        authorName = message.authorName
        authorOrganizationName = message.authorOrganizationName
        isAssistant = message.role == "assistant"
        onBehalfOfUserName = message.onBehalfOfUserName
        text = Transcript.text(of: message.content)
        createdAt = message.createdAt
        isEdited = !(message.editedAt ?? "").isEmpty
        isDeleted = !(message.deletedAt ?? "").isEmpty
        replyToMessageId = message.replyToMessageId
        replyToExcerpt = message.replyToExcerpt
        replyToAuthorName = message.replyToAuthorName
        isAddressingAssistant = message.isAddressingAssistant ?? false
        hasPreviewsRemoved = !(message.linkPreviewsRemovedAt ?? "").isEmpty
    }

    public var date: Date? { PortalDate.parse(createdAt) }
    public var isReply: Bool { !(replyToMessageId ?? "").isEmpty }
    /// A reply whose quoted message was said before the person joined has no excerpt.
    public var hasQuotedText: Bool { !(replyToExcerpt ?? "").isEmpty }
}

/// What the screen must do after an event the timeline cannot settle itself.
public enum ChatEffect: Equatable, Sendable {
    case none
    /// Members changed: read the chat again.
    case refetchChat
    /// A message's link previews changed: read them again.
    case refetchPreviews(messageId: String)
    /// A message arrived from someone else.
    case received(messageId: String)
}

/// ChatTimeline is the messages of one chat, kept current by its events.
public struct ChatTimeline: Equatable, Sendable {
    /// How long a typing signal shows.
    public static let typingDuration: TimeInterval = 6

    public private(set) var messages: [ChatMessage] = []
    private var persistedReactions: [String: [Reaction]] = [:]
    private var foldedReactions: [String: [Reaction]] = [:]
    private var typingAt: [String: Date] = [:]
    private var typingNames: [String: String] = [:]
    private var isAssistantTypingAt: Date?
    public private(set) var readMarks: [String: String] = [:]

    public init() {}

    /// Replaces the history. Only messages said in the room are kept: the
    /// person's private tool rows are not part of what the room reads.
    public mutating func load(_ rows: [ConversationMessage]) {
        let shared = rows.filter { $0.isChatMessage == true && ($0.role == "user" || $0.role == "assistant") }
        messages = shared.map(ChatMessage.init)
        persistedReactions = [:]
        for row in shared where !(row.reactions ?? []).isEmpty { persistedReactions[row.id] = row.reactions }
    }

    public func reactions(for messageId: String) -> [Reaction] {
        foldedReactions[messageId] ?? persistedReactions[messageId] ?? []
    }

    public mutating func setReactions(_ reactions: [Reaction], for messageId: String) {
        foldedReactions[messageId] = reactions
    }

    public mutating func setReadMarks(_ marks: [String: String]) { readMarks = marks }

    /// How many other people have read up to and including a message.
    public func readerCount(of messageId: String, excluding userId: String) -> Int {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return 0 }
        return readMarks.filter { key, mark in
            guard key != userId, let markIndex = messages.firstIndex(where: { $0.id == mark }) else { return false }
            return markIndex >= index
        }.count
    }

    public mutating func apply(_ event: ConversationEvent, now: Date = Date()) -> ChatEffect {
        guard let chat = event.chat else { return .none }
        switch ConversationEvent.Kind(rawValue: chat.type ?? event.type) {
        case .chatSaid, .chatEdited:
            guard let row = chat.message else { return .none }
            let message = ChatMessage(row)
            if !(row.reactions ?? []).isEmpty { persistedReactions[row.id] = row.reactions }
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
                return .none
            }
            messages.append(message)
            typingAt[message.authorUserId ?? ""] = nil
            return .received(messageId: message.id)
        case .chatDeleted:
            guard let id = chat.messageId, let index = messages.firstIndex(where: { $0.id == id }) else { return .none }
            let old = messages[index]
            messages[index] = ChatMessage(
                ConversationMessage(
                    id: old.id, role: old.isAssistant ? "assistant" : "user", content: .string(""), createdAt: old.createdAt, isChatMessage: true,
                    authorUserId: old.authorUserId, authorName: old.authorName, authorOrganizationName: old.authorOrganizationName,
                    deletedAt: "deleted"))
            return .none
        case .chatReacted:
            guard let id = chat.messageId else { return .none }
            let change = Reaction(emoji: chat.reactionEmoji ?? "", reactorKind: "user", reactorUserId: chat.actorUserId)
            foldedReactions[id] = Reaction.folding(change, into: reactions(for: id))
            return .none
        case .chatMembers:
            return .refetchChat
        case .chatTyping:
            if chat.isActorAssistant == true {
                isAssistantTypingAt = now
            } else if let actor = chat.actorUserId, !actor.isEmpty {
                typingAt[actor] = now
                typingNames[actor] = chat.actorUserName ?? ""
            }
            return .none
        case .chatRead:
            if let actor = chat.actorUserId, let mark = chat.lastReadMessageId, !mark.isEmpty { readMarks[actor] = mark }
            return .none
        case .chatLinkPreview:
            guard let id = chat.messageId else { return .none }
            return .refetchPreviews(messageId: id)
        default:
            return .none
        }
    }

    /// Who is typing now, other than the person themself.
    public func peopleTyping(now: Date = Date(), excluding userId: String) -> [String] {
        typingAt.filter { $0.key != userId && now.timeIntervalSince($0.value) < Self.typingDuration }
            .map { typingNames[$0.key] ?? "" }.filter { !$0.isEmpty }.sorted()
    }

    /// Whether the assistant is answering for someone else in the room. The
    /// person's own turn shows its own working indicator, so it is skipped then.
    public func isAssistantAnswering(now: Date = Date(), isOwnTurnRunning: Bool) -> Bool {
        guard !isOwnTurnRunning, let isAssistantTypingAt else { return false }
        return now.timeIntervalSince(isAssistantTypingAt) < Self.typingDuration
    }
}

extension Documents {
    static let chatRoomFields = """
        id organizationId chatKind name displayName isMemoryFilingEnabled lastMessageAt readerConversationId readerNotificationLevel isReaderAdmin
        isReaderMember readerUnreadMessageCount readerLastReadMessageId lastMessageExcerpt lastMessageAuthorName
        members { id userId userName organizationId organizationName isMujinUser isAdmin lastReadMessageId leftAt notificationLevel }
        """

    public static let listChats = """
        query ListConversations($search: String, $conversationKind: ConversationKind, $options: ListOptionsInput) {
          ListConversations(search: $search, conversationKind: $conversationKind, options: $options) {
            conversations { \(conversationFields) chat { \(chatRoomFields) } }
            meta { totalCount }
          }
        }
        """

    public static let getChat = "query GetChat($chatId: String) { GetChat(chatId: $chatId) { \(chatRoomFields) } }"

    public static let listChatCandidates = """
        query ListChatCandidates($search: String, $organizationId: String) {
          ListChatCandidates(search: $search, organizationId: $organizationId) { userId userName email organizationId organizationName isMujinUser }
        }
        """

    public static let startDirectChat = """
        mutation StartDirectChat($userId: String) {
          StartDirectChat(userId: $userId) { chat { \(chatRoomFields) } conversation { id } }
        }
        """

    public static let createGroupChat = """
        mutation CreateGroupChat($name: String, $userIds: [String]) {
          CreateGroupChat(name: $name, userIds: $userIds) { chat { \(chatRoomFields) } conversation { id } }
        }
        """

    public static let addChatMembers = """
        mutation AddChatMembers($chatId: String, $userIds: [String]) { AddChatMembers(chatId: $chatId, userIds: $userIds) { chat { \(chatRoomFields) } } }
        """

    public static let removeChatMember = """
        mutation RemoveChatMember($chatId: String, $userId: String) { RemoveChatMember(chatId: $chatId, userId: $userId) { chat { \(chatRoomFields) } } }
        """

    public static let renameChat = """
        mutation RenameChat($chatId: String, $name: String) { RenameChat(chatId: $chatId, name: $name) { chat { \(chatRoomFields) } } }
        """

    public static let setChatMemberAdmin = """
        mutation SetChatMemberAdmin($chatId: String, $userId: String, $isAdmin: Boolean) {
          SetChatMemberAdmin(chatId: $chatId, userId: $userId, isAdmin: $isAdmin) { chat { \(chatRoomFields) } }
        }
        """

    public static let setChatNotificationLevel = """
        mutation SetChatNotificationLevel($chatId: String, $notificationLevel: ChatNotificationLevel) {
          SetChatNotificationLevel(chatId: $chatId, notificationLevel: $notificationLevel) { chat { \(chatRoomFields) } }
        }
        """

    public static let setChatMemoryFiling = """
        mutation SetChatMemoryFiling($chatId: String, $isEnabled: Boolean) {
          SetChatMemoryFiling(chatId: $chatId, isEnabled: $isEnabled) { chat { \(chatRoomFields) } }
        }
        """

    public static let sendChatMessage = """
        mutation SendMessage($conversationId: String!, $message: String!, $replyToMessageId: String, $surface: ConversationSurface) {
          SendMessage(conversationId: $conversationId, message: $message, replyToMessageId: $replyToMessageId, surface: $surface) {
            runId
            message { id role content createdAt \(chatMessageFields) }
          }
        }
        """

    public static let editChatMessage = """
        mutation EditChatMessage($chatId: String, $messageId: String, $text: String) {
          EditChatMessage(chatId: $chatId, messageId: $messageId, text: $text) { message { id role content createdAt \(chatMessageFields) } }
        }
        """

    public static let deleteChatMessage = "mutation DeleteChatMessage($chatId: String, $messageId: String) { DeleteChatMessage(chatId: $chatId, messageId: $messageId) }"
    public static let markChatRead = "mutation MarkChatRead($chatId: String, $messageId: String) { MarkChatRead(chatId: $chatId, messageId: $messageId) }"
    public static let setChatTyping = "mutation SetChatTyping($chatId: String) { SetChatTyping(chatId: $chatId) }"

    public static let listMessageLinkPreviews = """
        query ListMessageLinkPreviews($conversationId: String, $messageIds: [String]) {
          ListMessageLinkPreviews(conversationId: $conversationId, messageIds: $messageIds) {
            messageId isPending
            linkPreviews { urlHash url finalUrl linkKind resourceId title description siteName statusText path imageUrl }
          }
        }
        """

    public static let removeMessageLinkPreviews = """
        mutation RemoveMessageLinkPreviews($conversationId: String, $messageId: String) {
          RemoveMessageLinkPreviews(conversationId: $conversationId, messageId: $messageId)
        }
        """

    static var chatDocuments: [String] {
        [
            listChats, getChat, listChatCandidates, startDirectChat, createGroupChat, addChatMembers, removeChatMember, renameChat, setChatMemberAdmin,
            setChatNotificationLevel, setChatMemoryFiling, sendChatMessage, editChatMessage, deleteChatMessage, markChatRead, setChatTyping,
            listMessageLinkPreviews, removeMessageLinkPreviews,
        ]
    }
}

extension Connection {
    /// The person's chats, the most recently active first.
    public func chats(search: String = "") async throws -> [ConversationSummary] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let conversations: [ConversationSummary]? }
            let ListConversations: List?
        }
        var variables: [String: JSONValue] = ["conversationKind": .string("chat"), "options": .object(["first": .number(200)])]
        if !search.isEmpty { variables["search"] = .string(search) }
        let rows = try await execute(Documents.listChats, variables: variables, as: Answer.self).ListConversations?.conversations ?? []
        return rows.filter { $0.chat != nil && $0.archivedAt == nil }.sorted {
            ($0.chat?.lastActivity ?? $0.lastActivity ?? .distantPast) > ($1.chat?.lastActivity ?? $1.lastActivity ?? .distantPast)
        }
    }

    public func chat(id: String) async throws -> ChatRoom {
        struct Answer: Decodable, Sendable { let GetChat: ChatRoom? }
        guard let room = try await execute(Documents.getChat, variables: ["chatId": .string(id)], as: Answer.self).GetChat else {
            throw PortalError.refused("Chat not found.")
        }
        return room
    }

    public func chatCandidates(search: String = "", organizationId: String? = nil) async throws -> [ChatCandidate] {
        struct Answer: Decodable, Sendable { let ListChatCandidates: [ChatCandidate]? }
        var variables: [String: JSONValue] = [:]
        if !search.isEmpty { variables["search"] = .string(search) }
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        return try await execute(Documents.listChatCandidates, variables: variables, as: Answer.self).ListChatCandidates ?? []
    }

    /// Starts (or finds) the direct chat with a person and returns its conversation id.
    public func startDirectChat(userId: String) async throws -> String {
        struct Answer: Decodable, Sendable {
            struct Started: Decodable, Sendable {
                struct Conversation: Decodable, Sendable { let id: String }
                let conversation: Conversation?
            }
            let StartDirectChat: Started?
        }
        guard let id = try await execute(Documents.startDirectChat, variables: ["userId": .string(userId)], as: Answer.self).StartDirectChat?.conversation?.id
        else { throw PortalError.unreadableAnswer }
        return id
    }

    public func createGroupChat(name: String, userIds: [String]) async throws -> String {
        struct Answer: Decodable, Sendable {
            struct Created: Decodable, Sendable {
                struct Conversation: Decodable, Sendable { let id: String }
                let conversation: Conversation?
            }
            let CreateGroupChat: Created?
        }
        let variables: [String: JSONValue] = ["name": .string(name), "userIds": .array(userIds.map { .string($0) })]
        guard let id = try await execute(Documents.createGroupChat, variables: variables, as: Answer.self).CreateGroupChat?.conversation?.id
        else { throw PortalError.unreadableAnswer }
        return id
    }

    /// One of the member and setting mutations; each returns the chat afterwards.
    private func changeChat(_ document: String, field: String, variables: [String: JSONValue]) async throws -> ChatRoom {
        struct Holder: Decodable, Sendable { let chat: ChatRoom? }
        let answer = try await execute(document, variables: variables, as: [String: Holder].self)
        guard let room = answer[field]?.chat else { throw PortalError.unreadableAnswer }
        return room
    }

    public func addChatMembers(chatId: String, userIds: [String]) async throws -> ChatRoom {
        try await changeChat(Documents.addChatMembers, field: "AddChatMembers", variables: ["chatId": .string(chatId), "userIds": .array(userIds.map { .string($0) })])
    }

    /// Removes a member; with no `userId` the person leaves.
    public func removeChatMember(chatId: String, userId: String? = nil) async throws -> ChatRoom {
        var variables: [String: JSONValue] = ["chatId": .string(chatId)]
        if let userId { variables["userId"] = .string(userId) }
        return try await changeChat(Documents.removeChatMember, field: "RemoveChatMember", variables: variables)
    }

    public func renameChat(chatId: String, name: String) async throws -> ChatRoom {
        try await changeChat(Documents.renameChat, field: "RenameChat", variables: ["chatId": .string(chatId), "name": .string(name)])
    }

    public func setChatMemberAdmin(chatId: String, userId: String, isAdmin: Bool) async throws -> ChatRoom {
        try await changeChat(
            Documents.setChatMemberAdmin, field: "SetChatMemberAdmin",
            variables: ["chatId": .string(chatId), "userId": .string(userId), "isAdmin": .bool(isAdmin)])
    }

    public func setChatNotificationLevel(chatId: String, level: String) async throws -> ChatRoom {
        try await changeChat(
            Documents.setChatNotificationLevel, field: "SetChatNotificationLevel",
            variables: ["chatId": .string(chatId), "notificationLevel": .string(level)])
    }

    public func setChatMemoryFiling(chatId: String, isEnabled: Bool) async throws -> ChatRoom {
        try await changeChat(Documents.setChatMemoryFiling, field: "SetChatMemoryFiling", variables: ["chatId": .string(chatId), "isEnabled": .bool(isEnabled)])
    }

    /// Says something to the room. The run id is empty unless the message
    /// addressed the assistant. No `viewing` or `voice` goes out in a chat.
    public func sendChatMessage(conversationId: String, text: String, replyToMessageId: String? = nil) async throws -> (runId: String, message: ConversationMessage?) {
        struct Answer: Decodable, Sendable {
            struct Sent: Decodable, Sendable {
                let runId: String?
                let message: ConversationMessage?
            }
            let SendMessage: Sent
        }
        var variables: [String: JSONValue] = ["conversationId": .string(conversationId), "message": .string(text), "surface": .string("ios")]
        if let replyToMessageId, !replyToMessageId.isEmpty { variables["replyToMessageId"] = .string(replyToMessageId) }
        let sent = try await execute(Documents.sendChatMessage, variables: variables, as: Answer.self).SendMessage
        return (sent.runId ?? "", sent.message)
    }

    public func editChatMessage(chatId: String, messageId: String, text: String) async throws {
        _ = try await execute(Documents.editChatMessage, variables: ["chatId": .string(chatId), "messageId": .string(messageId), "text": .string(text)], as: JSONValue.self)
    }

    public func deleteChatMessage(chatId: String, messageId: String) async throws {
        _ = try await execute(Documents.deleteChatMessage, variables: ["chatId": .string(chatId), "messageId": .string(messageId)], as: JSONValue.self)
    }

    public func markChatRead(chatId: String, messageId: String) async throws {
        _ = try await execute(Documents.markChatRead, variables: ["chatId": .string(chatId), "messageId": .string(messageId)], as: JSONValue.self)
    }

    public func setChatTyping(chatId: String) async throws {
        _ = try await execute(Documents.setChatTyping, variables: ["chatId": .string(chatId)], as: JSONValue.self)
    }

    /// The cards under messages, at most 50 messages at a time.
    public func linkPreviews(conversationId: String, messageIds: [String]) async throws -> [MessagePreviews] {
        struct Answer: Decodable, Sendable { let ListMessageLinkPreviews: [MessagePreviews]? }
        let ids = Array(messageIds.prefix(LinkPreviewRules.maximumMessagesPerRequest))
        let variables: [String: JSONValue] = ["conversationId": .string(conversationId), "messageIds": .array(ids.map { .string($0) })]
        return try await execute(Documents.listMessageLinkPreviews, variables: variables, as: Answer.self).ListMessageLinkPreviews ?? []
    }

    public func removeLinkPreviews(conversationId: String, messageId: String) async throws {
        _ = try await execute(Documents.removeMessageLinkPreviews, variables: ["conversationId": .string(conversationId), "messageId": .string(messageId)], as: JSONValue.self)
    }
}
