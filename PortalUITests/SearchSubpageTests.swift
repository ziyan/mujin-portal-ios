import XCTest

/// A search row for a page below a controller opens that page, not the controller.
@MainActor
final class SearchSubpageTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testBackupsRowOpensTheBackups() {
        let app = DemoApp.launch(screen: "search-subpage", persona: "staff")
        let row = app.staticTexts["Backups"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The page of the controller is not offered.\n\(app.debugDescription)")
        row.tap()
        XCTAssertTrue(DemoApp.element(app, "linkedPageClose").waitForExistence(timeout: 15), "The row opened nothing.\n\(app.debugDescription)")
        XCTAssertTrue(app.navigationBars["Backups"].waitForExistence(timeout: 15), "The row did not open the backups.\n\(app.debugDescription)")
    }
}
