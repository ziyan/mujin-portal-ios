import XCTest

/// A search result the app has no screen for opens in the built-in browser. The person usually taps it with the search field
/// still active, which is a screen of its own under the browser, and closing the browser must return to the results.
@MainActor
final class SearchBrowserTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Types into the search field the way a person does, which leaves it active, and returns the row.
    private func search(_ app: XCUIApplication, _ text: String, row rowKey: String) -> XCUIElement {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 60), "There is no search field.\n\(app.debugDescription)")
        field.tap()
        field.typeText(text)
        let row = DemoApp.button(app, "searchRow-\(rowKey)")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The search for \"\(text)\" did not find \(rowKey).\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.waitUntilHittable(row, timeout: 30), "\(rowKey) cannot be tapped.\n\(app.debugDescription)")
        return row
    }

    func testBrowserOpenedFromAnActiveSearchCloses() {
        let app = DemoApp.launch(screen: "search")
        let row = search(app, "help", row: "shortcut|page.help")
        row.tap()
        let close = DemoApp.element(app, "webBrowserClose")
        XCTAssertTrue(close.waitForExistence(timeout: 30), "The browser did not open.\n\(app.debugDescription)")
        XCTAssertEqual(app.keyboards.count, 0, "The keyboard stayed up over the browser.\n\(app.debugDescription)")
        close.tap()
        let deadline = Date().addingTimeInterval(10)
        while close.exists, Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertFalse(close.exists, "The browser did not close.\n\(app.debugDescription)")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Closing the browser did not return to the results.\n\(app.debugDescription)")
    }

    func testDreamsRowOpensTheAppsOwnScreen() {
        let app = DemoApp.launch(screen: "search")
        search(app, "dream", row: "shortcut|assistant.dreams").tap()
        XCTAssertTrue(DemoApp.element(app, "linkedPageClose").waitForExistence(timeout: 30), "The row opened no screen of the app.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.element(app, "webBrowserClose").exists, "The row opened the browser")
        XCTAssertTrue(app.navigationBars["Tidying up"].waitForExistence(timeout: 15), "The row did not open the dreams.\n\(app.debugDescription)")
    }
}
