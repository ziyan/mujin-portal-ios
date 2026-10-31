import Foundation
import Testing

@testable import PortalKit

@Suite struct ChatTests {
    func said(_ id: String, author: String = "user02", name: String = "Sam Sample", text: String = "Hello", role: String = "user", edited: Bool = false) -> ConversationMessage {
        ConversationMessage(
            id: id, role: role, content: .string(text), createdAt: "2026-03-01T10:0\(id.suffix(1)):00Z", isChatMessage: true, authorUserId: author, authorName: name,
            editedAt: edited ? "2026-03-01T11:00:00Z" : nil)
    }

    func event(_ type: String, _ chat: ConversationEvent.Chat) -> ConversationEvent { ConversationEvent(type: type, chat: chat) }

    func chatEvent(type: String, messageId: String? = nil, message: ConversationMessage? = nil, actor: String? = nil, emoji: String? = nil, assistant: Bool = false, mark: String? = nil) -> ConversationEvent {
        let data = try! JSONSerialization.data(
            withJSONObject: [
                "type": type, "chatId": "chat01", "messageId": messageId as Any, "actorUserId": actor as Any, "actorUserName": "Sam Sample",
                "isActorAssistant": assistant, "reactionEmoji": emoji as Any, "lastReadMessageId": mark as Any,
            ].compactMapValues { $0 is NSNull ? nil : $0 })
        var chat = try! JSONDecoder().decode(ConversationEvent.Chat.self, from: data)
        if let message {
            let encoded = try! JSONEncoder().encode(message)
            var object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            object["message"] = try! JSONSerialization.jsonObject(with: encoded)
            chat = try! JSONDecoder().decode(ConversationEvent.Chat.self, from: JSONSerialization.data(withJSONObject: object))
        }
        return ConversationEvent(type: type, chat: chat)
    }

    @Test func onlyMessagesSaidInTheRoomAreKept() {
        var timeline = ChatTimeline()
        timeline.load([said("m1"), ConversationMessage(id: "t1", role: "tool", content: .string("x"), isChatMessage: false), said("m2", name: "Assistant", role: "assistant")])
        #expect(timeline.messages.map(\.id) == ["m1", "m2"])
        #expect(timeline.messages[1].isAssistant)
    }

    @Test func aSaidEventAppendsOnceAndAnEditReplaces() {
        var timeline = ChatTimeline()
        let effect710 = timeline.apply(chatEvent(type: "chat_said", message: said("m1")))
        #expect(effect710 == .received(messageId: "m1"))
        let effect148 = timeline.apply(chatEvent(type: "chat_said", message: said("m1")))
        #expect(effect148 == .none)
        #expect(timeline.messages.count == 1)
        _ = timeline.apply(chatEvent(type: "chat_edited", message: said("m1", text: "Hello again", edited: true)))
        #expect(timeline.messages[0].text == "Hello again" && timeline.messages[0].isEdited)
    }

    @Test func aDeletedMessageKeepsItsPlaceWithNoWords() {
        var timeline = ChatTimeline()
        timeline.load([said("m1"), said("m2")])
        _ = timeline.apply(chatEvent(type: "chat_deleted", messageId: "m1"))
        #expect(timeline.messages[0].isDeleted && timeline.messages[0].text.isEmpty)
        #expect(!timeline.messages[1].isDeleted)
    }

    @Test func anyMemberMayReactAndAnEmptyEmojiTakesItBack() {
        var timeline = ChatTimeline()
        timeline.load([said("m1")])
        _ = timeline.apply(chatEvent(type: "chat_reacted", messageId: "m1", actor: "user02", emoji: "\u{1F44D}"))
        _ = timeline.apply(chatEvent(type: "chat_reacted", messageId: "m1", actor: "user03", emoji: "\u{1F44D}"))
        #expect(Reactions.summaries(timeline.reactions(for: "m1"), currentUserId: "user02").first?.count == 2)
        _ = timeline.apply(chatEvent(type: "chat_reacted", messageId: "m1", actor: "user02", emoji: ""))
        #expect(timeline.reactions(for: "m1").count == 1)
    }

    @Test func typingShowsForSixSecondsAndSkipsTheViewer() {
        var timeline = ChatTimeline()
        let now = Date()
        _ = timeline.apply(chatEvent(type: "chat_typing", actor: "user02"), now: now)
        _ = timeline.apply(chatEvent(type: "chat_typing", actor: "user01"), now: now)
        #expect(timeline.peopleTyping(now: now.addingTimeInterval(2), excluding: "user01") == ["Sam Sample"])
        #expect(timeline.peopleTyping(now: now.addingTimeInterval(7), excluding: "user01").isEmpty)
    }

