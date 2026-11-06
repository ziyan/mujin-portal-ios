import Foundation
import Testing

@testable import PortalKit

/// Message threads: which screen an event or a row belongs to, how the documents are shaped for a server with and without them,
/// and how a notification opens a thread.
@Suite struct ThreadTests {
    func said(
        _ id: String, text: String = "Hello", role: String = "user", root: String? = nil, replyCount: Int? = nil, lastReplyAt: String? = nil,
        replyTo: String? = nil
    ) -> ConversationMessage {
        ConversationMessage(
            id: id, role: role, content: .string(text), createdAt: "2026-03-01T10:0\(id.suffix(1)):00Z", isChatMessage: true, authorUserId: "user02",
            authorName: "Sam Sample", replyToMessageId: replyTo, threadRootMessageId: root, threadReplyCount: replyCount, threadLastReplyAt: lastReplyAt)
    }

    func chatEvent(type: String = "chat_said", message: ConversationMessage) -> ConversationEvent {
        var object: [String: Any] = ["type": type, "chatId": "chat01"]
        object["message"] = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(message))
        let chat = try! JSONDecoder().decode(ConversationEvent.Chat.self, from: JSONSerialization.data(withJSONObject: object))
        return ConversationEvent(type: type, chat: chat)
    }

    func runEvent(_ type: String, thread: String? = nil) -> ConversationEvent {
        ConversationEvent(
            type: type, runId: "run01", textDelta: type == "text_delta" ? .init(messageId: "a9", text: "Hi") : nil,
            toolCall: type == "tool_call" ? .init(toolCallId: "call01", toolName: "sites") : nil,
            runComplete: type == "run_complete" ? .init(stopReason: "end_turn") : nil,
            runError: type == "run_error" ? .init(turnEndReason: "It failed.", reasonKind: "failed") : nil, threadRootMessageId: thread)
    }

    // MARK: routing

    @Test func whatARunSaysBelongsToTheThreadItAnswersIn() {
        #expect(ThreadRouting.isEventForView(runEvent("text_delta", thread: "m1"), viewThreadRootMessageId: "m1"))
        #expect(!ThreadRouting.isEventForView(runEvent("text_delta", thread: "m1"), viewThreadRootMessageId: nil))
        #expect(!ThreadRouting.isEventForView(runEvent("tool_call", thread: "m1"), viewThreadRootMessageId: "m2"))
        #expect(!ThreadRouting.isEventForView(runEvent("text_delta"), viewThreadRootMessageId: "m1"))
        #expect(ThreadRouting.isEventForView(runEvent("text_delta"), viewThreadRootMessageId: nil))
        #expect(ThreadRouting.isEventForView(runEvent("text_delta", thread: ""), viewThreadRootMessageId: ""))
    }

    @Test func everythingElseReachesEveryScreen() {
        #expect(ThreadRouting.isEventForView(runEvent("run_complete", thread: "m1"), viewThreadRootMessageId: nil))
        #expect(ThreadRouting.isEventForView(runEvent("run_error", thread: "m1"), viewThreadRootMessageId: "m2"))
        let pending = ConversationEvent(type: "pending_question", pendingQuestion: .init(questionId: "q1", question: "Which?"), threadRootMessageId: "m1")
        #expect(ThreadRouting.isEventForView(pending, viewThreadRootMessageId: nil))
    }

    @Test func onlyRunContentSaysWhereTheAssistantWorks() {
        #expect(ThreadRouting.workingThreadRootMessageId(of: runEvent("tool_call", thread: "m1")) == "m1")
        #expect(ThreadRouting.workingThreadRootMessageId(of: runEvent("text_delta")) == nil)
        #expect(ThreadRouting.workingThreadRootMessageId(of: runEvent("run_complete", thread: "m1")) == nil)
    }

    @Test func aScreenShowsARunAtWorkOnlyWhereItAnswers() {
        #expect(ThreadRouting.isViewRunning(isRunning: true, workingThreadRootMessageId: "m1", viewThreadRootMessageId: "m1"))
        #expect(!ThreadRouting.isViewRunning(isRunning: true, workingThreadRootMessageId: "m1", viewThreadRootMessageId: nil))
        #expect(ThreadRouting.isViewRunning(isRunning: true, workingThreadRootMessageId: nil, viewThreadRootMessageId: nil))
        #expect(!ThreadRouting.isViewRunning(isRunning: true, workingThreadRootMessageId: nil, viewThreadRootMessageId: "m1"))
        #expect(!ThreadRouting.isViewRunning(isRunning: false, workingThreadRootMessageId: "m1", viewThreadRootMessageId: "m1"))
    }

    @Test func aThreadListsItsRootAndRepliesAndTheMainHistoryTheRest() {
        let root = said("m1", replyCount: 1)
        let reply = said("m2", root: "m1")
        let plain = said("m3")
        let oldReply = said("m4", replyTo: "m3")
        #expect(ThreadRouting.belongs(root, toViewWithThreadRootMessageId: "m1"))
        #expect(ThreadRouting.belongs(reply, toViewWithThreadRootMessageId: "m1"))
        #expect(!ThreadRouting.belongs(plain, toViewWithThreadRootMessageId: "m1"))
        #expect(ThreadRouting.belongs(root, toViewWithThreadRootMessageId: nil))
        #expect(!ThreadRouting.belongs(reply, toViewWithThreadRootMessageId: nil))
        // Written before threads existed: it has no thread, so it stays in the main history.
        #expect(ThreadRouting.belongs(oldReply, toViewWithThreadRootMessageId: nil))
    }

    @Test func aThreadSendsItsRepliesToTheRootUnlessAMessageWasPicked() {
        #expect(ThreadRouting.replyToMessageId(pickedMessageId: nil, viewThreadRootMessageId: "m1") == "m1")
        #expect(ThreadRouting.replyToMessageId(pickedMessageId: "m3", viewThreadRootMessageId: "m1") == "m3")
        #expect(ThreadRouting.replyToMessageId(pickedMessageId: nil, viewThreadRootMessageId: nil) == nil)
        #expect(ThreadRouting.replyToMessageId(pickedMessageId: "", viewThreadRootMessageId: nil) == nil)
        #expect(ThreadRouting.replyToMessageId(pickedMessageId: "m3", viewThreadRootMessageId: nil) == "m3")
    }

    @Test func theReadMarkFollowsTheNewestMessageEvenWhenItIsAReply() {
        let rows = [said("m1"), said("m2", root: "m1"), ConversationMessage(id: "t1", role: "tool", content: .string("x"), isChatMessage: false)]
        #expect(ThreadRouting.newestChatMessageId(in: rows) == "m2")
        #expect(ThreadRouting.newestChatMessageId(in: []) == nil)
    }

    // MARK: a chat

    @Test func theMainHistoryOfAChatKeepsNoReplyAndCountsThemUnderTheirRoot() {
        var timeline = ChatTimeline()
        timeline.load([said("m1", replyCount: 2, lastReplyAt: "2026-03-01T10:09:00Z"), said("m2", root: "m1"), said("m3")])
        #expect(timeline.messages.map(\.id) == ["m1", "m3"])
        #expect(timeline.messages[0].threadSummary == ThreadSummary(replyCount: 2, lastReplyAt: "2026-03-01T10:09:00Z"))
        #expect(timeline.messages[1].threadSummary == nil)
    }

    @Test func aReplySaidLiveIsCountedOnceAndStaysOutOfTheMainHistory() {
        var timeline = ChatTimeline()
        timeline.load([said("m1", replyCount: 1), said("m3")])
        let reply = chatEvent(message: said("m5", root: "m1"))
        #expect(timeline.apply(reply) == .threadReplied(rootMessageId: "m1", messageId: "m5"))
        #expect(timeline.apply(reply) == .none)
        #expect(timeline.messages.map(\.id) == ["m1", "m3"])
        #expect(timeline.messages[0].threadReplyCount == 2)
        #expect(timeline.messages[0].threadLastReplyAt == "2026-03-01T10:05:00Z")
        // An edit of a reply is not a new reply.
        #expect(timeline.apply(chatEvent(type: "chat_edited", message: said("m6", root: "m1"))) == .none)
        #expect(timeline.messages[0].threadReplyCount == 2)
    }

    @Test func aReplyToAMessageNotHeldChangesNoCount() {
        var timeline = ChatTimeline()
        timeline.load([said("m3")])
        #expect(timeline.apply(chatEvent(message: said("m5", root: "m1"))) == .threadReplied(rootMessageId: "m1", messageId: "m5"))
        #expect(timeline.messages.map(\.id) == ["m3"])
    }

    @Test func aReplySaidLiveMovesTheReadMarkOnToIt() {
        var timeline = ChatTimeline()
        timeline.load([said("m1"), said("m3")])
        #expect(timeline.newestMessageId == "m3")
        _ = timeline.apply(chatEvent(message: said("m5", root: "m1")))
        #expect(timeline.newestMessageId == "m5")
        timeline.noteNewestMessage("m7")
        #expect(timeline.newestMessageId == "m7")
        timeline.noteNewestMessage(nil)
        timeline.noteNewestMessage("")
        #expect(timeline.newestMessageId == "m7")
    }

    @Test func aThreadListsOnlyItself() {
        var timeline = ChatTimeline(threadRootMessageId: "m1")
        timeline.load([said("m1", replyCount: 2), said("m2", root: "m1"), said("m3"), said("m4", root: "m1"), said("m5", root: "m9")])
        #expect(timeline.messages.map(\.id) == ["m1", "m2", "m4"])
        // A message of the main history, or of another thread, does not appear.
        #expect(timeline.apply(chatEvent(message: said("m6"))) == .none)
        #expect(timeline.apply(chatEvent(message: said("m7", root: "m9"))) == .none)
        #expect(timeline.messages.count == 3)
        // A reply in this thread does.
        #expect(timeline.apply(chatEvent(message: said("m8", root: "m1"))) == .received(messageId: "m8"))
        #expect(timeline.messages.map(\.id) == ["m1", "m2", "m4", "m8"])
        // What the person just sent is added the same way.
        timeline.upsert(said("m9", root: "m1"))
        timeline.upsert(said("m0"))
        #expect(timeline.messages.map(\.id) == ["m1", "m2", "m4", "m8", "m9"])
    }

    @Test func aReplyWrittenBeforeThreadsKeepsItsPlaceAndItsQuote() {
        var timeline = ChatTimeline()
        timeline.load([said("m1"), said("m2", replyTo: "m1")])
        #expect(timeline.messages.map(\.id) == ["m1", "m2"])
        #expect(timeline.messages[1].isReply && timeline.messages[1].threadRootMessageId == nil)
        #expect(timeline.apply(chatEvent(message: said("m4", replyTo: "m1"))) == .received(messageId: "m4"))
    }

    // MARK: an assistant conversation

    func userRow(_ id: String, text: String, root: String? = nil, replyTo: String? = nil) -> ConversationMessage {
        ConversationMessage(id: id, role: "user", content: .string(text), replyToMessageId: replyTo, threadRootMessageId: root)
    }

    func answerRow(_ id: String, text: String, root: String? = nil, replyCount: Int? = nil) -> ConversationMessage {
        ConversationMessage(id: id, role: "assistant", content: .string(text), threadRootMessageId: root, threadReplyCount: replyCount, threadLastReplyAt: replyCount == nil ? nil : "2026-03-01T10:00:00Z")
    }

    @Test func theMainHistoryOfAConversationSaysWhichAnswersHaveAThread() {
        var transcript = Transcript()
        transcript.load(messages: [userRow("m1", text: "Hi"), answerRow("m2", text: "Hello", replyCount: 3)], questions: [], approvals: [], isRunning: false)
        #expect(transcript.threadSummary(for: "m2")?.replyCount == 3)
        #expect(transcript.threadSummary(for: "m1") == nil)
    }

    @Test func aThreadDoesNotQuoteItsRootAboveEveryReply() {
        var transcript = Transcript(threadRootMessageId: "m2")
        let reply = ConversationMessage(
            id: "m3", role: "user", content: .string("Why?"), replyToMessageId: "m2", replyToExcerpt: "Hello", replyToAuthorName: "Assistant", threadRootMessageId: "m2")
        let other = ConversationMessage(
            id: "m4", role: "user", content: .string("And?"), replyToMessageId: "m3", replyToExcerpt: "Why?", replyToAuthorName: "Alex", threadRootMessageId: "m2")
        transcript.load(messages: [answerRow("m2", text: "Hello", replyCount: 2), reply, other], questions: [], approvals: [], isRunning: false)
        #expect(transcript.replyQuote(for: "m3") == nil)
        // The message replied to is two rows up here, so its quote is kept.
        transcript.load(messages: [answerRow("m2", text: "Hello", replyCount: 2), userRow("m5", text: "x", root: "m2"), other], questions: [], approvals: [], isRunning: false)
        #expect(transcript.replyQuote(for: "m4") != nil)
    }

    @Test func aMainHistoryKeepsTheQuoteOfAnOldReply() {
        var transcript = Transcript()
        let oldReply = ConversationMessage(
            id: "m4", role: "user", content: .string("Why?"), replyToMessageId: "m1", replyToExcerpt: "Hi there", replyToAuthorName: "Assistant")
        transcript.load(messages: [userRow("m1", text: "Hi there"), answerRow("m2", text: "Hello"), oldReply], questions: [], approvals: [], isRunning: false)
        #expect(transcript.replyQuote(for: "m4")?.excerpt == "Hi there")
    }

    @Test func aRunInAThreadStreamsOnlyIntoThatThread() {
        var main = Transcript()
        var thread = Transcript(threadRootMessageId: "m2")
        for event in [runEvent("text_delta", thread: "m2"), runEvent("tool_call", thread: "m2")] {
            main.apply(event)
            thread.apply(event)
        }
        #expect(main.entries.isEmpty)
        #expect(!thread.entries.isEmpty)
        // The main history still knows where the assistant works, to say so under the message.
        #expect(main.workingThreadRootMessageId == "m2")
        #expect(main.isRunning)
        #expect(!main.isRunningInView)
        #expect(thread.isRunningInView)
    }

    @Test func aRunInTheMainHistoryStaysOutOfAThread() {
        var main = Transcript()
        var thread = Transcript(threadRootMessageId: "m2")
        let event = runEvent("text_delta")
        main.apply(event)
        thread.apply(event)
        #expect(main.entries.count == 1 && thread.entries.isEmpty)
        #expect(main.isRunningInView && !thread.isRunningInView)
    }

    @Test func theEndOfARunInAThreadIsToldInThatThreadAlone() {
        var main = Transcript()
        var thread = Transcript(threadRootMessageId: "m2")
        for event in [runEvent("text_delta", thread: "m2"), runEvent("run_error", thread: "m2")] {
            main.apply(event)
            thread.apply(event)
        }
        #expect(!main.isRunning && !thread.isRunning)
        #expect(main.workingThreadRootMessageId == nil)
        #expect(main.entries.isEmpty)
        #expect(thread.entries.contains { if case .turnEnd = $0 { true } else { false } })
    }

    @Test func aReplySentInAThreadIsAnsweredInThatThread() {
        var thread = Transcript(threadRootMessageId: "m2")
        thread.appendPendingUser("Why?")
        #expect(thread.isRunningInView)
        var main = Transcript()
        main.appendPendingUser("Hello")
        #expect(main.isRunningInView)
    }

    // MARK: documents and capabilities

    @Test func theThreadFieldsAreAskedForOnlyWhereAMessageAndAnEventAreAsked() {
        let threaded = Documents.withThreads(Documents.listMessages)
        #expect(!Documents.listMessages.contains("threadReplyCount"))
        #expect(threaded.contains("threadRootMessageId threadReplyCount threadLastReplyAt"))
        let subscription = Documents.withThreads(Documents.onConversationEvent)
        #expect(subscription.contains("OnConversationEvent(conversationId: $conversationId) { threadRootMessageId"))
        // The message inside a chat event asks for them too.
        #expect(subscription.contains("linkPreviewsRemovedAt threadRootMessageId"))
        #expect(Documents.withThreads(Documents.me) == Documents.me)
    }

    @Test func theThreadFieldsComposeWithTheVoiceAndCallFields() {
        let both = Documents.withThreads(Documents.withChatMedia(Documents.listMessages))
        #expect(both.contains("voiceMessage {") && both.contains("call {") && both.contains("threadReplyCount"))
    }

    @Test func theMessageQueriesNameThreadsOnlyInTheirOwnDocuments() {
        #expect(!Documents.listMessages.contains("shouldCollapseThreads") && !Documents.listMessages.contains("threadRootMessageId"))
        #expect(!Documents.countMessages.contains("shouldCollapseThreads"))
        #expect(Documents.listMessagesInThreads.contains("$shouldCollapseThreads: Boolean"))
        #expect(Documents.listMessagesInThreads.contains("$threadRootMessageId: String"))
        #expect(Documents.countMessagesInThreads.contains("shouldCollapseThreads: $shouldCollapseThreads"))
    }

    @Test func aServerOffersThreadsWhenItsMessageQueryTakesBothArguments() {
        #expect(!ServerCapabilities().offersMessageThreads)
        #expect(!ServerCapabilities(listMessageArgumentNames: ["conversationId", "latestMessageCount"]).offersMessageThreads)
        #expect(!ServerCapabilities(listMessageArgumentNames: ["threadRootMessageId"]).offersMessageThreads)
        #expect(ServerCapabilities(listMessageArgumentNames: ["threadRootMessageId", "shouldCollapseThreads"]).offersMessageThreads)
    }

    @Test func theCapabilitiesAreReadFromTheMessageQueryOfTheSchema() async {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "__schema": [
                    "queryType": ["fields": [["name": "listTickets", "args": []], ["name": "listConversationMessages", "args": [["name": "threadRootMessageId"], ["name": "shouldCollapseThreads"]]]]],
                    "mutationType": ["fields": []],
                    "subscriptionType": NSNull(),
                ]
            ]
        }
        let capabilities = await connection.capabilities()
        #expect(capabilities.offersMessageThreads)
        let (olderConnection, _) = scriptedConnection { _, _ in
            ["__schema": ["queryType": ["fields": [["name": "listConversationMessages", "args": [["name": "latestMessageCount"]]]]], "mutationType": NSNull(), "subscriptionType": NSNull()]]
        }
        let older = await olderConnection.capabilities()
        #expect(!older.offersMessageThreads)
    }

    @Test func anOlderServerGetsTheDocumentsAsTheyWere() async {
        let (connection, _) = scriptedConnection { _, _ in [:] }
        let before = await connection.prepared(Documents.listMessages)
        #expect(before == Documents.listMessages)
        await connection.setMessageThreads(true)
        let after = await connection.prepared(Documents.listMessages)
        #expect(after.contains("threadReplyCount"))
    }

    @Test func aMessageDecodesWithAndWithoutThreadFields() throws {
        let threaded = try JSONDecoder().decode(
            ConversationMessage.self,
            from: Data(#"{"id":"m1","role":"user","content":"Hi","threadRootMessageId":"","threadReplyCount":4,"threadLastReplyAt":"2026-03-01T10:09:00Z"}"#.utf8))
        #expect(threaded.threadReplyCount == 4)
        #expect(ChatMessage(threaded).threadRootMessageId == nil)
        #expect(ChatMessage(threaded).threadSummary?.replyCount == 4)
        let older = try JSONDecoder().decode(ConversationMessage.self, from: Data(#"{"id":"m1","role":"user","content":"Hi"}"#.utf8))
        #expect(ChatMessage(older).threadSummary == nil && !ChatMessage(older).hasThread)
    }

    @Test func anEventDecodesWithAndWithoutItsThread() throws {
        let event = try JSONDecoder().decode(
            ConversationEvent.self, from: Data(#"{"type":"text_delta","runId":"r","textDelta":{"messageId":"a","text":"x"},"threadRootMessageId":"m2"}"#.utf8))
        #expect(event.threadRootMessageId == "m2")
        let older = try JSONDecoder().decode(ConversationEvent.self, from: Data(#"{"type":"run_complete"}"#.utf8))
        #expect(older.threadRootMessageId == nil)
    }

    // MARK: a notification

    static func userInfo(_ portal: [String: Any]) -> [AnyHashable: Any] { ["aps": ["category": "PORTAL_REPLY"], "portal": portal] }

    @Test func aChatPushAboutAReplyOpensItsThread() throws {
        let payload = try #require(
            PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "chat_message", "conversationId": "c2", "chatId": "ch1", "threadRootMessageId": "m7"])))
        #expect(payload.threadRootMessageId == "m7")
        #expect(payload.route == .chatThread(conversationId: "c2", threadRootMessageId: "m7"))
    }

    @Test func aPushWithNoThreadOpensTheChatAsBefore() throws {
        #expect(PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "chat_message", "conversationId": "c2"]))?.route == .chat(conversationId: "c2"))
        #expect(PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "chat_message", "conversationId": "c2", "threadRootMessageId": ""]))?.route == .chat(conversationId: "c2"))
        #expect(PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "agent_message", "conversationId": "c9"]))?.route == .conversation(id: "c9"))
    }

    @Test func aThreadWithoutAConversationOpensTheInbox() throws {
        #expect(PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "chat_message", "threadRootMessageId": "m7"]))?.route == .notifications)
    }

    @Test func aCallPushIgnoresAThread() throws {
        #expect(PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "chat_call", "conversationId": "c2", "threadRootMessageId": "m7"]))?.route == .chat(conversationId: "c2"))
    }

    @Test func anAssistantPushAboutAThreadOpensTheConversationOnIt() throws {
        let payload = try #require(
            PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "agent_message", "conversationId": "c9", "threadRootMessageId": "m3"])))
        #expect(payload.route == .conversationThread(id: "c9", threadRootMessageId: "m3"))
    }
}
