import Foundation

extension Documents {
    static let reactionFields = "id messageId reactorKind reactorUserId emoji isAcknowledgment createdAt"

    public static let countMessages = """
        query CountConversationMessages($conversationId: String) {
          CountConversationMessages(conversationId: $conversationId) { messageCount }
        }
        """

    public static let renameConversation = """
        mutation RenameConversation($conversationId: String, $title: String) {
          RenameConversation(conversationId: $conversationId, title: $title) { conversation { id title isTitleCustom } }
        }
        """

    public static let reactToMessage = """
        mutation ReactToConversationMessage($conversationId: String, $messageId: String, $emoji: String) {
          ReactToConversationMessage(conversationId: $conversationId, messageId: $messageId, emoji: $emoji) {
            message { id conversationId reactions { \(reactionFields) } }
          }
        }
        """

    public static let listWaiting = """
        query ListConversationWaiting($shouldIncludeOthers: Boolean) {
          ListConversationWaiting(shouldIncludeOthers: $shouldIncludeOthers) {
            conversationId organizationId ownerUserId conversationTitle waitingKind interactionId promptText toolName toolRisk askedAt expiresAt
          }
        }
        """

    static var assistantDocuments: [String] { [countMessages, renameConversation, reactToMessage, listWaiting] }
}