    @Test func theAssistantAnsweringIsHiddenWhileTheViewersOwnTurnRuns() {
        var timeline = ChatTimeline()
        let now = Date()
        _ = timeline.apply(chatEvent(type: "chat_typing", assistant: true), now: now)
        #expect(timeline.isAssistantAnswering(now: now.addingTimeInterval(1), isOwnTurnRunning: false))
        #expect(!timeline.isAssistantAnswering(now: now.addingTimeInterval(1), isOwnTurnRunning: true))
        #expect(!timeline.isAssistantAnswering(now: now.addingTimeInterval(8), isOwnTurnRunning: false))
    }

    @Test func readMarksCountThoseWhoReadUpToAMessage() {
        var timeline = ChatTimeline()
        timeline.load([said("m1"), said("m2"), said("m3")])
        _ = timeline.apply(chatEvent(type: "chat_read", actor: "user02", mark: "m3"))
        _ = timeline.apply(chatEvent(type: "chat_read", actor: "user03", mark: "m1"))
        #expect(timeline.readerCount(of: "m2", excluding: "user01") == 1)
        #expect(timeline.readerCount(of: "m1", excluding: "user01") == 2)
        #expect(timeline.readerCount(of: "m3", excluding: "user02") == 0)
    }

    @Test func memberAndPreviewEventsAskForARefetch() {
        var timeline = ChatTimeline()
        let effect18 = timeline.apply(chatEvent(type: "chat_members"))
        #expect(effect18 == .refetchChat)
        let effect894 = timeline.apply(chatEvent(type: "chat_link_preview", messageId: "m1"))
        #expect(effect894 == .refetchPreviews(messageId: "m1"))
    }

    @Test func aReplyWithoutAnExcerptWasSaidBeforeThePersonJoined() {
        let reply = ChatMessage(ConversationMessage(id: "m2", role: "user", content: .string("Yes"), isChatMessage: true, replyToMessageId: "m0"))
        #expect(reply.isReply && !reply.hasQuotedText)
    }

    @Test func theAssistantIsAddressedByAWordBoundedMention() {
        #expect(ChatRules.isAddressingAssistant("@assistant what is the status?"))
        #expect(ChatRules.isAddressingAssistant("Hey @Assistant, look"))
        #expect(ChatRules.isAddressingAssistant("(@ASSISTANT)"))
        #expect(!ChatRules.isAddressingAssistant("mail me@assistant.example"))
        #expect(!ChatRules.isAddressingAssistant("@assistants"))
        #expect(!ChatRules.isAddressingAssistant("no mention"))
    }

    @Test func aGroupNeedsThreePeopleAndAName() {
        #expect(!ChatRules.canCreateGroup(selectedCount: 1, name: "Pick team"))
        #expect(ChatRules.canCreateGroup(selectedCount: 2, name: "Pick team"))
        #expect(!ChatRules.canCreateGroup(selectedCount: 2, name: "  "))
        #expect(ChatRules.canCreateGroup(selectedCount: 49, name: "Everyone"))
        #expect(!ChatRules.canCreateGroup(selectedCount: 50, name: "Too many"))
    }

    @Test func staffSeeCandidatesGroupedByOrganizationWithStaffFirst() {
        let groups = ChatRules.groupedByOrganization([
            ChatCandidate(userId: "u1", userName: "Robin Demo", organizationName: "Sample Foods"),
            ChatCandidate(userId: "u2", userName: "Sam Sample", organizationName: "Support", isMujinUser: true),
            ChatCandidate(userId: "u3", userName: "Alex Example", organizationName: "Example Logistics"),
            ChatCandidate(userId: "u4", userName: "Ana Support", organizationName: "Support", isMujinUser: true),
        ])
        #expect(groups.map(\.organization) == ["Support", "Example Logistics", "Sample Foods"])
        #expect(groups[0].people.map(\.userId) == ["u4", "u2"])
    }

    @Test func typingIsSignalledAtMostEveryThreeSeconds() {
        var throttle = TypingThrottle()
        let now = Date()
        let first = throttle.shouldSend(now: now)
        let second = throttle.shouldSend(now: now.addingTimeInterval(2))
        let third = throttle.shouldSend(now: now.addingTimeInterval(3.1))
        #expect(first && !second && third)
    }

    @Test func onlyMessagesWithLinksAreAskedAbout() {
        #expect(LinkPreviewRules.mayHoldLink("See https://example.test/page"))
        #expect(LinkPreviewRules.mayHoldLink("Look at /ticket/42 please"))
        #expect(LinkPreviewRules.mayHoldLink("/site/site01"))
        #expect(!LinkPreviewRules.mayHoldLink("no links here, just 12/34"))
        #expect(!LinkPreviewRules.mayHoldLink("a/ticket/42 inside a word"))
    }

