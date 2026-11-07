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

    /// Scrolls the chat, to the older messages first, until the element can be tapped. A row that is off screen is not in the
    /// accessibility hierarchy at all, so there is no waiting for it before scrolling. Once the row is on screen, short drags
    /// move it into the band every test taps in: the floating composer covers more of the bottom than a fixed margin allows
    /// for, so a link just above it is still under it.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 20)
        var attempts = 0
        while !isClearOfBars(element, in: app) && attempts < 20 {
            if element.exists, element.frame.height > 0 {
                let isAboveBand = element.frame.midY <= app.windows.firstMatch.frame.height * 0.4
                drag(app, isUp: !isAboveBand)
            } else if attempts < 8 {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            attempts += 1
        }
        XCTAssertTrue(isClearOfBars(element, in: app), "\(element) cannot be tapped.\n\(app.debugDescription)", file: file, line: line)
    }

    private func isClearOfBars(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        return DemoApp.isInTapBand(element, in: app)
    }

    /// A short drag that stops where it ends, so the row does not fly past the band.
    private func drag(_ app: XCUIApplication, isUp: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: isUp ? 0.6 : 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: isUp ? 0.4 : 0.6))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func start(of element: XCUIElement) -> XCUICoordinate {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 20, dy: 0))
    }

    private func isShown(_ app: XCUIApplication, _ identifier: String) -> Bool {
        DemoApp.element(app, identifier).waitForExistence(timeout: 10)
    }

    /// Taps the link whose text is `text` and checks that the web page `address` was opened in the Safari view.
    private func checkWebLink(screen: String, text: String, address: String, holdSeconds: Double? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let app = DemoApp.launch(screen: screen)
        let link = messageText(app, text)
        reveal(link, in: app, file: file, line: line)
        if let holdSeconds { start(of: link).press(forDuration: holdSeconds) } else { start(of: link).tap() }
        XCTAssertTrue(isShown(app, "safariPageAddress"), "Tapping the link \"\(text)\" opened nothing. The link is at \(link.frame) in a window of \(app.windows.firstMatch.frame).\n\(app.debugDescription)", file: file, line: line)
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

    func testChatControllerPath() {
        checkPortalLink(screen: "chat-links", text: "controller01")
    }

    func testChatControllerPathInList() {
        checkPortalLink(screen: "chat-links", text: "controller02")
    }

    func testChatSitePath() {
        checkPortalLink(screen: "chat-links", text: "Site by path")
    }

    func testChatTicketPath() {
        checkPortalLink(screen: "chat-links", text: "Ticket by path")
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
        let words = app.staticTexts["A plain item"]
        reveal(words, in: app)
        words.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10), "A long press on a message did not open its actions")
    }

    /// A finger rests on the screen longer than a synthesized tap does, but still shorter than the long press that opens the actions.
    func testChatMarkdownLinkHeldForAFifthOfASecond() {
        checkWebLink(screen: "chat-links", text: "Pressure checklist", address: "https://example.test/docs/markdown", holdSeconds: 0.2)
    }

    func testChatMarkdownLinkHeldForAThirdOfASecond() {
        checkWebLink(screen: "chat-links", text: "Pressure checklist", address: "https://example.test/docs/markdown", holdSeconds: 0.3)
    }

    func testChatBareAddressHeldForAFifthOfASecond() {
        checkWebLink(screen: "chat-links", text: "https://example.test/docs/plain", address: "https://example.test/docs/plain", holdSeconds: 0.2)
    }

    func testChatTapOnPlainTextDoesNothing() {
        let app = DemoApp.launch(screen: "chat-links")
        let words = app.staticTexts["A plain item"]
        reveal(words, in: app)
        words.tap()
        sleep(2)
        XCTAssertFalse(openedAnything(app), "A tap on plain text opened something")
    }

    // MARK: - The assistant's conversation

    func testConversationMarkdownLink() {
        checkWebLink(screen: "conversation-links", text: "Assistant checklist", address: "https://example.test/docs/assistant")
    }

    func testConversationMarkdownLinkHeldForAFifthOfASecond() {
        checkWebLink(screen: "conversation-links", text: "Assistant checklist", address: "https://example.test/docs/assistant", holdSeconds: 0.2)
    }

    func testConversationMarkdownLinkHeldForAThirdOfASecond() {
        checkWebLink(screen: "conversation-links", text: "Assistant checklist", address: "https://example.test/docs/assistant", holdSeconds: 0.3)
    }

    func testConversationBareAddress() {
        checkWebLink(screen: "conversation-links", text: "https://example.test/docs/assistant-plain", address: "https://example.test/docs/assistant-plain")
    }

    func testConversationPortalPageLink() {
        checkPortalLink(screen: "conversation-links", text: "Assistant ticket")
    }

    func testConversationControllerPath() {
        checkPortalLink(screen: "conversation-links", text: "controller03")
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
