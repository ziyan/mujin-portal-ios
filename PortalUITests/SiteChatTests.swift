import XCTest

/// Every site has a chat for the people with access to it. Nobody picks who is in it, and a call there starts with choosing who.
@MainActor
final class SiteChatTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testASiteChatIsListedByItsSiteAndOrganization() {
        let app = DemoApp.launch(screen: "chats")
        let row = app.staticTexts["Plant North · Example Logistics"]
        XCTAssertTrue(row.waitForExistence(timeout: 60), "The site chat is not listed.\n\(app.debugDescription)")
    }

    /// The row and the tab's count say a chat was read as soon as it was, without waiting for the list to be read again.
    func testOpeningAChatClearsItsUnreadMark() {
        let app = DemoApp.launch(screen: "chats")
        let mark = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '2 unread'")).firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 60), "The chat is not marked unread.\n\(app.debugDescription)")
        let row = app.staticTexts["Sam Sample"].firstMatch
        XCTAssertTrue(DemoApp.waitUntilHittable(row, timeout: 15), "The row cannot be tapped.\n\(app.debugDescription)")
        row.tap()
        DemoApp.goBack(app)
        XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 30), "Going back left the chat on screen.\n\(app.debugDescription)")
        XCTAssertFalse(mark.waitForExistence(timeout: 5), "The chat is still marked unread.\n\(app.debugDescription)")
    }

    func testTheChatInfoOffersNoWayToChangeWhoIsIn() {
        let app = DemoApp.launch(screen: "chat-site-info")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 60), "The chat info did not open.\n\(app.debugDescription)")
        // Add people would sit right above this row, so reaching it brings that place on screen.
        let notifications = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Notify me'")).firstMatch
        XCTAssertTrue(reveal(notifications, in: app), "The chat info has no notification choice.\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["Add people"].exists, "A site chat offers Add people.\n\(app.debugDescription)")
    }

    func testChoosingWhoToCallCanBeSearched() {
        let app = DemoApp.launch(screen: "chat-site-picker")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 60), "The people cannot be searched.\n\(app.debugDescription)")
        search.tap()
        search.typeText("Quinn")
        XCTAssertTrue(app.staticTexts["Quinn Fixture"].waitForExistence(timeout: 10), "The search found nobody.\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["Robin Demo"].exists, "The search kept someone else.\n\(app.debugDescription)")
    }

    func testTheSitePageOpensItsChat() {
        let app = DemoApp.launch(screen: "site")
        let row = DemoApp.element(app, "siteChatRow")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 60), "The site page did not open.\n\(app.debugDescription)")
        XCTAssertTrue(reveal(row, in: app), "The site page offers no chat.\n\(app.debugDescription)")
        DemoApp.scrollToElement(row, in: app)
        row.tap()
        XCTAssertTrue(app.staticTexts["Plant North · Example Logistics"].waitForExistence(timeout: 30), "The site chat did not open.\n\(app.debugDescription)")
    }

    /// A list builds its rows as they come near the screen, so a row further down does not exist until the page has scrolled to it.
    private func reveal(_ row: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<12 {
            if row.waitForExistence(timeout: 3) { return true }
            app.swipeUp()
        }
        return row.exists
    }
}
