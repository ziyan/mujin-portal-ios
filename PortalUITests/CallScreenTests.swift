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

    /// A page opened while the call covers the screen, such as from a notification, shows: the call shrinks to its bar and goes on.
    func testAPageOpenedDuringTheCallShrinksTheCallToItsBar() {
        let app = DemoApp.launch(screen: "call-push")
        let leave = DemoApp.element(app, "leaveCallButton")
        XCTAssertTrue(DemoApp.waitUntilExists(leave, timeout: 60), "The call screen did not open.\n\(app.debugDescription)")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: leave)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 30), .completed, "The page opened behind the call.\n\(app.debugDescription)")
        // The call goes on in the app's bar, or, where the page shows the call under its own header, in that page's strip.
        let ongoingCall = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["callBar", "ongoingCallStrip"])).firstMatch
        XCTAssertTrue(DemoApp.waitUntilExists(ongoingCall, timeout: 15), "The call did not go on in its bar.\n\(app.debugDescription)")
    }

    /// A dropped call says what is happening and keeps its controls.
    func testALostConnectionSaysItIsReconnecting() {
        let app = DemoApp.launch(screen: "call-reconnecting")
        let status = app.staticTexts["Reconnecting\u{2026}"]
        XCTAssertTrue(status.waitForExistence(timeout: 60), "The call does not say it is reconnecting.\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["Leave call"].exists, "A person can always leave a call that is reconnecting.\n\(app.debugDescription)")
    }
}
