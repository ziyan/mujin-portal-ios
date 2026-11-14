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

    // MARK: chats

    func chatMessage(_ id: String, author: String = "user01", root: String? = nil, replyCount: Int = 0, lastReplyAt: String? = nil, text: String = "Hello") -> ChatMessage {
        ChatMessage(
            ConversationMessage(
                id: id, role: "user", content: .string(text), createdAt: "2026-03-01T10:00:00Z", isChatMessage: true, authorUserId: author,
                authorName: author, threadRootMessageId: root, threadReplyCount: replyCount, threadLastReplyAt: lastReplyAt))
    }

    @Test func aTapOnAMessageOfTheMainHistoryOpensItsThreadEvenWithoutReplies() {
        #expect(ThreadRouting.chatThreadToOpen(messageId: "m1", threadRootMessageId: nil, isDeleted: false) == "m1")
        #expect(ThreadRouting.chatThreadToOpen(messageId: "m2", threadRootMessageId: "m1", isDeleted: false) == "m1")
        #expect(ThreadRouting.chatThreadToOpen(messageId: "m3", threadRootMessageId: "", isDeleted: true) == nil)
    }

    @Test func theThreadToContinueIsTheLatestActiveOneThePersonTookPartIn() {
        let now = PortalDate.parse("2026-03-01T12:00:00Z")!
        let messages = [
            // A thread the person wrote a reply in, active ten minutes ago.
            chatMessage("r1", author: "user02", replyCount: 2, lastReplyAt: "2026-03-01T11:50:00Z", text: "Can someone check the gripper on station three today?"),
            chatMessage("x1", author: "user01", root: "r1"),
            // A thread the person started, active five minutes ago: the latest.
            chatMessage("r2", author: "user01", replyCount: 1, lastReplyAt: "2026-03-01T11:55:00Z", text: "Dock door"),
            // Active a minute ago, but the person took no part in it.
            chatMessage("r3", author: "user03", replyCount: 4, lastReplyAt: "2026-03-01T11:59:00Z"),
            // The person took part, but its last reply is an hour old.
            chatMessage("r4", author: "user01", replyCount: 1, lastReplyAt: "2026-03-01T11:00:00Z"),
        ]
        #expect(ThreadRouting.threadToContinue(messages, currentUserId: "user01", now: now)?.id == "r2")
        #expect(ThreadRouting.threadToContinue(messages, currentUserId: "user09", now: now) == nil)
    }

    @Test func anExcerptEndsAtAWord() {
        #expect(ThreadRouting.excerpt("Dock door") == "Dock door")
        #expect(ThreadRouting.excerpt("Can someone check the gripper on station three today?") == "Can someone check the gripper on station\u{2026}")
        #expect(ThreadRouting.excerpt("Line one\nline two") == "Line one line two")
    }

    // MARK: routing

    @Test func theMainHistoryShowsEveryEventAndAThreadOnlyItsOwnRuns() {
        #expect(ThreadRouting.isEventForView(runEvent("text_delta", thread: "m1"), viewThreadRootMessageId: nil))
        #expect(ThreadRouting.isEventForView(runEvent("text_delta"), viewThreadRootMessageId: nil))
        #expect(ThreadRouting.isEventForView(runEvent("text_delta", thread: "m1"), viewThreadRootMessageId: "m1"))
        #expect(!ThreadRouting.isEventForView(runEvent("tool_call", thread: "m1"), viewThreadRootMessageId: "m2"))
        #expect(!ThreadRouting.isEventForView(runEvent("text_delta"), viewThreadRootMessageId: "m1"))
    }

    @Test func everythingElseReachesEveryScreen() {
        #expect(ThreadRouting.isEventForView(runEvent("run_complete", thread: "m1"), viewThreadRootMessageId: nil))
        #expect(ThreadRouting.isEventForView(runEvent("run_error", thread: "m1"), viewThreadRootMessageId: "m2"))
        let pending = ConversationEvent(type: "pending_question", pendingQuestion: .init(questionId: "q1", question: "Which?"), threadRootMessageId: "m1")
        #expect(ThreadRouting.isEventForView(pending, viewThreadRootMessageId: nil))
    }

    @Test func aQuestionOrApprovalDeliveredLiveShowsOnlyInTheViewItWasAskedIn() {
        let question = ConversationEvent(type: "pending_question", pendingQuestion: .init(questionId: "q1", question: "Which?"), threadRootMessageId: "m1")
        let approval = ConversationEvent(
            type: "pending_approval", pendingApproval: .init(approvalId: "a1", toolName: "shell"), threadRootMessageId: "m1")
        var inThread = Transcript(threadRootMessageId: "m1")
        inThread.apply(question)
        inThread.apply(approval)
        #expect(inThread.entries.map(\.id).sorted() == ["approval:a1", "question:q1"])
        var otherThread = Transcript(threadRootMessageId: "m2")
        otherThread.apply(question)
        otherThread.apply(approval)
        #expect(otherThread.entries.isEmpty)
        var mainHistory = Transcript()
        mainHistory.apply(question)
        mainHistory.apply(approval)
        #expect(mainHistory.entries.isEmpty)
        mainHistory.apply(ConversationEvent(type: "pending_question", pendingQuestion: .init(questionId: "q2", question: "Which?")))
        #expect(mainHistory.entries.map(\.id) == ["question:q2"])
    }

    @Test func onlyATodoToolResultRefreshesTheTodoList() {
        #expect(ConversationEvent(type: "tool_result", toolResult: .init(toolCallId: "c1", toolName: "todo")).mayChangeTodos)
        #expect(!ConversationEvent(type: "tool_result", toolResult: .init(toolCallId: "c2", toolName: "shell")).mayChangeTodos)
        #expect(!ConversationEvent(type: "tool_call", toolCall: .init(toolCallId: "c1", toolName: "todo")).mayChangeTodos)
    }

    @Test func onlyRunContentSaysWhereTheAssistantWorks() {
        #expect(ThreadRouting.workingThreadRootMessageId(of: runEvent("tool_call", thread: "m1")) == "m1")
        #expect(ThreadRouting.workingThreadRootMessageId(of: runEvent("text_delta")) == nil)
        #expect(ThreadRouting.workingThreadRootMessageId(of: runEvent("run_complete", thread: "m1")) == nil)
    }

    @Test func aThreadShowsARunAtWorkOnlyWhereItAnswers() {
        #expect(ThreadRouting.isViewRunning(isRunning: true, workingThreadRootMessageId: "m1", viewThreadRootMessageId: "m1"))
        #expect(ThreadRouting.isViewRunning(isRunning: true, workingThreadRootMessageId: "m1", viewThreadRootMessageId: nil))
        #expect(ThreadRouting.isViewRunning(isRunning: true, workingThreadRootMessageId: nil, viewThreadRootMessageId: nil))
        #expect(!ThreadRouting.isViewRunning(isRunning: true, workingThreadRootMessageId: "m2", viewThreadRootMessageId: "m1"))
        #expect(!ThreadRouting.isViewRunning(isRunning: true, workingThreadRootMessageId: nil, viewThreadRootMessageId: "m1"))
        #expect(!ThreadRouting.isViewRunning(isRunning: false, workingThreadRootMessageId: "m1", viewThreadRootMessageId: "m1"))
    }

    @Test func aThreadListsItsRootAndRepliesAndTheMainHistoryEverything() {
        let root = said("m1", replyCount: 1)
        let reply = said("m2", root: "m1")
        let plain = said("m3")
        #expect(ThreadRouting.belongs(root, toViewWithThreadRootMessageId: "m1"))
        #expect(ThreadRouting.belongs(reply, toViewWithThreadRootMessageId: "m1"))
        #expect(!ThreadRouting.belongs(plain, toViewWithThreadRootMessageId: "m1"))
        #expect(ThreadRouting.belongs(root, toViewWithThreadRootMessageId: nil))
        #expect(ThreadRouting.belongs(reply, toViewWithThreadRootMessageId: nil))
        #expect(ThreadRouting.belongs(said("m4", replyTo: "m3"), toViewWithThreadRootMessageId: nil))
    }

    @Test func aTapOpensTheThreadAReplyIsInOrTheOneARootHolds() {
        #expect(ThreadRouting.threadToOpen(messageId: "m2", threadRootMessageId: "m1", replyCount: 0) == "m1")
        #expect(ThreadRouting.threadToOpen(messageId: "m1", threadRootMessageId: nil, replyCount: 2) == "m1")
        #expect(ThreadRouting.threadToOpen(messageId: "m3", threadRootMessageId: "", replyCount: 0) == nil)
    }

    @Test func aThreadSendsItsRepliesToTheRootUnlessAMessageWasPicked() {
        #expect(ThreadRouting.replyToMessageId(pickedMessageId: nil, viewThreadRootMessageId: "m1") == "m1")
        #expect(ThreadRouting.replyToMessageId(pickedMessageId: "m3", viewThreadRootMessageId: "m1") == "m3")
        #expect(ThreadRouting.replyToMessageId(pickedMessageId: nil, viewThreadRootMessageId: nil) == nil)
        #expect(ThreadRouting.replyToMessageId(pickedMessageId: "", viewThreadRootMessageId: nil) == nil)
        #expect(ThreadRouting.replyToMessageId(pickedMessageId: "m3", viewThreadRootMessageId: nil) == "m3")
    }

    // MARK: a chat

    @Test func theMainHistoryOfAChatListsEveryMessageAndCountsRepliesUnderTheirRoot() {
        var timeline = ChatTimeline()
        timeline.load([said("m1", replyCount: 2, lastReplyAt: "2026-03-01T10:09:00Z"), said("m2", root: "m1"), said("m3")])
        #expect(timeline.messages.map(\.id) == ["m1", "m2", "m3"])
        #expect(timeline.messages[0].threadSummary == ThreadSummary(replyCount: 2, lastReplyAt: "2026-03-01T10:09:00Z"))
        #expect(timeline.messages[1].threadRootMessageId == "m1")
    }

    @Test func aReplySaidLiveIsListedAndCountedOnce() {
        var timeline = ChatTimeline()
        timeline.load([said("m1", replyCount: 1), said("m3")])
        let reply = chatEvent(message: said("m5", root: "m1"))
        #expect(timeline.apply(reply) == .received(messageId: "m5"))
        #expect(timeline.apply(reply) == .none)
        #expect(timeline.messages.map(\.id) == ["m1", "m3", "m5"])
        #expect(timeline.messages[0].threadReplyCount == 2)
        #expect(timeline.messages[0].threadLastReplyAt == "2026-03-01T10:05:00Z")
        // An edit of a reply is not a new reply.
        _ = timeline.apply(chatEvent(type: "chat_edited", message: said("m5", text: "Changed", root: "m1")))
        #expect(timeline.messages[0].threadReplyCount == 2)
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

    @Test func aMainHistoryDoesNotQuoteARootAboveEachOfItsReplies() {
        func reply(_ id: String) -> ConversationMessage {
            ConversationMessage(
                id: id, role: "user", content: .string("Why?"), replyToMessageId: "m2", replyToExcerpt: "Hello", replyToAuthorName: "Assistant", threadRootMessageId: "m2")
        }
        var transcript = Transcript()
        transcript.load(messages: [answerRow("m2", text: "Hello", replyCount: 3), reply("m3"), answerRow("m4", text: "Because", root: "m2"), reply("m5")], questions: [], approvals: [], isRunning: false)
        #expect(transcript.replyQuote(for: "m3") == nil)
        #expect(transcript.replyQuote(for: "m5") == nil)
    }

    @Test func aReplyKeepsItsQuoteWhileTheRootIsNotLoaded() {
        let reply = ConversationMessage(
            id: "m3", role: "user", content: .string("Why?"), replyToMessageId: "m2", replyToExcerpt: "Hello", replyToAuthorName: "Assistant", threadRootMessageId: "m2")
        var transcript = Transcript()
        transcript.load(messages: [userRow("m1", text: "Hi"), reply], questions: [], approvals: [], isRunning: false)
        #expect(transcript.replyQuote(for: "m3")?.excerpt == "Hello")
    }

    @Test func aQuoteOfAnotherMessageInTheThreadIsNotARepeatOfTheRoot() {
        #expect(ThreadRouting.quoteRepeatsRoot(replyToMessageId: "m2", threadRootMessageId: "m2", isRootShown: true))
        #expect(!ThreadRouting.quoteRepeatsRoot(replyToMessageId: "m3", threadRootMessageId: "m2", isRootShown: true))
        #expect(!ThreadRouting.quoteRepeatsRoot(replyToMessageId: "m2", threadRootMessageId: "m2", isRootShown: false))
        #expect(!ThreadRouting.quoteRepeatsRoot(replyToMessageId: "m2", threadRootMessageId: nil, isRootShown: true))
    }

    @Test func aMainHistoryKeepsTheQuoteOfAnOldReply() {
        var transcript = Transcript()
        let oldReply = ConversationMessage(
            id: "m4", role: "user", content: .string("Why?"), replyToMessageId: "m1", replyToExcerpt: "Hi there", replyToAuthorName: "Assistant")
        transcript.load(messages: [userRow("m1", text: "Hi there"), answerRow("m2", text: "Hello"), oldReply], questions: [], approvals: [], isRunning: false)
        #expect(transcript.replyQuote(for: "m4")?.excerpt == "Hi there")
    }

    @Test func aRunInAThreadStreamsIntoTheMainHistoryAndIntoThatThread() {
        var main = Transcript()
        var thread = Transcript(threadRootMessageId: "m2")
        var other = Transcript(threadRootMessageId: "m5")
        for event in [runEvent("text_delta", thread: "m2"), runEvent("tool_call", thread: "m2")] {
            main.apply(event)
            thread.apply(event)
            other.apply(event)
        }
        #expect(!main.entries.isEmpty)
        #expect(main.entries == thread.entries)
        #expect(other.entries.isEmpty)
        #expect(main.workingThreadRootMessageId == "m2")
        #expect(main.isRunningInView && thread.isRunningInView)
        #expect(other.isRunning && !other.isRunningInView)
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

    @Test func theEndOfARunInAThreadIsToldInTheMainHistoryAndThatThread() {
        var main = Transcript()
        var thread = Transcript(threadRootMessageId: "m2")
        var other = Transcript(threadRootMessageId: "m5")
        for event in [runEvent("text_delta", thread: "m2"), runEvent("run_error", thread: "m2")] {
            main.apply(event)
            thread.apply(event)
            other.apply(event)
        }
        #expect(!main.isRunning && !thread.isRunning && !other.isRunning)
        #expect(main.workingThreadRootMessageId == nil)
        for transcript in [main, thread] {
            #expect(transcript.entries.contains { if case .turnEnd = $0 { true } else { false } })
        }
        #expect(other.entries.isEmpty)
    }

    @Test func aTapOnAReplyOrARootOpensItsThread() {
        var transcript = Transcript()
        transcript.load(
            messages: [answerRow("m2", text: "Hello", replyCount: 1), userRow("m3", text: "Why?", root: "m2", replyTo: "m2"), userRow("m4", text: "Thanks")],
            questions: [], approvals: [], isRunning: false)
        #expect(transcript.threadToOpen(forMessage: "m2") == "m2")
        #expect(transcript.threadToOpen(forMessage: "m3") == "m2")
        // A stored message with no replies opens its own thread, as on the web; one not stored yet opens none.
        #expect(transcript.threadToOpen(forMessage: "m4") == "m4")
        #expect(transcript.threadToOpen(forMessage: "pending:1") == nil)
    }

    @Test func aTapOnAConversationMessageOpensItsThreadOnceItIsStored() {
        #expect(ThreadRouting.conversationThreadToOpen(messageId: "m2", threadRootMessageId: "m1", isStored: true) == "m1")
        #expect(ThreadRouting.conversationThreadToOpen(messageId: "m1", threadRootMessageId: nil, isStored: true) == "m1")
        #expect(ThreadRouting.conversationThreadToOpen(messageId: "m3", threadRootMessageId: "", isStored: true) == "m3")
        #expect(ThreadRouting.conversationThreadToOpen(messageId: "m4", threadRootMessageId: nil, isStored: false) == nil)
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

    @Test func theMessageQueryNamesThreadsOnlyInItsOwnDocument() {
        #expect(!Documents.listMessages.contains("threadRootMessageId"))
        #expect(Documents.listMessagesInThread.contains("$threadRootMessageId: String"))
        #expect(!Documents.listMessagesInThread.contains("shouldCollapseThreads"))
    }

    @Test func aServerOffersThreadsWhenItsMessageQueryTakesTheThreadArgument() {
        #expect(!ServerCapabilities().offersMessageThreads)
        #expect(!ServerCapabilities(listMessageArgumentNames: ["conversationId", "latestMessageCount"]).offersMessageThreads)
        #expect(ServerCapabilities(listMessageArgumentNames: ["threadRootMessageId"]).offersMessageThreads)
    }

    @Test func theCapabilitiesAreReadFromTheMessageQueryOfTheSchema() async {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "__schema": [
                    "queryType": ["fields": [["name": "listTickets", "args": []], ["name": "listConversationMessages", "args": [["name": "threadRootMessageId"]]]]],
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

@Suite struct ThreadReplyLineTests {
    @Test func aTranscriptKnowsTheThreadAReplyIsIn() {
        var transcript = Transcript()
        transcript.load(
            messages: [
                ConversationMessage(id: "m1", role: "assistant", content: .string("Hello"), threadReplyCount: 1),
                ConversationMessage(id: "m2", role: "user", content: .string("Why?"), threadRootMessageId: "m1"),
                ConversationMessage(id: "m3", role: "user", content: .string("Thanks")),
            ], questions: [], approvals: [], isRunning: false)
        #expect(transcript.replyThreadRoot(of: "m2") == "m1")
        #expect(transcript.replyThreadRoot(of: "m1") == nil)
        #expect(transcript.replyThreadRoot(of: "m3") == nil)
    }
}

@Suite struct ThreadBarTests {
    @Test func aMessageIsPartOfTheThreadItIsAReplyInOrTheOneItHolds() {
        let root = ChatMessage(ConversationMessage(id: "m1", role: "user", threadReplyCount: 2))
        let reply = ChatMessage(ConversationMessage(id: "m2", role: "user", threadRootMessageId: "m1"))
        let plain = ChatMessage(ConversationMessage(id: "m3", role: "user"))
        #expect(root.threadKey == "m1" && reply.threadKey == "m1" && plain.threadKey == nil)
        var transcript = Transcript()
        transcript.load(
            messages: [
                ConversationMessage(id: "m1", role: "user", content: .string("Q"), threadReplyCount: 1),
                ConversationMessage(id: "m2", role: "assistant", content: .string("A"), threadRootMessageId: "m1"),
                ConversationMessage(id: "m3", role: "user", content: .string("Next")),
            ], questions: [], approvals: [], isRunning: false)
        #expect(transcript.threadKey(ofMessage: "m1") == "m1")
        #expect(transcript.threadKey(ofMessage: "m2") == "m1")
        #expect(transcript.threadKey(ofMessage: "m3") == nil)
    }

    @Test func theThreadRootIsAskedAfterAReply() async {
        let (connection, _) = scriptedConnection { operation, _ in
            operation == "GetMessageThreadRoot" ? ["GetMessageThreadRoot": ["threadRootMessageId": "q1"]] : [:]
        }
        let root = await connection.messageThreadRoot(conversationId: "c1", messageId: "a1")
        #expect(root == "q1")
    }
}

@Suite struct MessageLinkTests {
    let server = try! ServerAddress("https://portal.example.test")

    @Test func aChatMessageLinkIsReadAndWritten() throws {
        let url = MessagePermalink.chatMessage(server: server, chatId: "chat01", messageId: "m7")
        #expect(url.absoluteString == "https://portal.example.test/chat/chat01/m7")
        #expect(PortalLink(url: url, server: server) == .chatMessage(chatId: "chat01", messageId: "m7"))
        #expect(PortalLink(path: "/chat/chat01/m7") == .chatMessage(chatId: "chat01", messageId: "m7"))
        // One segment after `/chat` is a conversation; two are a message of a chat.
        #expect(PortalLink(path: "/chat/chat01") == .conversation(id: "chat01"))
        #expect(PortalLink.chatMessage(chatId: "chat01", messageId: "m7").path == "/chat/chat01/m7")
    }

    @Test func anAssistantMessageLinkCarriesAFragment() {
        let url = MessagePermalink.assistantMessage(server: server, conversationId: "conv01", messageId: "m7")
        #expect(url.absoluteString == "https://portal.example.test/chat/conv01#message-m7")
        #expect(PortalLink(url: url, server: server) == .conversation(id: "conv01"))
    }

    @Test func linksAndCallHistoryAreOfferedByTheSchema() {
        #expect(!ServerCapabilities().offersMessageLinks && !ServerCapabilities().offersChatCallHistory)
        #expect(ServerCapabilities(mutationNames: ["OpenChatMessage"]).offersMessageLinks)
        #expect(ServerCapabilities(queryNames: ["ListChatCalls"]).offersChatCallHistory)
    }

    @Test func aCallListDecodesWithItsCounts() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            ["ListChatCalls": ["calls": [["id": "call1", "messageId": "m3", "recordingCount": 2, "transcriptSegmentCount": 5]], "meta": ["totalCount": 9]]]
        }
        let page = try await connection.pastChatCalls(chatId: "chat01", first: 20)
        #expect(page.totalCount == 9)
        #expect(page.calls.first?.recordingCount == 2 && page.calls.first?.messageId == "m3")
    }
}

@Suite struct ChatLinkPreviewRuleTests {
    @Test func aBareChatMessagePathMayHoldALink() {
        #expect(LinkPreviewRules.mayHoldLink("/chat/abc/def"))
        #expect(LinkPreviewRules.mayHoldLink("Here it is: /chat/abc/def"))
        #expect(!LinkPreviewRules.mayHoldLink("Let us chat about it"))
        #expect(!LinkPreviewRules.mayHoldLink("the chat/abc idea"))
    }
}

/// A call with the assistant reads aloud only the runs of its own place: its thread, or the main history.
@Suite struct ThreadCallHearingTests {
    private func words(inThread root: String?) -> ConversationEvent {
        ConversationEvent(type: "text_delta", runId: "run01", textDelta: .init(messageId: "answer01", text: "Door 4 is slow"), threadRootMessageId: root)
    }

    @Test func aCallInAThreadHearsThatThreadAlone() {
        #expect(ThreadRouting.isHeardInCall(words(inThread: "root01"), callThreadRootMessageId: "root01"))
        #expect(!ThreadRouting.isHeardInCall(words(inThread: "root02"), callThreadRootMessageId: "root01"))
        #expect(!ThreadRouting.isHeardInCall(words(inThread: nil), callThreadRootMessageId: "root01"))
    }

    @Test func aCallOnTheMainHistoryDoesNotHearAThreadsRun() {
        #expect(ThreadRouting.isHeardInCall(words(inThread: nil), callThreadRootMessageId: nil))
        #expect(!ThreadRouting.isHeardInCall(words(inThread: "root01"), callThreadRootMessageId: nil))
    }

    @Test func whatIsNotARunsWordsIsForEveryCall() {
        let title = ConversationEvent(type: "conversation_updated", runId: nil)
        #expect(ThreadRouting.isHeardInCall(title, callThreadRootMessageId: "root01"))
    }
}
