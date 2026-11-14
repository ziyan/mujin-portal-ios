import XCTest

/// A reply goes in a thread: the main history of a chat or a conversation shows how many replies a message has, and a tap opens the
/// thread alone, with its own composer and a way back.
@MainActor
final class ThreadTests: XCTestCase {
    private static let chatRootText = "The dock door 4 sensor has been flickering since this morning."
    private static let chatReplyText = "I saw it too. The cable looks loose at the frame."
    private static let chatMainText = "Shift change moves to 14:00 on Friday."
    private static let chatLonelyText = "Thanks, I will check door 4 after lunch."
    private static let chatMentionText = "which doors reported the most sensor changes today?"
    private static let assistantRootText = "Door 4 had the most faults this week"
    private static let assistantReplyText = "Two of the nine were real faults."
    private static let assistantMainText = "Remind me to check the door 4 wiring on Friday."

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func message(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The title of a thread screen: "Thread" and the name of the chat.
    private func threadTitle(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Thread")).firstMatch
    }

    private func replyControl(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(identifier: "threadReplyControl").matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func assertOpensThread(_ app: XCUIApplication, replies: String, shows: String, leavesOut: String, file: StaticString = #filePath, line: UInt = #line) {
        let control = replyControl(app, containing: replies)
        XCTAssertTrue(control.waitForExistence(timeout: 60), "There is no \"\(replies)\" under the message.\n\(app.debugDescription)", file: file, line: line)
        // The chat opens at its end, so a message near the top has to be scrolled to.
        DemoApp.scrollToElement(control, in: app, file: file, line: line)
        control.tap()
        XCTAssertTrue(threadTitle(app).waitForExistence(timeout: 30), "The thread did not open.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertTrue(message(app, shows).waitForExistence(timeout: 30), "The thread does not show its reply.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertFalse(message(app, leavesOut).exists, "The thread shows a message of the main history.\n\(app.debugDescription)", file: file, line: line)
    }

    // MARK: a chat with people

    func testTheMainHistoryOfAChatShowsEveryMessageAndCountsRepliesOnTheirRoot() {
        let app = DemoApp.launch(screen: "thread-chat")
        XCTAssertTrue(message(app, Self.chatMainText).waitForExistence(timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        XCTAssertTrue(replyControl(app, containing: "3 replies").exists, "The message with a thread does not say how many replies it has.\n\(app.debugDescription)")
        // A question with its one answer needs no count.
        XCTAssertFalse(replyControl(app, containing: "1 reply").exists, "A thread of one reply shows a count.\n\(app.debugDescription)")
        XCTAssertTrue(message(app, Self.chatReplyText).exists, "A reply is missing from the main history.\n\(app.debugDescription)")
    }

    func testATapOnAReplyInTheMainHistoryOpensItsThread() {
        let app = DemoApp.launch(screen: "thread-chat")
        let reply = message(app, Self.chatReplyText)
        XCTAssertTrue(reply.waitForExistence(timeout: 60), "The reply is not in the main history.\n\(app.debugDescription)")
        DemoApp.scrollToElement(reply, in: app)
        reply.tap()
        XCTAssertTrue(threadTitle(app).waitForExistence(timeout: 30), "The thread did not open.\n\(app.debugDescription)")
        XCTAssertTrue(message(app, Self.chatRootText).waitForExistence(timeout: 30), "The thread does not start with its root.\n\(app.debugDescription)")
        XCTAssertFalse(message(app, Self.chatMainText).exists, "The thread shows a message of the main history.\n\(app.debugDescription)")
    }

    /// A message of the main history with no replies yet opens as its own thread: the message, and a composer that replies in it.
    func testATapOnAMessageWithNoRepliesOpensItsThread() {
        let app = DemoApp.launch(screen: "thread-chat")
        let lonely = message(app, Self.chatLonelyText)
        XCTAssertTrue(DemoApp.waitUntilExists(lonely, timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        DemoApp.scrollToElement(lonely, in: app)
        lonely.tap()
        assertThreadOpenToReply(app)
        XCTAssertFalse(message(app, Self.chatMainText).exists, "The thread shows another message of the main history.\n\(app.debugDescription)")
    }

    /// A tap on the words of a thread's root, not its count of replies, opens the thread.
    func testATapOnTheWordsOfAThreadsRootOpensItsThread() {
        let app = DemoApp.launch(screen: "thread-chat")
        let root = message(app, Self.chatRootText)
        XCTAssertTrue(DemoApp.waitUntilExists(root, timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        DemoApp.scrollToElement(root, in: app)
        root.tap()
        assertThreadOpenToReply(app)
        XCTAssertTrue(message(app, Self.chatReplyText).waitForExistence(timeout: 30), "The thread does not show its replies.\n\(app.debugDescription)")
    }

    /// A tap on the @mention at the start of a message opens its thread, as a tap on its other words does.
    func testATapOnAMentionOpensTheMessagesThread() {
        let app = DemoApp.launch(screen: "thread-chat")
        let mentioning = message(app, Self.chatMentionText)
        XCTAssertTrue(DemoApp.waitUntilExists(mentioning, timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        DemoApp.scrollToElement(mentioning, in: app)
        // The mention is the first words of the message.
        mentioning.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        assertThreadOpenToReply(app)
    }

    private func assertThreadOpenToReply(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(DemoApp.waitUntilExists(threadTitle(app), timeout: 30), "The thread did not open.\n\(app.debugDescription)", file: file, line: line)
        let field = DemoApp.element(app, "chatMessageField")
        XCTAssertTrue(DemoApp.waitUntilExists(field, timeout: 30), "The thread has no composer.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertTrue(DemoApp.waitUntilLabel(field, contains: "Reply in thread", timeout: 10), "The composer does not reply in the thread: \"\(field.label)\".", file: file, line: line)
    }

    func testAReplyInTheMainHistoryHasABarAndSaysWhatItCommentsOn() {
        let app = DemoApp.launch(screen: "thread-chat")
        XCTAssertTrue(message(app, Self.chatMainText).waitForExistence(timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        // The third message of the thread is the first reply after other messages: it says what it comments on.
        let line = app.buttons.matching(identifier: "threadCommentLine").firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 30), "No reply says which message it comments on.\n\(app.debugDescription)")
        XCTAssertTrue(line.label.contains("Commented on"), "The line does not say what it is.\n\(line.label)")
        XCTAssertTrue(line.label.contains("dock door 4 sensor"), "The line does not start the message it comments on.\n\(line.label)")
    }

    func testAnOldReplyKeepsItsQuoteInTheMainHistory() {
        let app = DemoApp.launch(screen: "thread-chat")
        XCTAssertTrue(message(app, "Fine by me.").waitForExistence(timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        // The quote of the message it answers sits above the reply, named by its author.
        XCTAssertTrue(
            message(app, "Jordan Placeholder, \(Self.chatMainText)").waitForExistence(timeout: 30), "The old reply lost its quote.\n\(app.debugDescription)")
    }

    func testATapOnTheCountOpensTheThreadAndBackComesBackToTheChat() {
        let app = DemoApp.launch(screen: "thread-chat")
        XCTAssertTrue(message(app, Self.chatMainText).waitForExistence(timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        assertOpensThread(app, replies: "3 replies", shows: Self.chatReplyText, leavesOut: Self.chatMainText)
        XCTAssertTrue(message(app, Self.chatRootText).exists, "The thread does not start with the message it hangs from.\n\(app.debugDescription)")
        DemoApp.goBack(app)
        XCTAssertTrue(message(app, Self.chatMainText).waitForExistence(timeout: 30), "Back did not return to the chat.\n\(app.debugDescription)")
        XCTAssertFalse(threadTitle(app).exists, "The thread is still open.\n\(app.debugDescription)")
    }

    func testAReplySentInAThreadStaysInTheThreadAndCountsInTheChat() {
        let app = DemoApp.launch(screen: "thread-chat-open")
        XCTAssertTrue(message(app, Self.chatReplyText).waitForExistence(timeout: 60), "The thread did not open.\n\(app.debugDescription)")
        let field = DemoApp.element(app, "chatMessageField")
        XCTAssertTrue(field.waitForExistence(timeout: 30), "The thread has no composer.\n\(app.debugDescription)")
        field.tap()
        field.typeText("I can look at it after lunch")
        DemoApp.button(app, "chatSendButton").tap()
        XCTAssertTrue(message(app, "I can look at it after lunch").waitForExistence(timeout: 30), "The reply did not appear in the thread.\n\(app.debugDescription)")
        DemoApp.goBack(app)
        XCTAssertTrue(replyControl(app, containing: "4 replies").waitForExistence(timeout: 30), "The chat did not count the new reply.\n\(app.debugDescription)")
        XCTAssertTrue(message(app, "I can look at it after lunch").exists, "The reply is missing from the main history.\n\(app.debugDescription)")
    }

    func testTheAssistantAtWorkInAThreadShowsOneSetOfDots() {
        let app = DemoApp.launch(screen: "thread-chat-working")
        XCTAssertTrue(message(app, Self.chatMainText).waitForExistence(timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.element(app, "typingBubble").waitForExistence(timeout: 30), "The typing dots are not shown.\n\(app.debugDescription)")
        XCTAssertFalse(
            replyControl(app, containing: "Working on an answer").exists,
            "The message shows a second set of dots for the same turn.\n\(app.debugDescription)")
    }

    func testANotificationAboutAReplyOpensTheThread() {
        let app = DemoApp.launch(screen: "thread-push")
        XCTAssertTrue(message(app, Self.chatReplyText).waitForExistence(timeout: 60), "The notification did not open the thread.\n\(app.debugDescription)")
        XCTAssertTrue(threadTitle(app).waitForExistence(timeout: 30), "The thread is not on screen.\n\(app.debugDescription)")
        DemoApp.goBack(app)
        XCTAssertTrue(message(app, Self.chatMainText).waitForExistence(timeout: 30), "Back from the thread did not reach the chat.\n\(app.debugDescription)")
    }

    // MARK: a conversation with the assistant

    /// A turn at work shows one thing while it works: the typing dots below what it has said, and no spinner on its steps.
    func testATurnAtWorkShowsOnlyTheTypingDots() {
        let app = DemoApp.launch(screen: "conversation:conversation-working")
        XCTAssertTrue(
            app.staticTexts["I'll read this week's pick rates for both cells first."].waitForExistence(timeout: 60),
            "The assistant's progress line is not shown.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.element(app, "typingBubble").waitForExistence(timeout: 30), "The typing dots are not shown.\n\(app.debugDescription)")
        XCTAssertEqual(app.activityIndicators.count, 0, "Something else shows the turn at work.\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["Working on an answer…"].exists, "The message also says the assistant is working.")
    }

    func testTheMainHistoryOfAConversationShowsEveryMessageAndCountsRepliesOnTheirRoot() {
        let app = DemoApp.launch(screen: "thread-conversation")
        XCTAssertTrue(message(app, Self.assistantMainText).waitForExistence(timeout: 60), "The conversation did not open.\n\(app.debugDescription)")
        XCTAssertTrue(replyControl(app, containing: "3 replies").exists, "The answer with a thread does not say how many replies it has.\n\(app.debugDescription)")
        XCTAssertTrue(message(app, Self.assistantReplyText).exists, "A reply is missing from the main history.\n\(app.debugDescription)")
        // The step rows are off by default, and a reply that follows its own thread does not say what it comments on.
        XCTAssertFalse(app.staticTexts["What it did"].exists, "A step row is shown with tool call details off.\n\(app.debugDescription)")
        XCTAssertFalse(
            app.buttons.matching(identifier: "threadCommentLine").firstMatch.exists,
            "A reply right under its thread says what it comments on.\n\(app.debugDescription)")
    }

    func testATapOnTheCountOpensTheConversationThreadAndBackReturns() {
        let app = DemoApp.launch(screen: "thread-conversation")
        XCTAssertTrue(message(app, Self.assistantMainText).waitForExistence(timeout: 60), "The conversation did not open.\n\(app.debugDescription)")
        assertOpensThread(app, replies: "3 replies", shows: Self.assistantReplyText, leavesOut: Self.assistantMainText)
        XCTAssertTrue(message(app, Self.assistantRootText).exists, "The thread does not start with the answer it hangs from.\n\(app.debugDescription)")
        DemoApp.goBack(app)
        XCTAssertTrue(message(app, Self.assistantMainText).waitForExistence(timeout: 30), "Back did not return to the conversation.\n\(app.debugDescription)")
    }

    func testATapOnAConversationMessageWithNoRepliesOpensItsOwnThread() {
        let app = DemoApp.launch(screen: "thread-conversation")
        let single = message(app, Self.assistantMainText)
        XCTAssertTrue(single.waitForExistence(timeout: 60), "The conversation did not open.\n\(app.debugDescription)")
        // The last message sits just above the composer, below the band a scroll aims for: it is tapped where it is when it can be.
        if !DemoApp.waitUntilHittable(single) { DemoApp.scrollToElement(single, in: app) }
        // The words themselves, not the bubble around them.
        single.tap()
        XCTAssertTrue(threadTitle(app).waitForExistence(timeout: 30), "A tap on a message with no replies opened no thread.\n\(app.debugDescription)")
        XCTAssertTrue(message(app, Self.assistantMainText).waitForExistence(timeout: 30), "The thread does not show its message.\n\(app.debugDescription)")
        XCTAssertFalse(message(app, Self.assistantReplyText).exists, "The thread shows a message of another thread.\n\(app.debugDescription)")
        DemoApp.goBack(app)
        XCTAssertTrue(replyControl(app, containing: "3 replies").waitForExistence(timeout: 30), "Back did not return to the conversation.\n\(app.debugDescription)")
    }

    func testAReplyInAConversationThreadIsAnsweredInTheThread() {
        let app = DemoApp.launch(screen: "thread-conversation-open")
        // The thread opens on top of the conversation as the app starts; the first queries may meet an app too busy to answer.
        XCTAssertTrue(DemoApp.waitUntilExists(threadTitle(app), timeout: 60), "The thread did not open.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.waitUntilExists(message(app, Self.assistantReplyText), timeout: 30), "The thread does not show its reply.\n\(app.debugDescription)")
        let field = DemoApp.element(app, "messageField")
        XCTAssertTrue(DemoApp.waitUntilExists(field, timeout: 30), "The thread has no composer.\n\(app.debugDescription)")
        field.tap()
        field.typeText("Is it urgent")
        DemoApp.button(app, "sendButton").tap()
        XCTAssertTrue(message(app, "Is it urgent").waitForExistence(timeout: 30), "The reply did not appear in the thread.\n\(app.debugDescription)")
        // The demo's feed events do not reach a test run, so the answer is read from the history when the conversation comes back.
        Thread.sleep(forTimeInterval: 4)
        DemoApp.goBack(app)
        XCTAssertTrue(message(app, "Is it urgent").waitForExistence(timeout: 30), "The reply is missing from the main history.\n\(app.debugDescription)")
        XCTAssertTrue(message(app, "This is a demo answer").waitForExistence(timeout: 30), "The answer is missing from the main history.\n\(app.debugDescription)")
    }

    // MARK: links and past calls

    func testALinkToAMessageOpensTheThreadItIsIn() {
        let app = DemoApp.launch(screen: "thread-link")
        XCTAssertTrue(threadTitle(app).waitForExistence(timeout: 60), "The link did not open the thread.\n\(app.debugDescription)")
        XCTAssertTrue(message(app, "Can someone tighten it before the afternoon shift?").waitForExistence(timeout: 30), "The thread does not show the message.\n\(app.debugDescription)")
    }

    func testTheCallsOfAChatAreListed() {
        let app = DemoApp.launch(screen: "chat-call-history")
        let row = DemoApp.element(app, "pastCallRow")
        XCTAssertTrue(row.waitForExistence(timeout: 60), "The chat lists no past call.\n\(app.debugDescription)")
        XCTAssertTrue(message(app, "Missed").waitForExistence(timeout: 30), "The missed call is not listed.\n\(app.debugDescription)")
    }

    func testACallOpensToWhoSaidWhatAndItsRecordings() {
        let app = DemoApp.launch(screen: "chat-call-history-detail")
        XCTAssertTrue(message(app, "Door 4 is flickering again.").waitForExistence(timeout: 60), "The call does not show what was said.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.element(app, "callRecording-rec1").exists, "The call does not offer its recording.\n\(app.debugDescription)")
    }
}
