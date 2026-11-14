import Foundation
import Testing

@testable import PortalKit

/// Internal notes: what a send asks the server, and how the composer's lock starts and holds.
@Suite struct ChatNoteTests {
    func message(_ id: String, isInternal: Bool = false, isDeleted: Bool = false) -> ChatMessage {
        ChatMessage(
            ConversationMessage(
                id: id, role: "user", content: .string("Hello"), createdAt: "2026-03-01T10:00:00Z", isChatMessage: true, authorUserId: "user01",
                deletedAt: isDeleted ? "2026-03-01T10:05:00Z" : nil, isInternal: isInternal))
    }

    @Test func aSendSaysItIsInternalOnlyWhenItIs() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["SendMessage": ["runId": "", "message": NSNull()]] }
        _ = try await connection.sendChatMessage(conversationId: "c1", text: "Hello")
        var body = String(decoding: try #require(transport.requests.last?.httpBody), as: UTF8.self)
        #expect(!body.contains("isInternal"))
        _ = try await connection.sendChatMessage(conversationId: "c1", text: "Only for staff", isInternal: true)
        body = String(decoding: try #require(transport.requests.last?.httpBody), as: UTF8.self)
        #expect(body.contains("isInternal: $isInternal"))
        #expect(sentVariables(try #require(transport.requests.last))["isInternal"] as? Bool == true)
    }

    @Test func aReplyToAnInternalNoteOrInAnInternalThreadIsHeldInternal() {
        #expect(InternalNoteRules.isForcedOn(threadRoot: message("r1", isInternal: true), replyTo: nil))
        #expect(InternalNoteRules.isForcedOn(threadRoot: nil, replyTo: message("m2", isInternal: true)))
        #expect(!InternalNoteRules.isForcedOn(threadRoot: message("r1"), replyTo: message("m2")))
        #expect(!InternalNoteRules.isForcedOn(threadRoot: nil, replyTo: nil))
    }

    @Test func aThreadStartsInternalWhenItsNewestMessageIs() {
        #expect(InternalNoteRules.startsOn(threadMessages: [message("r1"), message("m2", isInternal: true)]))
        #expect(!InternalNoteRules.startsOn(threadMessages: [message("r1", isInternal: true), message("m2")]))
        // A deleted message is not what the person last read.
        #expect(InternalNoteRules.startsOn(threadMessages: [message("m1", isInternal: true), message("m2", isDeleted: true)]))
        #expect(!InternalNoteRules.startsOn(threadMessages: []))
    }

    @Test func theFieldsAreAskedForOnlyOfAServerThatHasThem() async {
        let (connection, _) = scriptedConnection { _, _ in [:] }
        #expect(!(await connection.prepared(Documents.listMessages)).contains("isInternal"))
        await connection.setInternalNotes(true)
        #expect(await connection.prepared(Documents.listMessages).contains("isInternal isAuthorMujinUser"))
        #expect(ServerCapabilities(sendMessageArgumentNames: ["isInternal"]).offersInternalNotes)
        #expect(!ServerCapabilities().offersInternalNotes)
    }

    @Test func anAnswerSaysItWasGivenForStaffOnlyOnAServerThatHasIt() async {
        let (connection, _) = scriptedConnection { _, _ in [:] }
        #expect(!(await connection.prepared(Documents.listMessages)).contains("isOnBehalfOfMujinUser"))
        await connection.setOnBehalfOfStaff(true)
        #expect(await connection.prepared(Documents.listMessages).contains("onBehalfOfUserName isOnBehalfOfMujinUser"))
        #expect(ServerCapabilities(messageFieldNames: ["isOnBehalfOfMujinUser"]).offersOnBehalfOfStaff)
        #expect(!ServerCapabilities().offersOnBehalfOfStaff)
        #expect(ChatMessage(ConversationMessage(id: "m1", role: "assistant", isOnBehalfOfMujinUser: true)).isOnBehalfOfMujinUser)
        #expect(!ChatMessage(ConversationMessage(id: "m2", role: "assistant")).isOnBehalfOfMujinUser)
    }
}
