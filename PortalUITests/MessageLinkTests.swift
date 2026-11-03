import XCTest

/// A link in a chat message must open when it is tapped, in a chat between people and in the assistant's conversation, and a
/// long press on a message must still open its actions. The demo's `chat-links` and `conversation-links` screens hold one
/// message per kind of link, each holding nothing but the link, so a tap at the start of its text is a tap on the link.
@MainActor
final class MessageLinkTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// The text of a message, found by what it says.
    private func messageText(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        let link = app.links[text]
        if link.waitForExistence(timeout: 3) { return link }
        return app.staticTexts[text]
    }

    /// Scrolls the chat, up to the older messages first, until the element can be tapped.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 45), "\(element) never appeared.\n\(app.debugDescription)", file: file, line: line)
        var attempts = 0
        while !element.isHittable && attempts < 16 {
            if attempts < 8 { app.swipeDown() } else { app.swipeUp() }
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) cannot be tapped", file: file, line: line)
    }

    /// A point on the first letters of the element's text, which is where the link of a one-link message starts.
    private func start(of element: XCUIElement) -> XCUICoordinate {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 20, dy: 0))
    }

    private func isShown(_ app: XCUIApplication, _ identifier: String) -> Bool {
        DemoApp.element(app, identifier).waitForExistence(timeout: 10)
    }

    /// Taps the link whose text is `text` and checks that the web page `address` was opened in the Safari view.
    private func checkWebLink(screen: String, text: String, address: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = DemoApp.launch(screen: screen)
        let link = messageText(app, text)
        reveal(link, in: app, file: file, line: line)
        start(of: link).tap()
        XCTAssertTrue(isShown(app, "safariPageAddress"), "Tapping the link \"\(text)\" opened nothing", file: file, line: line)
        XCTAssertEqual(DemoApp.element(app, "safariPageAddress").label, address, file: file, line: line)
        DemoApp.element(app, "safariPageDone").tap()
    }

    /// Taps the link whose text is `text` and checks that the Portal page it names was opened.
    private func checkPortalLink(screen: String, text: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = DemoApp.launch(screen: screen)
        let link = messageText(app, text)
        reveal(link, in: app, file: file, line: line)
        start(of: link).tap()
        XCTAssertTrue(isShown(app, "linkedPageClose"), "Tapping the link \"\(text)\" opened nothing", file: file, line: line)
        DemoApp.element(app, "linkedPageClose").tap()
    }

    /// Whether anything that a link opens, or the actions of a message, is on the screen.
    private func openedAnything(_ app: XCUIApplication) -> Bool {
        ["safariPageAddress", "linkedPageClose", "citationPageClose"].contains { DemoApp.element(app, $0).exists } || app.buttons["Close"].exists
    }

    // MARK: - A chat between people

    func testChatBareAddress() {
        checkWebLink(screen: "chat-links", text: "https://example.test/docs/plain", address: "https://example.test/docs/plain")
    }

    func testChatMarkdownLink() {
        checkWebLink(screen: "chat-links", text: "Pressure checklist", address: "https://example.test/docs/markdown")
    }

    func testChatPortalPageLink() {
        checkPortalLink(screen: "chat-links", text: "Gripper ticket")
    }

    func testChatLinkInTable() {
        checkWebLink(screen: "chat-links", text: "Table checklist", address: "https://example.test/docs/table")
    }

    func testChatLinkInList() {
        checkWebLink(screen: "chat-links", text: "List checklist", address: "https://example.test/docs/list")
    }

    func testChatLinkInQuote() {
        checkWebLink(screen: "chat-links", text: "Quote checklist", address: "https://example.test/docs/quote")
    }

    func testChatLongPressOpensActions() {
        let app = DemoApp.launch(screen: "chat-links")
        let words = app.staticTexts["Hi Alex, I saw the gripper ticket. Can you send the pressure log?"]
        reveal(words, in: app)
        words.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10), "A long press on a message did not open its actions")
    }

    func testChatLongPressNextToALinkOpensActions() {
        let app = DemoApp.launch(screen: "chat-links")
        let message = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Notes:'")).firstMatch
        reveal(message, in: app)
        start(of: message).press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10), "A long press beside a link did not open the message's actions")
        XCTAssertFalse(DemoApp.element(app, "safariPageAddress").exists, "A long press followed the link")
    }

    func testChatTapOnPlainTextDoesNothing() {
        let app = DemoApp.launch(screen: "chat-links")
        let words = app.staticTexts["Hi Alex, I saw the gripper ticket. Can you send the pressure log?"]
        reveal(words, in: app)
        words.tap()
        sleep(2)
        XCTAssertFalse(openedAnything(app), "A tap on plain text opened something")
    }

    // MARK: - The assistant's conversation

    func testConversationMarkdownLink() {
        checkWebLink(screen: "conversation-links", text: "Assistant checklist", address: "https://example.test/docs/assistant")
    }

    func testConversationBareAddress() {
        checkWebLink(screen: "conversation-links", text: "https://example.test/docs/assistant-plain", address: "https://example.test/docs/assistant-plain")
    }

    func testConversationPortalPageLink() {
        checkPortalLink(screen: "conversation-links", text: "Assistant ticket")
    }

    func testConversationMemoryCitation() {
        let app = DemoApp.launch(screen: "conversation-links")
        let link = messageText(app, "Docks")
        reveal(link, in: app)
        start(of: link).tap()
        XCTAssertTrue(isShown(app, "citationPageClose"), "Tapping the memory citation opened nothing")
        DemoApp.element(app, "citationPageClose").tap()
    }

    func testConversationLinkInList() {
        checkWebLink(screen: "conversation-links", text: "Assistant list checklist", address: "https://example.test/docs/assistant-list")
    }

    func testConversationLinkInQuote() {
        checkWebLink(screen: "conversation-links", text: "Assistant quote checklist", address: "https://example.test/docs/assistant-quote")
    }

    func testConversationLinkInTable() {
        checkWebLink(screen: "conversation-links", text: "Assistant table checklist", address: "https://example.test/docs/assistant-table")
    }

    func testConversationLongPressOpensActions() {
        let app = DemoApp.launch(screen: "conversation-links")
        let words = app.staticTexts["A plain item"]
        reveal(words, in: app)
        words.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10), "A long press on an answer did not open its actions")
    }

    func testConversationTapOnPlainTextDoesNothing() {
        let app = DemoApp.launch(screen: "conversation-links")
        let words = app.staticTexts["A plain item"]
        reveal(words, in: app)
        words.tap()
        sleep(2)
        XCTAssertFalse(openedAnything(app), "A tap on plain text opened something")
    }
}
