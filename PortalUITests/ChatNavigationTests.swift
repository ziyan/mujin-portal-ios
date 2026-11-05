import XCTest

/// A conversation stays on screen once it is open, whatever brought it there. The app used to fall back to the empty pane
/// ("Select a conversation") when the list cleared its selection while the conversation was showing.
@MainActor
final class ChatNavigationTests: XCTestCase {
    private static let mainChatMessage = "Dock door 4 is slow again; I filed a ticket."
    private static let peopleChatMessage = "That matches what I saw."

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func message(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Watches the screen for a few seconds: the message must stay and the empty pane must never come.
    private func assertStaysOpen(_ app: XCUIApplication, _ text: String, seconds: TimeInterval = 4, file: StaticString = #filePath, line: UInt = #line) {
        let shown = message(app, text)
        XCTAssertTrue(shown.waitForExistence(timeout: 30), "The conversation did not open.\n\(app.debugDescription)", file: file, line: line)
        let empty = app.staticTexts["Select a conversation"]
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            XCTAssertFalse(empty.exists, "The conversation gave way to the empty pane.\n\(app.debugDescription)", file: file, line: line)
            XCTAssertTrue(shown.exists, "The messages went away after they were drawn.\n\(app.debugDescription)", file: file, line: line)
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Taps a row of the inbox. The last rows never reach the middle of the screen, so any place that is clear of the edge will do.
    private func tapNotification(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The inbox has no such row.\n\(app.debugDescription)", file: file, line: line)
        let bottom = app.windows.firstMatch.frame.maxY * 0.9
        for _ in 0..<8 where row.frame.maxY > bottom {
            app.swipeUp()
            _ = DemoApp.waitUntilStill(row)
        }
        XCTAssertLessThanOrEqual(row.frame.maxY, bottom, "The row stays below the screen.\n\(app.debugDescription)", file: file, line: line)
        row.tap()
    }

    /// Opens the inbox from the bell of this tab.
    private func openInbox(on section: String, listDelaySeconds: Int? = nil) -> XCUIApplication {
        let app = DemoApp.launch(screen: "section:\(section)", environment: listDelaySeconds.map { ["PORTAL_DEMO_LIST_DELAY_SECONDS": String($0)] } ?? [:])
        let bell = DemoApp.element(app, "notificationsBell")
        XCTAssertTrue(bell.waitForExistence(timeout: 60), "The tab has no bell.\n\(app.debugDescription)")
        bell.tap()
        XCTAssertTrue(DemoApp.element(app, "notificationsClose").waitForExistence(timeout: 30), "The inbox did not open.\n\(app.debugDescription)")
        return app
    }

    /// From another tab, so the Chat tab has its list to load as the conversation opens.
    func testNotificationOpensTheAssistantConversation() {
        let app = openInbox(on: "tickets")
        tapNotification(app, "Main chat has a new answer")
        assertStaysOpen(app, Self.mainChatMessage)
    }

    func testNotificationOpensThePeopleChat() {
        let app = openInbox(on: "tickets")
        tapNotification(app, "A new message in the chat")
        assertStaysOpen(app, Self.peopleChatMessage)
    }

    /// From the Chat tab, where the list is already on screen under the inbox.
    func testNotificationOpensTheConversationOverTheList() {
        let app = openInbox(on: "assistant")
        tapNotification(app, "Main chat has a new answer")
        assertStaysOpen(app, Self.mainChatMessage)
    }

    func testNotificationOpensThePeopleChatOverTheList() {
        let app = openInbox(on: "assistant")
        tapNotification(app, "A new message in the chat")
        assertStaysOpen(app, Self.peopleChatMessage)
    }

    /// The list arrives after the conversation has opened, which is what a real server does.
    func testNotificationOpensTheAssistantConversationBeforeTheListArrives() {
        let app = openInbox(on: "tickets", listDelaySeconds: 3)
        tapNotification(app, "Main chat has a new answer")
        assertStaysOpen(app, Self.mainChatMessage, seconds: 6)
    }

    func testNotificationOpensThePeopleChatBeforeTheListArrives() {
        let app = openInbox(on: "tickets", listDelaySeconds: 3)
        tapNotification(app, "A new message in the chat")
        assertStaysOpen(app, Self.peopleChatMessage, seconds: 6)
    }

    func testCancelledSwipeBackKeepsTheConversation() {
        let app = DemoApp.launch(screen: "main-chat")
        XCTAssertTrue(message(app, Self.mainChatMessage).waitForExistence(timeout: 30), "The conversation did not open.\n\(app.debugDescription)")
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.5)
        assertStaysOpen(app, Self.mainChatMessage)
    }

    func testGoingBackAndInAgainDrawsTheConversation() {
        let app = DemoApp.launch(screen: "main-chat")
        XCTAssertTrue(message(app, Self.mainChatMessage).waitForExistence(timeout: 30), "The conversation did not open.\n\(app.debugDescription)")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.staticTexts["Main chat"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The list did not come back.\n\(app.debugDescription)")
        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 15), "The list came back without the tab bar.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.waitUntilHittable(row, timeout: 15), "The row cannot be tapped.\n\(app.debugDescription)")
        row.tap()
        assertStaysOpen(app, Self.mainChatMessage)
    }
}
