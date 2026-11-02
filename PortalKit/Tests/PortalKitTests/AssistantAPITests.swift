import Foundation
import Testing

@testable import PortalKit

@Suite struct AssistantAPITests {
    @Test func everySendSaysItComesFromTheIosApp() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["SendMessage": ["runId": "run01"]] }
        let runId = try await connection.sendMessage(conversationId: "conversation01", text: "Hello")
        #expect(runId == "run01")
        let variables = sentVariables(transport.requests[0])
        #expect(variables["surface"] as? String == "ios")
        #expect((variables["viewing"] as? [String: Any])?["page"] as? String == "/agent/conversation01")
    }

    @Test func aSendCanNameTheScreenItAsksAbout() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["SendMessage": ["runId": "run01"]] }
        try await connection.sendMessage(conversationId: "conversation01", text: "Why?", viewing: Viewing(kind: "ticket", id: "ticket01", label: "ignored"))
        let viewing = sentVariables(transport.requests[0])["viewing"] as? [String: Any]
        #expect(viewing?["kind"] as? String == "ticket")
        #expect(viewing?["id"] as? String == "ticket01")
        #expect(viewing?["label"] == nil)
    }

    @Test func aReplyGoesOutAsAnIdNeverAsQuotedText() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["SendMessage": ["runId": "run01"]] }
        try await connection.sendMessage(conversationId: "c1", text: "Yes, do that", replyToMessageId: "m7")
        let variables = sentVariables(transport.requests[0])
        #expect(variables["replyToMessageId"] as? String == "m7")
        #expect(variables["message"] as? String == "Yes, do that")
    }

    @Test func aSentReplyKeepsItsQuoteForTheBubble() {
        var transcript = Transcript()
        transcript.load(
            messages: [
                ConversationMessage(
                    id: "m8", role: "user", content: .string("Yes, do that"), replyToMessageId: "m7", replyToExcerpt: "Shall I restart the planner?  \n Tell me.",
                    replyToAuthorName: "Assistant")
            ], questions: [], approvals: [], isRunning: false)
        #expect(transcript.replyQuote(for: "m8")?.messageId == "m7")
        #expect(transcript.replyQuote(for: "m8")?.excerpt == "Shall I restart the planner? Tell me.")
        #expect(transcript.replyQuote(for: "m9") == nil)
    }

    @Test func aQuotedExcerptIsBounded() {
        #expect(ReplyReference(messageId: "m", authorName: "A", excerpt: String(repeating: "word ", count: 100)).excerpt.count <= 200)
    }

    @Test func pagingAsksForTheLatestCountOrThePageBeforeAMessage() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["ListConversationMessages": []] }
        _ = try await connection.messages(conversationId: "conversation01", latestCount: 30)
        _ = try await connection.messages(conversationId: "conversation01", latestCount: 30, beforeMessageId: "m71")
        #expect(sentVariables(transport.requests[0])["latestMessageCount"] as? Int == 30)
        #expect(sentVariables(transport.requests[0])["beforeMessageId"] == nil)
        #expect(sentVariables(transport.requests[1])["beforeMessageId"] as? String == "m71")
    }

    @Test func theMessageCountIsRead() async throws {
        let (connection, _) = scriptedConnection { _, _ in ["CountConversationMessages": ["messageCount": 140]] }
        #expect(try await connection.messageCount(conversationId: "conversation01") == 140)
    }

    @Test func reactingReturnsTheWholeListAfterTheChange() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            [
                "ReactToConversationMessage": [
                    "message": [
                        "id": "m1", "conversationId": "conversation01",
                        "reactions": [["id": "r1", "messageId": "m1", "reactorKind": "user", "reactorUserId": "user01", "emoji": "\u{1F44D}", "isAcknowledgment": false]],
                    ]
                ]
            ]
        }
        let reactions = try await connection.react(conversationId: "conversation01", messageId: "m1", emoji: "\u{1F44D}")
        #expect(reactions.map(\.emoji) == ["\u{1F44D}"])
        #expect(sentVariables(transport.requests[0])["emoji"] as? String == "\u{1F44D}")
    }

    @Test func waitingItemsComeOldestFirstAndCountPerConversation() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "ListConversationWaiting": [
                    ["conversationId": "c2", "waitingKind": "approval", "interactionId": "a1", "promptText": "Restart?", "toolName": "shell", "askedAt": "2026-03-01T10:05:00Z"],
                    ["conversationId": "c1", "waitingKind": "question", "interactionId": "q1", "promptText": "Which site?", "askedAt": "2026-03-01T10:00:00Z"],
                    ["conversationId": "c1", "waitingKind": "question", "interactionId": "q2", "promptText": "Which robot?", "askedAt": "2026-03-01T10:10:00Z"],
                ]
            ]
        }
        let items = try await connection.waiting()
        #expect(items.map(\.interactionId) == ["q1", "a1", "q2"])
        #expect(items.countsByConversation == ["c1": 2, "c2": 1])
        #expect(items[1].isApproval && items[0].isQuestion)
    }

    @Test func renamingSendsTheNewTitle() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["RenameConversation": ["conversation": ["id": "c1", "title": "Pallet counts", "isTitleCustom": true]]] }
        let renamed = try await connection.renameConversation(id: "c1", title: "Pallet counts")
        #expect(renamed?.isTitleCustom == true)
        #expect(sentVariables(transport.requests[0])["title"] as? String == "Pallet counts")
    }

    @Test func searchIsSentToTheServer() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["ListConversations": ["conversations": [], "meta": ["totalCount": 0]]] }
        _ = try await connection.conversations(userId: "user01", search: "pallets")
        #expect(sentVariables(transport.requests[0])["search"] as? String == "pallets")
    }

    @Test func aTurnsEventsDecodeTheNewFields() throws {
        let json = #"{"type":"tool_result","runId":"run01","toolResult":{"toolCallId":"c1","toolName":"sites","result":"ok","toolNote":"3 sites","durationMS":1200}}"#
        let event = try JSONDecoder().decode(ConversationEvent.self, from: Data(json.utf8))
        #expect(event.toolResult?.toolNote == "3 sites")
        #expect(event.toolResult?.durationMS == 1200)
        let retry = try JSONDecoder().decode(ConversationEvent.self, from: Data(#"{"type":"round_retry","roundRetry":{"discardedMessageId":"m1"}}"#.utf8))
        #expect(retry.kind == .roundRetry)
        #expect(ConversationEvent.Kind(rawValue: "reacted") == .reacted)
        #expect(ConversationEvent.Kind(rawValue: "model_switch") == .modelSwitch)
    }

    @Test func aConversationUpdatedEventDecodesAndGivesTheTitleToItsOwnConversationOnly() throws {
        let json = #"{"type":"conversation_updated","conversationUpdated":{"conversationId":"c1","conversationTitle":"Dock door check","isTitleCustom":false}}"#
        let event = try JSONDecoder().decode(ConversationEvent.self, from: Data(json.utf8))
        #expect(event.kind == .conversationUpdated)
        #expect(event.conversationUpdated == .init(conversationId: "c1", conversationTitle: "Dock door check"))
        let announced = event.announcedTitle(for: "c1")
        #expect(announced?.title == "Dock door check")
        #expect(announced?.isCustom == false)
        #expect(event.announcedTitle(for: "c2") == nil)
    }

    @Test func aRenameIsCustomAndAnEmptyTitleOrAnotherEventAnnouncesNothing() {
        let renamed = ConversationEvent(type: "conversation_updated", conversationUpdated: .init(conversationId: "c1", conversationTitle: "Pallet counts", isTitleCustom: true))
        #expect(renamed.announcedTitle(for: "c1")?.isCustom == true)
        let empty = ConversationEvent(type: "conversation_updated", conversationUpdated: .init(conversationId: "c1", conversationTitle: ""))
        #expect(empty.announcedTitle(for: "c1") == nil)
        let other = ConversationEvent(type: "run_complete", conversationUpdated: .init(conversationId: "c1", conversationTitle: "Not an update"))
        #expect(other.announcedTitle(for: "c1") == nil)
    }

    @Test func theAnnouncedTitleRetitlesTheListRow() {
        let rows = [
            ConversationSummary(id: "c1", title: "Check dock door 4", conversationKind: "assistant"),
            ConversationSummary(id: "c2", title: "Other", conversationKind: "assistant"),
        ]
        let event = ConversationEvent(type: "conversation_updated", conversationUpdated: .init(conversationId: "c1", conversationTitle: "Dock door 4 check"))
        let title = event.announcedTitle(for: "c1")?.title
        #expect(ConversationListUpdate.retitled(rows, id: "c1", title: title).map { $0.title } == ["Dock door 4 check", "Other"])
    }
}
