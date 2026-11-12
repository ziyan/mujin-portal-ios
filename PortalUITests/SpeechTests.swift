import XCTest

/// Dictation puts what the person says into the message box and sends nothing; reading aloud speaks one message at a time. Neither
/// is shown on a server that does not say it has them. The demo has no microphone and no speech: it plays a short script of heard
/// words in place of the microphone, and holds a message "being read" in place of the sound.
@MainActor
final class SpeechTests: XCTestCase {
    private static let dictatedWords = "Can you check the dock schedule for Friday"
    private static let threadMessage = "I saw it too. The cable looks loose at the frame."

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func dictateButton(_ app: XCUIApplication) -> XCUIElement {
        DemoApp.button(app, "dictateButton")
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 30) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForValue(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 30) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func fieldText(_ field: XCUIElement) -> String {
        (field.value as? String) ?? ""
    }

    private func message(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Holds the message until its actions open, and returns their Read aloud row. A press that lands while the list is still settling
    /// opens nothing, so it is made again, scrolling to the message first each time.
    private func hold(_ held: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let action = DemoApp.button(app, "readAloudAction")
        for _ in 0..<3 {
            DemoApp.scrollToElement(held, in: app)
            held.press(forDuration: 1.0)
            if action.waitForExistence(timeout: 8) { break }
        }
        return action
    }

    // MARK: - Not offered

    func testNeitherIsOfferedByAServerThatDoesNotSayItHasThem() {
        let chat = DemoApp.launch(screen: "chat:chatconv01")
        XCTAssertTrue(DemoApp.element(chat, "chatMessageField").waitForExistence(timeout: 90), "The chat did not open.\n\(chat.debugDescription)")
        XCTAssertFalse(dictateButton(chat).exists, "A server that does not say it has dictation shows the Dictate button.\n\(chat.debugDescription)")
        chat.terminate()
        let conversation = DemoApp.launch(screen: "conversation:conversation01")
        XCTAssertTrue(DemoApp.element(conversation, "messageField").waitForExistence(timeout: 90), "The conversation did not open.\n\(conversation.debugDescription)")
        XCTAssertFalse(dictateButton(conversation).exists, "A server that does not say it has dictation shows the Dictate button.\n\(conversation.debugDescription)")
    }

    // MARK: - Dictate

    func testThePeopleChatHasADictateButton() {
        let app = DemoApp.launch(screen: "dictate-chat")
        let button = dictateButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 90), "The chat has no Dictate button.\n\(app.debugDescription)")
        XCTAssertEqual(button.label, "Dictate")
    }

    func testTheConversationHasADictateButton() {
        let app = DemoApp.launch(screen: "dictate-conversation")
        let button = dictateButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 90), "The conversation has no Dictate button.\n\(app.debugDescription)")
        XCTAssertEqual(button.label, "Dictate")
    }

    private func checkDictating(screen: String, fieldIdentifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = DemoApp.launch(screen: screen)
        let button = dictateButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 90), "There is no Dictate button.\n\(app.debugDescription)", file: file, line: line)
        button.tap()
        // Listening: the button says how to stop, and the words heard so far show above the box.
        XCTAssertTrue(waitForLabel(button, "Stop dictating"), "The button does not say it is listening.\n\(app.debugDescription)", file: file, line: line)
        let caption = DemoApp.element(app, "dictationCaption")
        XCTAssertTrue(caption.waitForExistence(timeout: 30), "There is no live caption above the box.\n\(app.debugDescription)", file: file, line: line)
        // The final words go into the box, and nothing is sent.
        let field = DemoApp.element(app, fieldIdentifier)
        XCTAssertTrue(waitForValue(field, containing: Self.dictatedWords), "The words did not reach the box: \"\(fieldText(field))\".\n\(app.debugDescription)", file: file, line: line)
        XCTAssertFalse(app.staticTexts[Self.dictatedWords].exists, "The dictated words were sent.\n\(app.debugDescription)", file: file, line: line)
        // The words are the person's to edit.
        field.tap()
        field.typeText(" please")
        // A tap puts the caret wherever it lands, so only that the typing arrived beside the words is checked.
        XCTAssertTrue(waitForValue(field, containing: "please"), "The dictated words cannot be edited: \"\(fieldText(field))\".", file: file, line: line)
        // Tapping again stops it.
        button.tap()
        XCTAssertTrue(waitForLabel(button, "Dictate"), "A second tap did not stop dictating.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertFalse(DemoApp.element(app, "dictationCaption").exists, "The caption is still shown after stopping.", file: file, line: line)
        XCTAssertTrue(fieldText(field).contains(Self.dictatedWords), "Stopping took the words away.", file: file, line: line)
    }

    func testDictatingInAPeopleChatPutsTheWordsInTheBox() {
        checkDictating(screen: "dictate-chat", fieldIdentifier: "chatMessageField")
    }

    func testDictatingInAConversationPutsTheWordsInTheBox() {
        checkDictating(screen: "dictate-conversation", fieldIdentifier: "messageField")
    }

    func testSendingTheMessageStopsDictating() {
        let app = DemoApp.launch(screen: "dictate-chat-words")
        let button = dictateButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 90), "There is no Dictate button.\n\(app.debugDescription)")
        button.tap()
        XCTAssertTrue(waitForLabel(button, "Stop dictating"), "The button does not say it is listening.\n\(app.debugDescription)")
        DemoApp.button(app, "chatSendButton").tap()
        XCTAssertTrue(waitForLabel(button, "Dictate"), "Dictation went on after the message was sent.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.element(app, "dictationCaption").exists, "The caption is still shown after sending.")
        // The words that were still to come never reach the box of the next message.
        Thread.sleep(forTimeInterval: 4)
        XCTAssertFalse(fieldText(DemoApp.element(app, "chatMessageField")).contains("Friday"), "Words heard after the message was sent landed in the box.")
    }

    func testTheListeningStateShowsALiveCaption() {
        let app = DemoApp.launch(screen: "dictate-conversation-listening")
        let button = dictateButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 90), "There is no Dictate button.\n\(app.debugDescription)")
        XCTAssertEqual(button.label, "Stop dictating")
        let caption = DemoApp.element(app, "dictationCaption")
        XCTAssertTrue(caption.waitForExistence(timeout: 30), "There is no live caption.\n\(app.debugDescription)")
        XCTAssertTrue(caption.label.contains("check the dock"), "The caption does not show the words heard: \"\(caption.label)\".")
    }

    func testAThreadOfAChatAndOfAConversationHaveADictateButton() {
        for (screen, fieldIdentifier) in [("dictate-thread-chat", "chatMessageField"), ("dictate-thread-conversation", "messageField")] {
            let app = DemoApp.launch(screen: screen)
            XCTAssertTrue(DemoApp.element(app, fieldIdentifier).waitForExistence(timeout: 90), "The thread of \(screen) did not open.\n\(app.debugDescription)")
            let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Thread")).firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 30), "\(screen) is not a thread.\n\(app.debugDescription)")
            let button = dictateButton(app)
            XCTAssertTrue(button.waitForExistence(timeout: 30), "The thread of \(screen) has no Dictate button.\n\(app.debugDescription)")
            XCTAssertEqual(button.label, "Stop dictating", "The thread of \(screen) does not show it is listening.")
            XCTAssertTrue(DemoApp.element(app, "dictationCaption").exists, "The thread of \(screen) has no live caption.")
            app.terminate()
        }
    }

    // MARK: - Read aloud

    private func checkReadingAloud(screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = DemoApp.launch(screen: screen)
        // The actions of the message open by themselves in the demo.
        let action = DemoApp.button(app, "readAloudAction")
        XCTAssertTrue(action.waitForExistence(timeout: 90), "The message's actions have no Read aloud.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertTrue(action.label.contains("Read aloud"), "The action is not called Read aloud: \"\(action.label)\".", file: file, line: line)
        action.tap()
        let bar = DemoApp.element(app, "readAloudBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 30), "Nothing shows that the message is being read.\n\(app.debugDescription)", file: file, line: line)
        // Tapping Stop reading stops it.
        let stop = DemoApp.button(app, "readAloudStopButton")
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "There is no way to stop.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertEqual(stop.label, "Stop reading", file: file, line: line)
        stop.tap()
        XCTAssertTrue(waitUntilGone(bar), "Stopping did not end the reading.\n\(app.debugDescription)", file: file, line: line)
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func testAMessageOfAPeopleChatCanBeReadAloudAndStopped() {
        checkReadingAloud(screen: "read-aloud-chat")
    }

    func testAnAnswerOfAConversationCanBeReadAloudAndStopped() {
        checkReadingAloud(screen: "read-aloud-conversation")
    }

    func testTheActionTurnsIntoStopReadingWhileTheMessageIsRead() {
        let app = DemoApp.launch(screen: "read-aloud-conversation-playing")
        XCTAssertTrue(DemoApp.waitUntilExists(DemoApp.element(app, "readAloudBar"), timeout: 90), "The message is not shown as being read.\n\(app.debugDescription)")
        // The conversation opens at its end; the held message is found by its words, scrolling to it.
        let action = hold(message(app, "The checklist is at"), in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 30), "The actions of the message being read have no Read aloud row.\n\(app.debugDescription)")
        // The row's words follow the reading as the menu opens; read them once they have settled rather than at the first frame.
        let offersStop = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Stop reading"), object: action)
        XCTAssertEqual(XCTWaiter().wait(for: [offersStop], timeout: 10), .completed, "The row does not offer to stop: \"\(action.label)\".")
        action.tap()
        XCTAssertTrue(waitUntilGone(DemoApp.element(app, "readAloudBar")), "Stop reading did not end the reading.\n\(app.debugDescription)")
    }

    func testAMessageOfAThreadCanBeReadAloud() {
        let app = DemoApp.launch(screen: "dictate-thread-chat")
        let held = message(app, Self.threadMessage)
        // The thread opens as the app starts; a first query that meets an app too busy to answer is asked again.
        XCTAssertTrue(DemoApp.waitUntilExists(held, timeout: 90), "The thread did not open.\n\(app.debugDescription)")
        let action = hold(held, in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 30), "The actions of a message in a thread have no Read aloud.\n\(app.debugDescription)")
        action.tap()
        XCTAssertTrue(DemoApp.element(app, "readAloudBar").waitForExistence(timeout: 30), "The thread message is not shown as being read.\n\(app.debugDescription)")
    }

    func testStartingAnotherMessageStopsTheFirst() {
        let app = DemoApp.launch(screen: "read-aloud-conversation-playing")
        XCTAssertTrue(DemoApp.element(app, "readAloudBar").waitForExistence(timeout: 90), "The first message is not being read.\n\(app.debugDescription)")
        // Another answer of the conversation, held while the first is being read.
        let other = message(app, "Here is the summary for this week")
        let action = hold(other, in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 30), "The other message has no Read aloud.\n\(app.debugDescription)")
        XCTAssertTrue(action.label.contains("Read aloud"), "The other message offers \"\(action.label)\" while a different one is being read.")
        action.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "readAloudStopButton").count, 1, "More than one message is being read.\n\(app.debugDescription)")
    }
}
