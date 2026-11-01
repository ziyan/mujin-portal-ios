import Foundation

/// CommunicationSender is who a message notification is from, as the system
/// shows it: a name, a picture and, in a group, the group's name. The
/// notification service builds an intent from it so the notification wears
/// the sender's picture.
public struct CommunicationSender: Equatable, Sendable {
    public let displayName: String
    /// What identifies the sender to the system: the user id once known, else the name.
    public let handle: String
    public let userId: String?
    /// The group's name; nil for a direct chat and for the assistant.
    public let groupName: String?
    public let conversationIdentifier: String
    public let isAssistant: Bool
    public let messageText: String

    public init(
        displayName: String, handle: String, userId: String? = nil, groupName: String? = nil, conversationIdentifier: String,
        isAssistant: Bool = false, messageText: String
    ) {
        self.displayName = displayName
        self.handle = handle
        self.userId = userId
        self.groupName = groupName
        self.conversationIdentifier = conversationIdentifier
        self.isAssistant = isAssistant
        self.messageText = messageText
    }

    /// The sender of a push, or nil for a push that is not a message. `assistantName` is what the assistant is called.
    public init?(payload: PushPayload, assistantName: String) {
        switch payload.kind {
        case "chat_message":
            // The alert carries the author, the chat's name and the excerpt, in that order.
            let arguments = payload.alertArguments
            guard arguments.count >= 3, !arguments[0].isEmpty, let chatId = payload.chatId else { return nil }
            let author = arguments[0]
            let chatName = arguments[1]
            // A direct chat is named for the other person, so a name that differs from the author's means a group.
            let isGroup = !chatName.isEmpty && chatName != author
            self.init(
                displayName: author, handle: payload.authorUserId ?? author, userId: payload.authorUserId, groupName: isGroup ? chatName : nil,
                conversationIdentifier: "chat:" + chatId, messageText: arguments[2])
        case "agent_message":
            guard let conversationId = payload.conversationId else { return nil }
            self.init(
                displayName: assistantName, handle: "assistant", conversationIdentifier: conversationId, isAssistant: true,
                messageText: payload.alertArguments.first ?? "")
        default:
            return nil
        }
    }

    /// The sender once the chat's members are known: the member of that name gives the user id, so the picture can be fetched.
    public func resolving(members: [ChatMember]) -> CommunicationSender {
        guard !isAssistant, userId == nil, let member = members.first(where: { $0.userName == displayName }) else { return self }
        return CommunicationSender(
            displayName: displayName, handle: member.userId, userId: member.userId, groupName: groupName,
            conversationIdentifier: conversationIdentifier, isAssistant: false, messageText: messageText)
    }

    /// The picture to fetch, when the sender is a person whose id is known.
    public var avatarSubject: AvatarSubject? {
        userId.map { AvatarSubject(kind: .user, id: $0) }
    }

    /// One or two letters standing for the name, for a sender with no picture.
    public var initials: String {
        String(displayName.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased()
    }
}
