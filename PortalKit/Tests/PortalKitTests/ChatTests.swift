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

    static let agents = [Agent(id: "agent02", name: "Site Helper", isMain: false), Agent(id: "agent01", name: "Mujin AI", isMain: true)]

    @Test func anAgentIsAddressedByItsOwnNameAtAWordBoundary() {
        #expect(ChatRules.addressedAgent(in: "@Mujin AI what is the status?", agents: Self.agents)?.id == "agent01")
        #expect(ChatRules.addressedAgent(in: "hey @mujin ai, look", agents: Self.agents)?.id == "agent01")
        #expect(ChatRules.addressedAgent(in: "(@SITE HELPER)", agents: Self.agents)?.id == "agent02")
        #expect(ChatRules.addressedAgent(in: "mail me@Mujin AI.example", agents: Self.agents) == nil)
        #expect(ChatRules.addressedAgent(in: "@Mujin AIs", agents: Self.agents) == nil)
        #expect(ChatRules.addressedAgent(in: "@Unknown hello", agents: Self.agents) == nil)
        #expect(ChatRules.addressedAgent(in: "no mention", agents: Self.agents) == nil)
    }

    @Test func theAtListOpensAfterAnAtThatStartsAWord() {
        #expect(Mentions.query(in: "@") == "")
        #expect(Mentions.query(in: "Hi @Mu") == "Mu")
        #expect(Mentions.query(in: "mail me@example") == nil)
        #expect(Mentions.query(in: "no at sign") == nil)
        #expect(Mentions.query(in: "@Mujin AI and then a very long continuation of the sentence") == nil)
    }

    @Test func agentsComeFirstWithTheMainOneFirstThenMembersFilteredByWhatWasTyped() {
        let members = [
            ChatMember(id: "a", userId: "user01", userName: "Alex Example"), ChatMember(id: "b", userId: "user02", userName: "Sam Sample", organizationName: "Support"),
            ChatMember(id: "c", userId: "user03", userName: "Robin Demo", leftAt: "2026-03-01T10:00:00Z"),
        ]
        let all = Mentions.candidates(agents: Self.agents, members: members, query: "", excludingUserId: "user01")
        #expect(all.map(\.name) == ["Mujin AI", "Site Helper", "Sam Sample"])
        #expect(all.map(\.kind) == [.agent, .agent, .user])
        #expect(Mentions.candidates(agents: Self.agents, members: members, query: "sa", excludingUserId: "user01").map(\.name) == ["Sam Sample"])
        #expect(Mentions.candidates(agents: Self.agents, members: members, query: "muj", excludingUserId: "user01").map(\.name) == ["Mujin AI"])
    }

    @Test func pickingReplacesTheTypedTokenWithTheName() {
        let candidate = MentionCandidate(kind: .agent, id: "agent01", name: "Mujin AI")
        #expect(Mentions.inserting(candidate, into: "Hello @Mu") == "Hello @Mujin AI ")
        #expect(Mentions.inserting(candidate, into: "@") == "@Mujin AI ")
    }

    @Test func aPickedMentionKeepsItsPlaceInTheText() {
        let agent = MentionCandidate(kind: .agent, id: "agent01", name: "Mujin AI")
        let person = MentionCandidate(kind: .user, id: "user02", name: "Sam Sample")
        let text = "Hi @Sam Sample, can @Mujin AI check this?"
        let mentions = Mentions.ranges(of: [agent, person], in: text)
        #expect(mentions.map(\.id) == ["user02", "agent01"])
        #expect(mentions[0].start == 3 && mentions[0].length == 11)
        #expect(Mentions.ranges(of: [agent], in: "I edited the name away").isEmpty)
    }

    @Test func mentionRangesCountUTF16CodeUnitsLikeTheServer() {
        let agent = MentionCandidate(kind: .agent, id: "agent01", name: "Mujin AI")
        // Each emoji is two UTF-16 code units and one character.
        let text = "\u{1F600}\u{1F600} @Mujin AI hi"
        let mention = Mentions.ranges(of: [agent], in: text).first
        #expect(mention?.start == 5)
        #expect(mention?.length == 9)
    }

    @Test func sentMessagesDrawTheirMentionsAsChips() {
        let text = "Hi @Sam Sample, can @Mujin AI check this? me@Mujin AI no"
        let spans = Mentions.spans(in: text, names: ["Mujin AI", "Sam Sample"])
        #expect(spans.map { String(text[$0]) } == ["@Sam Sample", "@Mujin AI"])
    }

    @Test func mentionsAreOnlySentWhenTheServerTakesThem() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["SendMessage": ["runId": "run01", "message": ["id": "m1", "role": "user", "content": "x", "isChatMessage": true]]] }
        _ = try await connection.sendChatMessage(conversationId: "c1", text: "@Mujin AI hi")
        #expect(sentVariables(transport.requests[0])["mentions"] == nil)
        _ = try await connection.sendChatMessage(conversationId: "c1", text: "@Mujin AI hi", mentions: [ChatMention(kind: .agent, id: "agent01", start: 0, length: 9)])
        let mentions = sentVariables(transport.requests[1])["mentions"] as? [[String: Any]]
        #expect(mentions?.first?["agentId"] as? String == "agent01")
    }

    @Test func structuredMentionsAreOfferedWhenSendMessageHasTheArgument() async {
        let (connection, _) = scriptedConnection { _, _ in
            ["__schema": ["queryType": ["fields": []], "mutationType": ["fields": [["name": "sendMessage", "args": [["name": "message"], ["name": "mentions"]]]]], "subscriptionType": NSNull()]]
        }
        #expect(await connection.capabilities().offersStructuredMentions)
        #expect(!ServerCapabilities().offersStructuredMentions)
    }

    @Test func theAgentsAMayUseComeMainFirst() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            ["ListAuthorizedAgents": [["id": "a2", "name": "Site Helper", "isMain": false, "isEnabled": true], ["id": "a1", "name": "Mujin AI", "isMain": true, "isEnabled": true], ["id": "a3", "name": "Off", "isEnabled": false]]]
        }
        #expect(try await connection.authorizedAgents(organizationId: "o1").map(\.id) == ["a1", "a2"])
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
        #expect(NotificationPreferences().isEnabled(kind: "chat_message", channel: "push"))
        #expect(!NotificationPreferences().isEnabled(kind: "chat_message", channel: "email"))
        #expect(NotificationPreferences().isEnabled(kind: "chat_message", channel: "in_app"))
    }

    @Test func aMemberWhoLeftCannotWrite() {
        #expect(!ChatRoom(id: "c", isReaderMember: false).canWrite)
        #expect(ChatRoom(id: "c").canWrite)
        #expect(ChatRoom(id: "c", members: [ChatMember(id: "a", userId: "u1"), ChatMember(id: "b", userId: "u2", leftAt: "2026-03-01T10:00:00Z")]).currentMembers.count == 1)
    }
}
