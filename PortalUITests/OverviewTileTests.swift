import XCTest

/// Each tile in the site page's Overview section must open its own list and nothing else: one tap, one screen, and one
/// Back returns to the site page. A List row that holds several navigation links activates all of them on a tap, which
/// pushes the whole stack at once; the screen that comes up is then the last tile's list, and Back walks through the others.
@MainActor
final class OverviewTileTests: XCTestCase {
    /// The Overview tiles, in the order the page draws them, with the list each one opens.
    private static let tiles: [(tile: String, list: String)] = [
        ("statTile.controllers", "siteList.controllers"),
        ("statTile.virtualControllers", "siteList.virtualControllers"),
        ("statTile.alarms", "siteList.alarms"),
        ("statTile.incidents", "siteList.incidents"),
        ("statTile.tickets", "siteList.tickets"),
    ]

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func checkTile(_ tileIdentifier: String) {
        let app = DemoApp.launch(screen: "site")
        let expectedList = Self.tiles.first { $0.tile == tileIdentifier }?.list ?? ""
        let sitePage = DemoApp.element(app, "sitePage")
        XCTAssertTrue(sitePage.waitForExistence(timeout: 45), "The site page never appeared")

        let tile = DemoApp.element(app, tileIdentifier)
        DemoApp.scrollToElement(tile, in: app)
        tile.tap()

        let list = DemoApp.element(app, expectedList)
        XCTAssertTrue(list.waitForExistence(timeout: 20), "Tapping \(tileIdentifier) did not open \(expectedList)")
        for other in Self.tiles.map(\.list) where other != expectedList {
            XCTAssertFalse(DemoApp.element(app, other).exists, "Tapping \(tileIdentifier) also opened \(other)")
        }

        DemoApp.goBack(app)
        XCTAssertTrue(sitePage.waitForExistence(timeout: 10), "One Back did not return to the site page")
        XCTAssertTrue(DemoApp.element(app, tileIdentifier).isHittable, "The site page is not the screen on top after one Back")
        XCTAssertFalse(DemoApp.element(app, expectedList).exists, "\(expectedList) is still showing after Back")
    }

    func testControllersTile() { checkTile("statTile.controllers") }
    func testVirtualControllersTile() { checkTile("statTile.virtualControllers") }
    func testAlarmsTile() { checkTile("statTile.alarms") }
    func testIncidentsTile() { checkTile("statTile.incidents") }
    func testTicketsTile() { checkTile("statTile.tickets") }
}
