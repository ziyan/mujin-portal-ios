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

    init(account: Account, connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.account = account
        self.connection = connection
        self.onError = onError
    }

    func search(_ text: String) async {
        searchText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await load()
    }

    func load() async {
        do {
            let rows: [ConversationSummary]
            if searchText.isEmpty {
                rows = try await connection.conversations(userId: account.userId)
            } else {
                rows = try await connection.conversations(userId: account.userId, search: searchText)
            }
            conversations = rows.filter { $0.archivedAt == nil }
            phase = .loaded
        } catch {
            onError(error)
            if conversations.isEmpty { phase = .failed(error.userMessage) }
        }
    }

    /// Makes a conversation with the main assistant and returns its id.
    func createConversation() async -> String? {
        do {
            let agent = try await connection.mainAgent()
            let created = try await connection.createConversation(agentId: agent.id)
            conversations.insert(created, at: 0)
            return created.id
        } catch {
            onError(error)
            phase = conversations.isEmpty ? .failed(error.userMessage) : phase
            return nil
        }
    }

    func archive(_ conversation: ConversationSummary) async {
        let before = conversations
        conversations.removeAll { $0.id == conversation.id }
        do {
            try await connection.archiveConversation(id: conversation.id)
        } catch {
            conversations = before
            onError(error)
        }
    }
}
