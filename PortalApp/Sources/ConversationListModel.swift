import Foundation
import Observation
import PortalKit

/// ConversationListModel loads the signed-in person's conversations.
@MainActor
@Observable
final class ConversationListModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let account: Account
    let connection: Connection
    private(set) var phase = Phase.loading
    private(set) var conversations: [ConversationSummary] = []
    /// What the person searches for; empty lists everything.
    private(set) var searchText = ""
    let onError: @MainActor (Error) -> Void
    /// Whether the server lists chats with people, which sit in the same list.
    var offersChats = false
    /// What was loaded, kept by the session: the list shows at once and is read again only when old.
    var cache: ResponseCache?
    /// The conversation on screen, which stays in the list even while it is empty.
    var openConversationId: String?
    /// Conversations started here that the server may not list yet; each stays until a read lists it.
    private var startedRows: [ConversationSummary] = []

    init(account: Account, connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.account = account
        self.connection = connection
        self.onError = onError
    }

    func search(_ text: String) async {
        searchText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await load()
    }

    /// Started conversations belong to the whole list, not to a search of it.
    private var pendingStartedRows: [ConversationSummary] { searchText.isEmpty ? startedRows : [] }

    private var cacheKey: CacheKey { CacheKey(accountKey: account.accountKey, name: "conversations", variables: searchText) }

    func load(force: Bool = false) async {
        if let cache, let held = cache.hit(cacheKey, as: [ConversationSummary].self) {
            conversations = ConversationOrdering.ordered(ConversationListUpdate.merging(read: held.value, started: pendingStartedRows).filter { $0.archivedAt == nil && (!$0.isEmptyAssistantConversation || $0.id == openConversationId) })
            phase = .loaded
            if held.isFresh && !force { return }
        }
        do {
            let rows: [ConversationSummary]
            if searchText.isEmpty {
                rows = try await connection.conversations(userId: account.userId)
            } else {
                rows = try await connection.conversations(userId: account.userId, search: searchText)
            }
            // Conversations with the assistant and chats with people are one list, newest first.
            var all = rows
            if offersChats { all += (try? await connection.chats(search: searchText)) ?? [] }
            // A conversation just started may not be in a replica's answer yet: it stays listed until one has it.
            let listedById = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let pendingRows = pendingStartedRows
            startedRows.removeAll { listedById[$0.id].map { !$0.isEmptyAssistantConversation } ?? false }
            all = ConversationListUpdate.merging(read: all, started: pendingRows)
            cache?.store(all, for: cacheKey)
            // A conversation nothing was said in is left out, unless it is the one open now.
            conversations = ConversationOrdering.ordered(all.filter { $0.archivedAt == nil && (!$0.isEmptyAssistantConversation || $0.id == openConversationId) })
            phase = .loaded
        } catch {
            onError(error)
            if conversations.isEmpty { phase = .failed(error.userMessage) }
        }
    }

    static func activity(_ conversation: ConversationSummary) -> Date { ConversationOrdering.activity(conversation) }

    func conversation(id: String) -> ConversationSummary? { conversations.first { $0.id == id } }

    /// Lists a conversation with the assistant the person just started, at the top, before the server is asked.
    /// It is put in the held list too, so the list is right when the person comes back to it.
    func didStartAssistantConversation(id: String, text: String) async {
        let row = ConversationListUpdate.startedRow(id: id, text: text, userId: account.userId)
        startedRows.append(row)
        conversations = ConversationListUpdate.inserting(row, into: conversations)
        phase = .loaded
        cache?.update(cacheKey, as: [ConversationSummary].self) { $0 = ConversationListUpdate.inserting(row, into: $0) }
        await load(force: true)
    }

    /// A chat with people needs its room to be drawn, so it is read, again for a moment if a replica is behind.
    func didStartChat(id: String) async {
        for attempt in 0..<4 {
            await load(force: true)
            if conversation(id: id) != nil { return }
            if attempt < 3 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        }
    }

    /// Unread messages across the chats listed.
    var chatUnreadCount: Int { conversations.reduce(0) { $0 + ($1.chat?.unreadCount ?? 0) } }

    /// The person read a chat to its end: the row and the held list show it at once, ahead of the next read.
    func markRead(id: String) {
        conversations = ConversationListUpdate.markedRead(conversations, id: id)
        cache?.update(cacheKey, as: [ConversationSummary].self) { $0 = ConversationListUpdate.markedRead($0, id: id) }
    }

    /// The server gave the conversation a title: the row and the held list take it.
    func retitle(id: String, title: String?) {
        guard let title, !title.isEmpty else { return }
        conversations = ConversationListUpdate.retitled(conversations, id: id, title: title)
        startedRows = ConversationListUpdate.retitled(startedRows, id: id, title: title)
        cache?.update(cacheKey, as: [ConversationSummary].self) { $0 = ConversationListUpdate.retitled($0, id: id, title: title) }
    }

    func archive(_ conversation: ConversationSummary) async {
        let before = conversations
        conversations.removeAll { $0.id == conversation.id }
        do {
            try await connection.archiveConversation(id: conversation.id)
            // The result changes the cached list; it is not read again.
            cache?.update(cacheKey, as: [ConversationSummary].self) { $0.removeAll { $0.id == conversation.id } }
        } catch {
            conversations = before
            onError(error)
        }
    }
}
