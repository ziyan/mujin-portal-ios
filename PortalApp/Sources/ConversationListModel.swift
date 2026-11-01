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

    init(account: Account, connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.account = account
        self.connection = connection
        self.onError = onError
    }

    func search(_ text: String) async {
        searchText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await load()
    }

    private var cacheKey: CacheKey { CacheKey(accountKey: account.accountKey, name: "conversations", variables: searchText) }

    func load(force: Bool = false) async {
        if let cache, let held = cache.hit(cacheKey, as: [ConversationSummary].self) {
            conversations = ConversationOrdering.ordered(held.value.filter { $0.archivedAt == nil && (!$0.isEmptyAssistantConversation || $0.id == openConversationId) })
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
