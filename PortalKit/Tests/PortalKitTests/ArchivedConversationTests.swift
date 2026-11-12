import Foundation
import Testing

@testable import PortalKit

/// Archived chats are a list of their own, asked for only of a server that lists by isForegroundOnly. The chat list never asks for them.
@Suite struct ArchivedConversationTests {
    private func sentQuery(_ request: URLRequest?) -> String {
        let body = request?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        return body["query"] as? String ?? ""
    }

    @Test func theArchivedListAsksForArchivedForegroundConversationsOnly() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            ["ListConversations": ["conversations": [["id": "conversation09", "title": "Old question", "archivedAt": "2026-03-01T10:00:00Z"]]]]
        }
        await connection.setForegroundOnlyLists(true)
        let rows = try await connection.archivedConversations(userId: "user01")
        #expect(rows.map(\.id) == ["conversation09"])
        let query = sentQuery(transport.requests.first)
        #expect(query.contains("ListConversations(isForegroundOnly: true, userId: $userId, archivedOnly: true)"))
    }

    @Test func aServerWithoutForegroundListsIsNotAskedForArchivedChats() async throws {
        let (connection, transport) = scriptedConnection { _, _ in [:] }
        #expect(try await connection.archivedConversations(userId: "user01").isEmpty)
        #expect(transport.requests.isEmpty)
    }

    @Test func theChatListNeverAsksForArchivedChats() {
        #expect(!Documents.listConversations.contains("archivedOnly"))
        #expect(!Documents.listConversations.contains("includeArchived"))
    }

    @Test func restoringTakesTheConversationOutOfTheArchive() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["ArchiveConversation": ["conversation": ["id": "conversation09", "archivedAt": NSNull()]]] }
        try await connection.restoreConversation(id: "conversation09")
        let body = transport.requests.first?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let variables = body["variables"] as? [String: Any] ?? [:]
        #expect(variables["conversationId"] as? String == "conversation09")
        #expect(variables["archived"] as? Bool == false)
    }
}
