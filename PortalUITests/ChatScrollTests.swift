import XCTest

/// Reading further up a long chat, the messages in view stay where they are: while an earlier page goes in above them, while
/// someone types and sends below them. Only a list at its end follows a new message.
@MainActor
final class ChatScrollTests: XCTestCase {
    /// How far a message may move between two readings and still count as still: less than a point is rounding.
    private static let allowedMovementHeight: CGFloat = 2

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// A message in view, by its words, and where its top is on screen.
    private struct Reading {
        let label: String
        let topY: CGFloat
    }

    private static func isMessageLabel(_ label: String) -> Bool {
        ["History message ", "Live message ", "Question ", "Answer "].contains { label.hasPrefix($0) }
    }

    /// The number a demo message starts with, as in "History message 42."
    private static func number(in label: String, after prefix: String) -> Int? {
        guard label.hasPrefix(prefix) else { return nil }
        return Int(label.dropFirst(prefix.count).prefix(while: \.isNumber))
    }

    /// Every message element on screen or off it, read in one pass.
    private func messageElements(_ app: XCUIApplication) -> [(label: String, frame: CGRect)] {
        guard let snapshot = try? app.snapshot() else { return [] }
        var found: [(label: String, frame: CGRect)] = []
        var pending = [snapshot]
        while let element = pending.popLast() {
            if Self.isMessageLabel(element.label), element.frame.height > 0 { found.append((element.label, element.frame)) }
            pending += element.children
        }
        return found
    }

    /// The highest message whose top is below the navigation bar: the first one the person sees.
    private func topMessage(_ app: XCUIApplication) -> Reading? {
        let barBottomY = app.navigationBars.firstMatch.frame.maxY
        return messageElements(app)
            .filter { $0.frame.minY >= barBottomY + 4 }
            .min { $0.frame.minY < $1.frame.minY }
            .map { Reading(label: $0.label, topY: $0.frame.minY) }
    }

    /// Where the message with these words is now.
    private func topY(of label: String, _ app: XCUIApplication) -> CGFloat? {
        messageElements(app).filter { $0.label == label }.map(\.frame.minY).min()
    }

    /// The earliest history message the list holds.
    private func earliestHistoryNumber(_ app: XCUIApplication) -> Int? {
        messageElements(app).compactMap { Self.number(in: $0.label, after: "History message ") }.min()
    }

    /// The latest live message the list holds.
    private func latestLiveNumber(_ app: XCUIApplication) -> Int {
        messageElements(app).compactMap { Self.number(in: $0.label, after: "Live message ") }.max() ?? 0
    }

