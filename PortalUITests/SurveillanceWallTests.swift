import XCTest

/// The wall of a long list of cameras: every tile that is on screen must play, never wait. A tile that is on screen and has no
/// stream says Paused, so no tile on screen may say it, at the top of the wall or after scrolling to the end.
@MainActor
final class SurveillanceWallTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func pausedTiles(_ app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Paused'")).count
    }

    private func liveTiles(_ app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Live'")).count
    }

    func testNoTileOnScreenWaitsWhileTheWallScrolls() {
        let app = DemoApp.launch(screen: "surveillance-many")
        let firstLiveTile = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Live'")).firstMatch
        XCTAssertTrue(firstLiveTile.waitForExistence(timeout: 60), "No tile of the wall ever played")
        XCTAssertEqual(pausedTiles(app), 0, "A tile on screen is waiting at the top of the wall")

        for step in 1...8 {
            app.swipeUp()
            // Streams of the tiles that came on screen take a moment to connect; a tile waiting for a free stream would say Paused at once.
            let deadline = Date().addingTimeInterval(10)
            while liveTiles(app) == 0 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
            XCTAssertGreaterThan(liveTiles(app), 0, "No tile played after scrolling \(step) times")
            XCTAssertEqual(pausedTiles(app), 0, "A tile on screen is waiting after scrolling \(step) times")
        }
    }
}
