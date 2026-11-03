import XCTest

/// The Apps section of a controller page is a grid of tiles in one List row. A tap on one tile must open that app and no
/// other: the browser shows the app that was opened last, so an extra open would show up as the wrong title.
@MainActor
final class WebAppTileTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testAppTileOpensOnlyItsOwnApp() {
        let app = DemoApp.launch(screen: "controller-apps")
        let tile = DemoApp.element(app, "webApp.order-board")
        DemoApp.scrollToElement(tile, in: app)
        tile.tap()

        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 20), "The browser did not open")
        let title = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Order Board")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20), "The browser did not show the tapped app")
    }
}
