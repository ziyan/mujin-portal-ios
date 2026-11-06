import Foundation

/// MessagePermalink is the address of one message, which is what Copy link puts on the pasteboard.
public enum MessagePermalink {
    /// A message of a chat with people: `/chat/<chatId>/<messageId>`.
    public static func chatMessage(server: ServerAddress, chatId: String, messageId: String) -> URL {
        PortalLink.chatMessage(chatId: chatId, messageId: messageId).url(server: server)
    }

    /// A message of a conversation with the assistant: `/agent/<conversationId>#message-<messageId>`.
    public static func assistantMessage(server: ServerAddress, conversationId: String, messageId: String) -> URL {
        let page = server.endpoint("/agent/\(conversationId)")
        guard var components = URLComponents(url: page, resolvingAgainstBaseURL: false) else { return page }
        components.fragment = "message-\(messageId)"
        return components.url ?? page
    }
}

extension ServerCapabilities {
    /// Whether a link to a message can be opened: the server turns a chat and a message into the reader's own conversation.
    public var offersMessageLinks: Bool { offersMutation("OpenChatMessage") }

    /// Whether the past calls of a chat can be listed.
    public var offersChatCallHistory: Bool { offersQuery("ListChatCalls") }
}

extension Documents {
    public static let openChatMessage = """
        mutation OpenChatMessage($chatId: String, $messageId: String) {
          OpenChatMessage(chatId: $chatId, messageId: $messageId) { conversation { id } }
        }
        """

    public static let listChatCalls = """
        query ListChatCalls($chatId: String, $options: ListOptionsInput) {
          ListChatCalls(chatId: $chatId, options: $options) {
            calls {
              id chatId messageId startedByUserName startedAt endedAt endReason durationMS transcriptState recordingCount transcriptSegmentCount
              members { userId userName ringState }
            }
            meta { totalCount }
          }
        }
        """

    static var messageLinkDocuments: [String] { [openChatMessage, listChatCalls] }
}

extension Connection {
    /// The reader's own conversation of a chat, to open it at a message. Throws when the message or the chat is not found.
    public func openChatMessage(chatId: String, messageId: String) async throws -> String {
        struct Answer: Decodable, Sendable {
            struct Opened: Decodable, Sendable {
                struct Conversation: Decodable, Sendable { let id: String? }
                let conversation: Conversation?
            }
            let OpenChatMessage: Opened?
        }
        let answer = try await execute(
            Documents.openChatMessage, variables: ["chatId": .string(chatId), "messageId": .string(messageId)], as: Answer.self)
        guard let id = answer.OpenChatMessage?.conversation?.id, !id.isEmpty else { throw PortalError.refused("Message not found.") }
        return id
    }

    /// A page of the past calls of a chat, newest first as the server orders them, and how many there are in all.
    public func pastChatCalls(chatId: String, first: Int, after: Int = 0) async throws -> (calls: [ChatCall], totalCount: Int) {
        struct Answer: Decodable, Sendable {
            struct Meta: Decodable, Sendable { let totalCount: Int? }
            struct List: Decodable, Sendable {
                let calls: [ChatCall]?
                let meta: Meta?
            }
            let ListChatCalls: List?
        }
        var options: [String: JSONValue] = ["first": .number(Double(first))]
        if after > 0 { options["after"] = .number(Double(after)) }
        let list = try await execute(Documents.listChatCalls, variables: ["chatId": .string(chatId), "options": .object(options)], as: Answer.self).ListChatCalls
        return (list?.calls ?? [], list?.meta?.totalCount ?? list?.calls?.count ?? 0)
    }
}
