import XCTest

/// A command running in the background marks the conversation's header with a terminal and a count; the list it opens shows each
/// command, its state, its time and its newest output, and the owner can stop one.
@MainActor
final class BackgroundCommandTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testTheHeaderShowsARunningCommandAndItsOwnerCanStopIt() {
        let app = DemoApp.launch(screen: "background-commands")
        let mark = DemoApp.button(app, "backgroundCommandsButton")
        XCTAssertTrue(DemoApp.waitUntilExists(mark, timeout: 90), "The header shows no running command.\n\(app.debugDescription)")
        XCTAssertTrue(mark.label.contains("1"), "The header does not say one command runs: \"\(mark.label)\".\n\(app.debugDescription)")
        mark.tap()
        let running = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "tail -n 200")).firstMatch
        XCTAssertTrue(DemoApp.waitUntilExists(running, timeout: 20), "The list does not show the command.\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Running"].exists, "The running command has no state chip.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.element(app, "backgroundCommandOutput").exists, "The command's output is not shown.\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Exited 0")).firstMatch.exists,
            "The finished command is not listed with its exit.\n\(app.debugDescription)")
        let stop = DemoApp.button(app, "backgroundCommandStop")
        XCTAssertTrue(stop.exists, "The owner cannot stop the running command.\n\(app.debugDescription)")
        stop.tap()
        XCTAssertTrue(DemoApp.waitUntilExists(app.staticTexts["Stopped"], timeout: 20), "Stopping did not stop it.\n\(app.debugDescription)")
    }
}
