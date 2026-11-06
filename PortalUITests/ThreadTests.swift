import XCTest

/// A reply goes in a thread: the main history of a chat or a conversation shows how many replies a message has, and a tap opens the
/// thread alone, with its own composer and a way back.
@MainActor
final class ThreadTests: XCTestCase {
    private static let chatRootText = "The dock door 4 sensor has been flickering since this morning."
    private static let chatReplyText = "I saw it too. The cable looks loose at the frame."
    private static let chatMainText = "Shift change moves to 14:00 on Friday."
    private static let assistantRootText = "Door 4 had the most faults this week"
    private static let assistantReplyText = "Two of the nine were real faults."
    private static let assistantMainText = "Remind me to check the door 4 wiring on Friday."

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func message(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func replyControl(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(identifier: "threadReplyControl").matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func assertOpensThread(_ app: XCUIApplication, replies: String, shows: String, leavesOut: String, file: StaticString = #filePath, line: UInt = #line) {
        let control = replyControl(app, containing: replies)
        XCTAssertTrue(control.waitForExistence(timeout: 60), "There is no \"\(replies)\" under the message.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertTrue(DemoApp.waitUntilHittable(control, timeout: 30), "The reply count cannot be tapped.\n\(app.debugDescription)", file: file, line: line)
        control.tap()
        XCTAssertTrue(app.staticTexts["Thread"].waitForExistence(timeout: 30), "The thread did not open.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertTrue(message(app, shows).waitForExistence(timeout: 30), "The thread does not show its reply.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertFalse(message(app, leavesOut).exists, "The thread shows a message of the main history.\n\(app.debugDescription)", file: file, line: line)
    }

    // MARK: a chat with people

    func testTheMainHistoryOfAChatCountsRepliesAndLeavesThemOut() {
        let app = DemoApp.launch(screen: "thread-chat")
        XCTAssertTrue(message(app, Self.chatMainText).waitForExistence(timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        XCTAssertTrue(replyControl(app, containing: "3 replies").exists, "The message with a thread does not say how many replies it has.\n\(app.debugDescription)")
        XCTAssertTrue(replyControl(app, containing: "1 reply").exists, "The assistant's answer in a thread is not counted.\n\(app.debugDescription)")
        XCTAssertFalse(message(app, Self.chatReplyText).exists, "A reply is shown in the main history.\n\(app.debugDescription)")
    }

    func testAnOldReplyKeepsItsQuoteInTheMainHistory() {
        let app = DemoApp.launch(screen: "thread-chat")
        XCTAssertTrue(message(app, "Fine by me.").waitForExistence(timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        // The message and the quote of it above the reply.
        XCTAssertGreaterThanOrEqual(
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", Self.chatMainText)).count, 2,
            "The old reply lost its quote.\n\(app.debugDescription)")
    }

    func testATapOnTheCountOpensTheThreadAndBackComesBackToTheChat() {
        let app = DemoApp.launch(screen: "thread-chat")
        XCTAssertTrue(message(app, Self.chatMainText).waitForExistence(timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        assertOpensThread(app, replies: "3 replies", shows: Self.chatReplyText, leavesOut: Self.chatMainText)
        XCTAssertTrue(message(app, Self.chatRootText).exists, "The thread does not start with the message it hangs from.\n\(app.debugDescription)")
        DemoApp.goBack(app)
        XCTAssertTrue(message(app, Self.chatMainText).waitForExistence(timeout: 30), "Back did not return to the chat.\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["Thread"].exists, "The thread is still open.\n\(app.debugDescription)")
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
        XCTAssertFalse(message(app, "I can look at it after lunch").exists, "The reply is shown in the main history.\n\(app.debugDescription)")
    }

    func testTheAssistantAtWorkIsShownOnTheMessageItIsAnswering() {
        let app = DemoApp.launch(screen: "thread-chat-working")
        XCTAssertTrue(message(app, Self.chatMainText).waitForExistence(timeout: 60), "The chat did not open.\n\(app.debugDescription)")
        XCTAssertTrue(
            replyControl(app, containing: "Working on an answer").waitForExistence(timeout: 30),
            "The message does not say the assistant is answering.\n\(app.debugDescription)")
    }

    func testANotificationAboutAReplyOpensTheThread() {
        let app = DemoApp.launch(screen: "thread-push")
        XCTAssertTrue(message(app, Self.chatReplyText).waitForExistence(timeout: 60), "The notification did not open the thread.\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Thread"].exists, "The thread is not on screen.\n\(app.debugDescription)")
        DemoApp.goBack(app)
        XCTAssertTrue(message(app, Self.chatMainText).waitForExistence(timeout: 30), "Back from the thread did not reach the chat.\n\(app.debugDescription)")
    }

    // MARK: a conversation with the assistant

    func testTheMainHistoryOfAConversationCountsRepliesAndLeavesThemOut() {
        let app = DemoApp.launch(screen: "thread-conversation")
        XCTAssertTrue(message(app, Self.assistantMainText).waitForExistence(timeout: 60), "The conversation did not open.\n\(app.debugDescription)")
        XCTAssertTrue(replyControl(app, containing: "2 replies").exists, "The answer with a thread does not say how many replies it has.\n\(app.debugDescription)")
        XCTAssertFalse(message(app, Self.assistantReplyText).exists, "A reply is shown in the main history.\n\(app.debugDescription)")
    }

    func testATapOnTheCountOpensTheConversationThreadAndBackReturns() {
        let app = DemoApp.launch(screen: "thread-conversation")
        XCTAssertTrue(message(app, Self.assistantMainText).waitForExistence(timeout: 60), "The conversation did not open.\n\(app.debugDescription)")
        assertOpensThread(app, replies: "2 replies", shows: Self.assistantReplyText, leavesOut: Self.assistantMainText)
        XCTAssertTrue(message(app, Self.assistantRootText).exists, "The thread does not start with the answer it hangs from.\n\(app.debugDescription)")
        DemoApp.goBack(app)
        XCTAssertTrue(message(app, Self.assistantMainText).waitForExistence(timeout: 30), "Back did not return to the conversation.\n\(app.debugDescription)")
    }

    func testAReplyInAConversationThreadIsAnsweredInTheThread() {
        let app = DemoApp.launch(screen: "thread-conversation-open")
        XCTAssertTrue(message(app, Self.assistantReplyText).waitForExistence(timeout: 60), "The thread did not open.\n\(app.debugDescription)")
        let field = DemoApp.element(app, "messageField")
        XCTAssertTrue(field.waitForExistence(timeout: 30), "The thread has no composer.\n\(app.debugDescription)")
        field.tap()
        field.typeText("Is it urgent")
        DemoApp.button(app, "sendButton").tap()
        XCTAssertTrue(message(app, "This is a demo answer").waitForExistence(timeout: 60), "The answer did not come in the thread.\n\(app.debugDescription)")
        DemoApp.goBack(app)
        XCTAssertTrue(replyControl(app, containing: "4 replies").waitForExistence(timeout: 30), "The conversation did not count the new replies.\n\(app.debugDescription)")
        XCTAssertFalse(message(app, "This is a demo answer").exists, "The answer is shown in the main history.\n\(app.debugDescription)")
    }
}
