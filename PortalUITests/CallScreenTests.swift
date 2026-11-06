import XCTest

/// The call screen fills the display from the root of the app, and closing it is a change of state the root watches.
@MainActor
final class CallScreenTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testMinimizeClosesTheCallScreen() {
        let app = DemoApp.launch(screen: "call-voice")
        let leave = DemoApp.element(app, "leaveCallButton")
        XCTAssertTrue(leave.waitForExistence(timeout: 60), "The call screen did not open.\n\(app.debugDescription)")
        app.buttons["Minimize"].firstMatch.tap()
        let deadline = Date().addingTimeInterval(10)
        while leave.exists, Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertFalse(leave.exists, "The call screen did not close.\n\(app.debugDescription)")
    }

    /// A dropped call says what is happening and keeps its controls.
    func testALostConnectionSaysItIsReconnecting() {
        let app = DemoApp.launch(screen: "call-reconnecting")
        let status = app.staticTexts["Reconnecting\u{2026}"]
        XCTAssertTrue(status.waitForExistence(timeout: 60), "The call does not say it is reconnecting.\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["Leave call"].exists, "A person can always leave a call that is reconnecting.\n\(app.debugDescription)")
    }
}
