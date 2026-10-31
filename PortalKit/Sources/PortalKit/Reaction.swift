import Foundation

/// Reaction is one emoji a reactor put on a message. A message has at most
/// one reaction from the assistant and one from each person.
public struct Reaction: Codable, Equatable, Identifiable, Sendable {
    public let emoji: String
    /// `user` or `assistant`.
    public let reactorKind: String
    public let reactorUserId: String?
    /// True for the emoji the server adds when a message arrives. It is drawn like any other.
    public let isAcknowledgment: Bool?
    public let id: String?
    public let messageId: String?

    public init(
        emoji: String, reactorKind: String, reactorUserId: String? = nil, isAcknowledgment: Bool? = nil, id: String? = nil,
        messageId: String? = nil
    ) {
        self.emoji = emoji
        self.reactorKind = reactorKind
        self.reactorUserId = reactorUserId
        self.isAcknowledgment = isAcknowledgment
        self.id = id
        self.messageId = messageId
    }

    public var isAssistant: Bool { reactorKind == "assistant" }

    func isFromSameReactor(as other: Reaction) -> Bool {
        guard reactorKind == other.reactorKind else { return false }
        return isAssistant || (reactorUserId ?? "") == (other.reactorUserId ?? "")
    }

    /// Folds one change into a message's reactions: the same reactor's
    /// reaction is replaced in place, an empty emoji removes it, and a new
    /// reactor's is appended.
    public static func folding(_ change: Reaction, into existing: [Reaction]) -> [Reaction] {
        if change.emoji.isEmpty { return existing.filter { !$0.isFromSameReactor(as: change) } }
        if existing.contains(where: { $0.isFromSameReactor(as: change) }) {
            return existing.map { $0.isFromSameReactor(as: change) ? change : $0 }
        }
        return existing + [change]
    }
}

/// ReactionSummary is one emoji on a message with how many reactors chose it.
public struct ReactionSummary: Equatable, Identifiable, Sendable {
    public let emoji: String
    public let count: Int
    public let isMine: Bool
    public let isFromAssistant: Bool
    public var id: String { emoji }
}

public enum Reactions {
    /// The emoji the long press offers, as the web does.
    public static let palette = ["\u{1F44D}", "\u{1F44E}", "\u{2764}\u{FE0F}", "\u{1F602}", "\u{1F389}", "\u{1F64F}"]

    /// The reactions grouped by emoji, in the order the emoji first appeared.
    public static func summaries(_ reactions: [Reaction], currentUserId: String) -> [ReactionSummary] {
        var order: [String] = []
        for reaction in reactions where !order.contains(reaction.emoji) { order.append(reaction.emoji) }
        return order.map { emoji in
            let matching = reactions.filter { $0.emoji == emoji }
            return ReactionSummary(
                emoji: emoji, count: matching.count,
                isMine: matching.contains { !$0.isAssistant && $0.reactorUserId == currentUserId },
                isFromAssistant: matching.contains(where: \.isAssistant))
        }
    }

    /// What to send when the person picks `chosen`: picking the emoji they
    /// already have takes it back (an empty emoji).
    public static func emojiToSend(chosen: String, in reactions: [Reaction], currentUserId: String) -> String {
        let mine = reactions.first { !$0.isAssistant && $0.reactorUserId == currentUserId }
        return mine?.emoji == chosen ? "" : chosen
    }

    /// Whether Portal accepts this as a reaction: one or two emoji, at most 32 bytes.
    public static func isAcceptable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 2 && trimmed.utf8.count <= 32
    }
}
