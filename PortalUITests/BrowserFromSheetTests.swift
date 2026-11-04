import XCTest

/// The built-in browser, Safari's view and the memory page open from the screen on top, even when that screen is itself a
/// sheet. A search result opens its page in a sheet, so these tests open a result first and then follow the links on it.
@MainActor
final class BrowserFromSheetTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// Opens the search result with this row key from a search for `query`, and waits for the sheet of the page.
    private func openResult(_ rowKey: String, query: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = DemoApp.launch(screen: "search-q:\(query)")
        let row = DemoApp.button(app, "searchRow-\(rowKey)")
        XCTAssertTrue(row.waitForExistence(timeout: 90), "The search for \"\(query)\" did not find \(rowKey)", file: file, line: line)
        XCTAssertTrue(DemoApp.waitUntilHittable(row, timeout: 30), "\(rowKey) cannot be tapped", file: file, line: line)
        row.tap()
        XCTAssertTrue(DemoApp.element(app, "linkedPageClose").waitForExistence(timeout: 60), "The result \(rowKey) opened no sheet", file: file, line: line)
        return app
    }

    private func assertSheetShown(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(DemoApp.element(app, "linkedPageClose").waitForExistence(timeout: 30), "Closing the browser did not return to the sheet", file: file, line: line)
        XCTAssertFalse(DemoApp.element(app, "webBrowserClose").exists, "The browser is still shown", file: file, line: line)
    }

    // MARK: - The browser from a controller sheet

    func testControllerSheetOpensLiveWebUI() {
        let app = openResult("controller|controller01", query: "controller01")
        let row = app.buttons["Open the live web UI"]
        XCTAssertTrue(row.waitForExistence(timeout: 60), "The controller page has no live web UI row")
        row.tap()
        let close = DemoApp.element(app, "webBrowserClose")
        XCTAssertTrue(close.waitForExistence(timeout: 30), "The browser did not open over the sheet")
        close.tap()
        assertSheetShown(app)
    }

    func testControllerSheetOpensWebAppTile() {
        let app = openResult("controller|controller01", query: "controller01")
        let tile = DemoApp.button(app, "webApp.order-board")
        DemoApp.scrollToElement(tile, in: app)
        tile.tap()
        let close = DemoApp.element(app, "webBrowserClose")
        XCTAssertTrue(close.waitForExistence(timeout: 30), "The browser did not open over the sheet")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Order Board")).firstMatch.waitForExistence(timeout: 30), "The browser did not show the tapped app")
        close.tap()
        assertSheetShown(app)
    }

    // MARK: - Safari's view from a ticket sheet

    func testTicketSheetOpensWebsiteLinkInSafari() {
        let app = openResult("ticket|1", query: "gripper")
        let link = app.links["Suction cup checklist"]
        DemoApp.scrollToElement(link, in: app)
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        let address = DemoApp.element(app, "safariPageAddress")
        XCTAssertTrue(address.waitForExistence(timeout: 30), "The website link opened nothing over the sheet")
        XCTAssertEqual(address.label, "https://example.test/docs/suction")
        DemoApp.element(app, "safariPageDone").tap()
        XCTAssertTrue(DemoApp.element(app, "linkedPageClose").waitForExistence(timeout: 30), "Closing Safari did not return to the sheet")
    }

    // MARK: - Every result that opens a sheet has a way to close it

    private func checkSheetCloses(_ rowKey: String, query: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = openResult(rowKey, query: query, file: file, line: line)
        let close = DemoApp.element(app, "linkedPageClose")
        XCTAssertTrue(close.isHittable, "The Close button of \(rowKey) cannot be tapped", file: file, line: line)
        close.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 30), .completed, "The sheet of \(rowKey) did not close", file: file, line: line)
        XCTAssertTrue(DemoApp.button(app, "searchRow-\(rowKey)").waitForExistence(timeout: 30), "Closing the sheet of \(rowKey) did not return to the search", file: file, line: line)
    }

    func testControllerSheetCloses() { checkSheetCloses("controller|controller01", query: "controller01") }
    func testVirtualControllerSheetCloses() { checkSheetCloses("virtualController|virtual01", query: "training") }
    func testSiteSheetCloses() { checkSheetCloses("site|site01", query: "example yard") }
    func testCameraSheetCloses() { checkSheetCloses("camera|camera01", query: "dock door") }
    func testTicketSheetCloses() { checkSheetCloses("ticket|1", query: "gripper") }
    func testReleaseSheetCloses() { checkSheetCloses("release|release01", query: "release 4") }
    func testIncidentSheetCloses() { checkSheetCloses("incident|incident01", query: "conveyor") }

    func testNotificationInboxShortcutOpensClosableSheet() {
        let app = DemoApp.launch(screen: "search-q:notification inbox")
        let row = DemoApp.button(app, "searchRow-shortcut|page.notificationInbox")
        XCTAssertTrue(row.waitForExistence(timeout: 90), "The shortcut was not found")
        XCTAssertTrue(DemoApp.waitUntilHittable(row, timeout: 30))
        row.tap()
        let close = DemoApp.element(app, "notificationsClose")
        XCTAssertTrue(close.waitForExistence(timeout: 60), "The notifications sheet did not open")
        close.tap()
        XCTAssertTrue(DemoApp.button(app, "searchRow-shortcut|page.notificationInbox").waitForExistence(timeout: 30), "Closing the notifications did not return to the search")
    }
}
