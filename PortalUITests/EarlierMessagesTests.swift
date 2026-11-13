import XCTest

/// The row at the top of a conversation says there are earlier messages, reads them only on a pull past the top, shows a spinner
/// while it reads, keeps the reading place when they go in above, says when the start is reached, and offers to try again on a
/// failure.
@MainActor
final class EarlierMessagesTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func row(_ app: XCUIApplication) -> XCUIElement { DemoApp.element(app, "earlierMessagesRow") }

    private func message(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The number of the earliest question the list holds, as in "Question 36 about the pick rate."
    private func earliestQuestion(_ app: XCUIApplication) -> Int? {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Question ")).allElementsBoundByIndex
            .compactMap { Int($0.label.dropFirst("Question ".count).prefix(while: \.isNumber)) }.min()
    }

    /// Scrolls to the top with flicks, which never hold a pull past the top.
    private func scrollToTop(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let top = row(app)
        XCTAssertTrue(top.waitForExistence(timeout: 60), "The conversation has no row at its top.\n\(app.debugDescription)", file: file, line: line)
        for _ in 0..<12 where !top.isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(top.isHittable, "The top of the conversation could not be reached.\n\(app.debugDescription)", file: file, line: line)
    }

    /// Holds the list at its top by the row, not by a message, whose long press has actions, and pulls it down well past the set
    /// distance, then lets go.
    private func pull(_ app: XCUIApplication) {
        let start = row(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)))
    }

    func testTheRowSaysThereIsMoreAndReachingTheTopReadsNothing() {
        let app = DemoApp.launch(screen: "earlier-more")
        scrollToTop(app)
        // Once the list has settled at the top: during a bounce the row can still say to let go.
        XCTAssertTrue(DemoApp.waitUntilLabel(row(app), contains: "Pull down for earlier messages", timeout: 10), "The row does not say to pull.\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(row(app).value as? String, "more", "Reaching the top read the earlier messages without a pull.\n\(app.debugDescription)")
    }

    func testAPullReadsTheEarlierPageInAboveWithoutMovingTheReadingPlace() {
        let app = DemoApp.launch(screen: "earlier-more")
        scrollToTop(app)
        Thread.sleep(forTimeInterval: 1)
        guard let earliestBefore = earliestQuestion(app) else { return XCTFail("No question is listed.\n\(app.debugDescription)") }
        let firstHeld = message(app, "Question \(earliestBefore) about the pick rate.")
        XCTAssertTrue(firstHeld.isHittable, "The first message held is not in view at the top.\n\(app.debugDescription)")
        pull(app)
        let earlier = message(app, "Question \(earliestBefore - 1) about the pick rate.")
        XCTAssertTrue(earlier.waitForExistence(timeout: 30), "A pull did not read the earlier page.\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 1)
        // The earlier messages went in above: what was being read is still in view, and the top of the conversation is not.
        XCTAssertTrue(firstHeld.isHittable, "The reading place moved as the earlier messages went in.\n\(app.debugDescription)")
        XCTAssertFalse(row(app).isHittable, "The list jumped to the top of the earlier messages.\n\(app.debugDescription)")
    }

    func testTheTopOfAShortConversationSaysItIsTheStart() {
        let app = DemoApp.launch(screen: "conversation:conversation02")
        scrollToTop(app)
        XCTAssertTrue(
            DemoApp.waitUntilLabel(row(app), contains: "Start of the conversation", timeout: 10), "The top does not say it is the start.\n\(app.debugDescription)")
        XCTAssertEqual(row(app).value as? String, "start")
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
