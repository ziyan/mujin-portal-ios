import XCTest

/// The row at the top of a conversation says there are earlier messages, reads them only on a pull past the top, shows a spinner
/// while it reads, keeps the reading place when they go in above, says when the start is reached, and offers to try again on a
/// failure.
@MainActor
final class EarlierMessagesTests: XCTestCase {
    /// The first message held before the earlier page is read: the conversation's 11th of 40.
    private static let firstHeldText = "Question 6 about the pick rate."

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func row(_ app: XCUIApplication) -> XCUIElement { DemoApp.element(app, "earlierMessagesRow") }

    private func message(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Scrolls to the top with flicks, which never hold a pull past the top.
    private func scrollToTop(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let top = row(app)
        XCTAssertTrue(top.waitForExistence(timeout: 60), "The conversation has no row at its top.\n\(app.debugDescription)", file: file, line: line)
        for _ in 0..<12 where !top.isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(top.isHittable, "The top of the conversation could not be reached.\n\(app.debugDescription)", file: file, line: line)
    }

    /// Holds the list at its top and pulls it down well past the set distance, then lets go.
    private func pull(_ app: XCUIApplication) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)))
    }

    func testTheRowSaysThereIsMoreAndReachingTheTopReadsNothing() {
        let app = DemoApp.launch(screen: "earlier-more")
        scrollToTop(app)
        XCTAssertTrue(row(app).label.contains("Pull down for earlier messages"), "The row does not say to pull.\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(row(app).value as? String, "more", "Reaching the top read the earlier messages without a pull.\n\(app.debugDescription)")
    }

    func testAPullReadsTheEarlierPageInAboveWithoutMovingTheReadingPlace() {
        let app = DemoApp.launch(screen: "earlier-more")
        scrollToTop(app)
        let firstHeld = message(app, Self.firstHeldText)
        XCTAssertTrue(firstHeld.isHittable, "The first message held is not in view at the top.\n\(app.debugDescription)")
        pull(app)
        XCTAssertTrue(DemoApp.waitUntilValue(row(app), contains: "start", timeout: 30), "A pull did not read the earlier page.\n\(app.debugDescription)")
        XCTAssertTrue(message(app, "Question 1 about the pick rate.").exists, "The earliest message is not there.\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 1)
        // The earlier messages went in above: what was being read is still in view, and the top of the conversation is not.
        XCTAssertTrue(firstHeld.isHittable, "The reading place moved as the earlier messages went in.\n\(app.debugDescription)")
        XCTAssertFalse(row(app).isHittable, "The list jumped to the top of the earlier messages.\n\(app.debugDescription)")
        scrollToTop(app)
        XCTAssertTrue(row(app).label.contains("Start of the conversation"), "The top does not say it is the start.\n\(app.debugDescription)")
    }

    func testTheRowShowsItIsLoadingWhileTheEarlierPageIsRead() {
        let app = DemoApp.launch(screen: "earlier-loading")
        scrollToTop(app)
        pull(app)
        XCTAssertTrue(DemoApp.waitUntilValue(row(app), contains: "loading", timeout: 20), "The row does not show it is loading.\n\(app.debugDescription)")
        XCTAssertTrue(row(app).label.contains("Loading earlier messages"), "The row does not say it is loading.\n\(app.debugDescription)")
    }

    func testAFailedReadSaysSoAndOffersToTryAgain() {
        let app = DemoApp.launch(screen: "earlier-failed")
        scrollToTop(app)
        pull(app)
        XCTAssertTrue(DemoApp.waitUntilValue(row(app), contains: "failed", timeout: 20), "The row does not say the read failed.\n\(app.debugDescription)")
        let retry = DemoApp.button(app, "earlierMessagesRetry")
        XCTAssertTrue(retry.waitForExistence(timeout: 10), "The row offers no way to try again.\n\(app.debugDescription)")
        retry.tap()
        XCTAssertTrue(DemoApp.waitUntilValue(row(app), contains: "failed", timeout: 20), "Trying again did not read again.\n\(app.debugDescription)")
    }
}
