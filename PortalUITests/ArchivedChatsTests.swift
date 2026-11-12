import XCTest

/// Archived chats have a list of their own, reached from the chat list. Restoring one takes it out of that list and back into the chat
/// list.
@MainActor
final class ArchivedChatsTests: XCTestCase {
    private static let archivedTitle = "Old dock door question"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testTheChatListOpensItsArchivedChats() {
        let app = DemoApp.launch(screen: "list")
        let button = DemoApp.button(app, "archivedChatsButton")
        XCTAssertTrue(DemoApp.waitUntilExists(button, timeout: 60), "The chat list has no Archived button.\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts[Self.archivedTitle].exists, "An archived chat is in the chat list.\n\(app.debugDescription)")
        button.tap()
        XCTAssertTrue(app.staticTexts[Self.archivedTitle].waitForExistence(timeout: 30), "The archived chats are not listed.\n\(app.debugDescription)")
    }

    func testARestoredChatGoesBackToTheChatList() {
        let app = DemoApp.launch(screen: "archived-chats")
        let row = app.staticTexts[Self.archivedTitle]
        XCTAssertTrue(row.waitForExistence(timeout: 60), "The archived chats are not listed.\n\(app.debugDescription)")
        row.swipeLeft()
        let restore = app.buttons["Restore"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10), "The row offers no Restore.\n\(app.debugDescription)")
        restore.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), "The restored chat stayed in the archived list.\n\(app.debugDescription)")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[Self.archivedTitle].waitForExistence(timeout: 30), "The restored chat is not back in the chat list.\n\(app.debugDescription)")
    }
}
