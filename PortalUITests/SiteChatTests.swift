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

    func testTheChatInfoOffersNoWayToChangeWhoIsIn() {
        let app = DemoApp.launch(screen: "chat-site-info")
        XCTAssertTrue(app.staticTexts["Notify me"].waitForExistence(timeout: 60), "The chat info did not open.\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["Add people"].exists, "A site chat offers Add people.\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["Leave chat"].exists, "A site chat offers Leave chat.\n\(app.debugDescription)")
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
        XCTAssertTrue(row.waitForExistence(timeout: 60), "The site page offers no chat.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.waitUntilHittable(row, timeout: 30), "The site chat row cannot be tapped.\n\(app.debugDescription)")
        row.tap()
        XCTAssertTrue(app.staticTexts["Plant North · Example Logistics"].waitForExistence(timeout: 30), "The site chat did not open.\n\(app.debugDescription)")
    }
}