    @Test func chatsComeFromConversationsOfKindChatNewestFirst() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            [
                "ListConversations": [
                    "conversations": [
                        ["id": "c1", "chat": ["id": "chat1", "displayName": "Sam Sample", "chatKind": "direct", "lastMessageAt": "2026-03-01T10:00:00Z", "readerUnreadMessageCount": 2]],
                        ["id": "c2", "chat": ["id": "chat2", "displayName": "Pick team", "chatKind": "group", "lastMessageAt": "2026-03-02T10:00:00Z", "readerUnreadMessageCount": 0]],
                        ["id": "c3"],
                    ], "meta": ["totalCount": 3],
                ]
            ]
        }
        let chats = try await connection.chats()
        #expect(chats.map(\.id) == ["c2", "c1"])
        #expect(chats[1].chat?.unreadCount == 2 && chats[0].chat?.isGroup == true)
        #expect(sentVariables(transport.requests[0])["conversationKind"] as? String == "chat")
    }

    @Test func theAssistantListAsksForAssistantConversationsOnly() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["ListConversations": ["conversations": [], "meta": ["totalCount": 0]]] }
        _ = try await connection.conversations(userId: "user01")
        #expect(sentVariables(transport.requests[0])["conversationKind"] as? String == "assistant")
    }

    @Test func aChatMessageGoesOutWithItsReplyAndNoViewing() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["SendMessage": ["runId": "", "message": ["id": "m9", "role": "user", "content": "Hi", "isChatMessage": true]]] }
        let sent = try await connection.sendChatMessage(conversationId: "c1", text: "Hi", replyToMessageId: "m3")
        #expect(sent.runId.isEmpty && sent.message?.id == "m9")
        let variables = sentVariables(transport.requests[0])
        #expect(variables["replyToMessageId"] as? String == "m3" && variables["viewing"] == nil && variables["voice"] == nil)
    }

    @Test func startingAChatReturnsItsConversation() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["StartDirectChat": ["chat": ["id": "chat1"], "conversation": ["id": "c1"]]] }
        #expect(try await connection.startDirectChat(userId: "user02") == "c1")
        #expect(sentVariables(transport.requests[0])["userId"] as? String == "user02")
    }

    @Test func aGroupIsCreatedWithItsNameAndPeople() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["CreateGroupChat": ["chat": ["id": "chat2"], "conversation": ["id": "c2"]]] }
        #expect(try await connection.createGroupChat(name: "Pick team", userIds: ["u2", "u3"]) == "c2")
        #expect(sentVariables(transport.requests[0])["userIds"] as? [String] == ["u2", "u3"])
    }

    @Test func leavingSendsNoUserId() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["RemoveChatMember": ["chat": ["id": "chat2", "isReaderMember": false]]] }
        let room = try await connection.removeChatMember(chatId: "chat2")
        #expect(!room.canWrite)
        #expect(sentVariables(transport.requests[0])["userId"] == nil)
    }

    @Test func settingsReturnTheChatAfterTheChange() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["SetChatNotificationLevel": ["chat": ["id": "chat2", "readerNotificationLevel": "mentions"]]] }
        let room = try await connection.setChatNotificationLevel(chatId: "chat2", level: "mentions")
        #expect(room.readerNotificationLevel == "mentions")
        #expect(sentVariables(transport.requests[0])["notificationLevel"] as? String == "mentions")
    }

    @Test func previewsAreAskedForInBatchesOfFifty() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            ["ListMessageLinkPreviews": [["messageId": "m1", "isPending": true, "linkPreviews": []], ["messageId": "m2", "isPending": false, "linkPreviews": [["urlHash": "h1", "linkKind": "ticket", "path": "/ticket/42", "title": "#42"]]]]]
        }
        let result = try await connection.linkPreviews(conversationId: "c1", messageIds: (1...60).map { "m\($0)" })
        #expect((sentVariables(transport.requests[0])["messageIds"] as? [String])?.count == 50)
        #expect(result[0].isPending == true && result[1].linkPreviews?.first?.isExternal == false)
    }

    @Test func aChatNotificationReadsAsAuthorInChatWithItsExcerptAndOpensTheConversation() {
        let notification = PortalNotification(
            id: "n1", kind: "chat_message", chatId: "chat1", chatName: "Pick team", chatAuthorName: "Sam Sample", chatMessageExcerpt: "Ready?",
            chatConversationId: "c1")
        #expect(notification.subject == "Sam Sample in Pick team: Ready?")
        #expect(notification.target == .chat(conversationId: "c1"))
        #expect(!NotificationPreferences().isEnabled(kind: "chat_message", channel: "push"))
        #expect(NotificationPreferences().isEnabled(kind: "chat_message", channel: "in_app"))
    }

    @Test func aMemberWhoLeftCannotWrite() {
        #expect(!ChatRoom(id: "c", isReaderMember: false).canWrite)
        #expect(ChatRoom(id: "c").canWrite)
        #expect(ChatRoom(id: "c", members: [ChatMember(id: "a", userId: "u1"), ChatMember(id: "b", userId: "u2", leftAt: "2026-03-01T10:00:00Z")]).currentMembers.count == 1)
    }
}
