import Foundation

extension ServerCapabilities {
    /// Internal notes: staff-only messages in chats a customer reads. A server that takes `isInternal` on SendMessage also gives a
    /// message's `isInternal` and `isAuthorMujinUser`, and a chat's `canPostInternal`.
    public var offersInternalNotes: Bool { sendMessageArgumentNames.contains("isInternal") }
}

extension Documents {
    /// The fields a message adds on a server with internal notes. Sent only to a server that offers them.
    static let internalNoteMessageFields = "isInternal isAuthorMujinUser"

    /// A document with the internal-note fields added to every message's fields and every chat's.
    public static func withInternalNotes(_ document: String) -> String {
        document
            .replacingOccurrences(of: "linkPreviewsRemovedAt", with: "linkPreviewsRemovedAt \(internalNoteMessageFields)")
            .replacingOccurrences(of: "lastMessageExcerpt lastMessageAuthorName", with: "lastMessageExcerpt lastMessageAuthorName canPostInternal")
    }

    /// A document whose messages also say whether the person an assistant answer was given for is Mujin staff.
    public static func withOnBehalfOfStaff(_ document: String) -> String {
        document.replacingOccurrences(of: "onBehalfOfUserName", with: "onBehalfOfUserName isOnBehalfOfMujinUser")
    }

    /// A SendMessage document that also says whether the message is an internal note.
    static func withInternalArgument(_ document: String) -> String {
        document
            .replacingOccurrences(of: "$surface: ConversationSurface", with: "$surface: ConversationSurface, $isInternal: Boolean")
            .replacingOccurrences(of: "surface: $surface", with: "surface: $surface, isInternal: $isInternal")
    }
}

/// InternalNoteRules decides the composer's internal-note lock: whether a send is an internal note, and whether the person may change it.
public enum InternalNoteRules {
    /// Whether the lock is held on: a reply to an internal note, or anything in a thread whose root is one, is internal whatever the
    /// person picks, as the server makes it.
    public static func isForcedOn(threadRoot: ChatMessage?, replyTo: ChatMessage?) -> Bool {
        (threadRoot?.isInternal ?? false) || (replyTo?.isInternal ?? false)
    }

    /// Where the lock starts on a thread: on when the newest message the person can read in it is internal, off elsewhere.
    public static func startsOn(threadMessages: [ChatMessage]) -> Bool {
        threadMessages.last { !$0.isDeleted }?.isInternal ?? false
    }
}