    /// Drags the list down by about half a screen and holds at the end, so it stops where the finger does.
    private func scrollUp(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity(1_500), thenHoldForDuration: 0.3)
    }

    private func scrollDown(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity(3_000), thenHoldForDuration: 0.1)
    }

    private func openLongChat(screen: String) -> XCUIApplication {
        let app = DemoApp.launch(screen: screen)
        let newestHistory = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "History message 120")).firstMatch
        XCTAssertTrue(DemoApp.waitUntilExists(newestHistory, timeout: 90), "The long chat did not open.\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 1)
        return app
    }

    private func assertStill(
        _ before: Reading, _ app: XCUIApplication, while what: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let afterY = topY(of: before.label, app) else {
            XCTFail("\"\(before.label)\" left the list \(what).\n\(app.debugDescription)", file: file, line: line)
            return
        }
        XCTAssertLessThanOrEqual(
            abs(afterY - before.topY), Self.allowedMovementHeight,
            "\"\(before.label)\" moved from \(before.topY) to \(afterY) \(what).", file: file, line: line)
    }

    func testScrollingUpThroughEarlierPagesKeepsTheMessagesInViewStill() {
        let app = openLongChat(screen: "chat-history")
        var pagesSeen = 0
        for _ in 0..<60 where pagesSeen < 3 {
            guard let earliestBefore = earliestHistoryNumber(app) else { return XCTFail("No history is listed.\n\(app.debugDescription)") }
            scrollUp(app)
            Thread.sleep(forTimeInterval: 0.6)
            guard let before = topMessage(app) else { return XCTFail("No message is in view.\n\(app.debugDescription)") }
            // Long enough for a page the scroll asked for to arrive and go in.
            Thread.sleep(forTimeInterval: 2.5)
            let earliestAfter = earliestHistoryNumber(app) ?? earliestBefore
            assertStill(before, app, while: earliestAfter < earliestBefore ? "as an earlier page went in" : "with nothing touched")
            if earliestAfter < earliestBefore { pagesSeen += 1 }
        }
        XCTAssertEqual(pagesSeen, 3, "Scrolling up did not bring in three earlier pages.\n\(app.debugDescription)")
    }

    func testANewMessageWhileReadingFurtherUpLeavesTheMessagesInViewStill() {
        let app = openLongChat(screen: "chat-history-live")
        scrollUp(app)
        scrollUp(app)
        Thread.sleep(forTimeInterval: 0.6)
        guard let before = topMessage(app) else { return XCTFail("No message is in view.\n\(app.debugDescription)") }
        // What arrives waits below, behind a button, rather than growing the list under the messages being read.
        let waiting = DemoApp.element(app, "newMessagesButton")
        XCTAssertTrue(DemoApp.waitUntilExists(waiting, timeout: 30), "No new message arrived.\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 1)
        assertStill(before, app, while: "as a new message arrived below")
        waiting.tap()
        let latest = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Live message")).allElementsBoundByIndex.last
        XCTAssertNotNil(latest, "The waiting messages did not show after the button.\n\(app.debugDescription)")
    }

    func testANewMessageAtTheEndIsFollowed() {
        let app = openLongChat(screen: "chat-history-live")
        // Up and back down to the end, which the list then follows again.
        scrollUp(app)
        Thread.sleep(forTimeInterval: 0.6)
        for _ in 0..<4 { scrollDown(app) }
        Thread.sleep(forTimeInterval: 1)
        let next = latestLiveNumber(app) + 1
        let arriving = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Live message \(next)")).firstMatch
        XCTAssertTrue(DemoApp.waitUntilExists(arriving, timeout: 20), "No new message arrived.\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 1)
        let window = app.windows.firstMatch.frame
        let barBottomY = app.navigationBars.firstMatch.frame.maxY
        XCTAssertGreaterThanOrEqual(arriving.frame.minY, barBottomY, "The new message is above the screen.\n\(app.debugDescription)")
        XCTAssertLessThanOrEqual(arriving.frame.maxY, window.maxY, "The list at its end did not follow the new message.\n\(app.debugDescription)")
    }

    /// The assistant writes its answer below while the person reads further up: the messages in view stay where they are, and
    /// the answer waits behind the button.
    func testAnAnswerWrittenBelowLeavesTheMessagesInViewStill() {
        let app = DemoApp.launch(screen: "conversation-stream")
        let newestHistory = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Answer 25")).firstMatch
        XCTAssertTrue(DemoApp.waitUntilExists(newestHistory, timeout: 90), "The conversation did not open.\n\(app.debugDescription)")
        let writing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "streamed word 8 ")).firstMatch
        XCTAssertTrue(DemoApp.waitUntilExists(writing, timeout: 30), "No answer was being written.\n\(app.debugDescription)")
        scrollUp(app)
        scrollUp(app)
        Thread.sleep(forTimeInterval: 0.6)
        guard let before = topMessage(app) else { return XCTFail("No message is in view.\n\(app.debugDescription)") }
        Thread.sleep(forTimeInterval: 4)
        assertStill(before, app, while: "as the answer was written below")
        XCTAssertTrue(DemoApp.element(app, "newMessagesButton").exists, "Nothing says the answer goes on below.\n\(app.debugDescription)")
    }
}
