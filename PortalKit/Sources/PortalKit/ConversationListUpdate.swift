import Foundation

/// ConversationListUpdate changes a list of conversations from what the app
/// already knows, so the list does not wait for a full read: a conversation the
/// person just started, and the title the server gives it afterwards.
public enum ConversationListUpdate {
    static let titleMaxWords = 8
    static let titleMaxCharacters = 60

    /// The title the server gives a conversation from its first message until its own summary
    /// replaces it: the first eight words on one line, cut at 60 characters, with an ellipsis when cut.
    public static func placeholderTitle(for text: String) -> String? {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        var isCut = false
        if words.count > titleMaxWords {
            words = Array(words.prefix(titleMaxWords))
            isCut = true
        }
        var title = words.joined(separator: " ")
        if title.count > titleMaxCharacters {
            title = String(title.prefix(titleMaxCharacters - 1)).trimmingCharacters(in: .whitespaces)
            isCut = true
        }
        return isCut ? title + "…" : title
    }

    /// The row for a conversation with the assistant that was just started with `text`.
    public static func startedRow(id: String, agentId: String? = nil, text: String, userId: String? = nil, now: Date = Date()) -> ConversationSummary {
        let stamp = ISO8601DateFormatter().string(from: now)
        return ConversationSummary(
            id: id, agentId: agentId, title: placeholderTitle(for: text), lastMessageAt: stamp, createdAt: stamp, modifiedAt: stamp,
            conversationKind: "assistant", userId: userId, lastMessageExcerpt: text)
    }

    /// The row at the head of the list, replacing any row with the same id.
    public static func inserting(_ row: ConversationSummary, into rows: [ConversationSummary]) -> [ConversationSummary] {
        [row] + rows.filter { $0.id != row.id }
    }

    /// The rows with one conversation's title changed. A title that is empty changes nothing.
    public static func retitled(_ rows: [ConversationSummary], id: String, title: String?) -> [ConversationSummary] {
        guard let title, !title.isEmpty else { return rows }
        return rows.map { row in row.id == id ? row.withTitle(title) : row }
    }

    /// What the server listed, plus the conversations started here that it has not listed yet (a read
    /// from a replica can be a moment behind). A listed row that still lacks a title or a last message
    /// takes them from the started row.
    public static func merging(read: [ConversationSummary], started: [ConversationSummary]) -> [ConversationSummary] {
        let startedById = Dictionary(started.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rows = read.map { row -> ConversationSummary in
            guard let local = startedById[row.id] else { return row }
            return row.filling(from: local)
        }
        let listedIds = Set(read.map(\.id))
        rows.append(contentsOf: started.filter { !listedIds.contains($0.id) })
        return rows
    }
}

extension ConversationSummary {
    func withTitle(_ title: String) -> ConversationSummary {
        ConversationSummary(
            id: id, agentId: agentId, title: title, summary: summary, lastMessageAt: lastMessageAt, activeRunId: activeRunId, archivedAt: archivedAt,
            createdAt: createdAt, modifiedAt: modifiedAt, isTitleCustom: isTitleCustom, conversationKind: conversationKind, chatId: chatId, chat: chat,
            userId: userId, hasRunningBackgroundWork: hasRunningBackgroundWork, lastMessageExcerpt: lastMessageExcerpt, isMain: isMain)
    }

    func filling(from local: ConversationSummary) -> ConversationSummary {
        let needsTitle = (title ?? "").isEmpty && !(local.title ?? "").isEmpty
        let needsLastMessage = (lastMessageAt ?? "").isEmpty && !(local.lastMessageAt ?? "").isEmpty
        guard needsTitle || needsLastMessage else { return self }
        return ConversationSummary(
            id: id, agentId: agentId, title: needsTitle ? local.title : title, summary: summary,
            lastMessageAt: needsLastMessage ? local.lastMessageAt : lastMessageAt, activeRunId: activeRunId, archivedAt: archivedAt,
            createdAt: createdAt, modifiedAt: modifiedAt, isTitleCustom: isTitleCustom, conversationKind: conversationKind, chatId: chatId, chat: chat,
            userId: userId, hasRunningBackgroundWork: hasRunningBackgroundWork, lastMessageExcerpt: lastMessageExcerpt ?? local.lastMessageExcerpt, isMain: isMain)
    }
}
