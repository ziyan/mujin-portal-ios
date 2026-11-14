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

    /// Pulls three earlier pages in at the top, one pull at a time from the row that says there is more: each time, the message
    /// that was first stays in view and the list does not jump to the top of the page that went in.
    func testPullingInEarlierPagesKeepsTheReadingPlace() {
        let app = openLongChat(screen: "chat-history")
        let row = DemoApp.element(app, "earlierMessagesRow")
        for page in 1...3 {
            // A flick that carries past the top while a finger is still down is a pull, and reads a page of its own: let that page go
            // in, and go back to the top, before the pull that is measured. Reaching the top without a pull is tested in the earlier
            // messages' own tests.
            for _ in 0..<15 where !row.isHittable { app.swipeDown(velocity: .fast) }
            Thread.sleep(forTimeInterval: 3)
            for _ in 0..<15 where !row.isHittable { app.swipeDown(velocity: .fast) }
            XCTAssertTrue(row.isHittable, "Page \(page): the top of the chat could not be reached.\n\(app.debugDescription)")
            Thread.sleep(forTimeInterval: 1)
            guard let earliestBefore = earliestHistoryNumber(app) else { return XCTFail("No history is listed.\n\(app.debugDescription)") }
            let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)))
            let firstHeld = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "(?s)History message \(earliestBefore)\\D.*")).firstMatch
            // Long enough for the page, which the demo holds back a moment, to arrive and go in.
            for _ in 0..<20 where (earliestHistoryNumber(app) ?? earliestBefore) >= earliestBefore { Thread.sleep(forTimeInterval: 0.5) }
            XCTAssertLessThan(earliestHistoryNumber(app) ?? earliestBefore, earliestBefore, "Page \(page): a pull did not read a page.\n\(app.debugDescription)")
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(firstHeld.isHittable, "Page \(page): the message being read left the screen.\n\(app.debugDescription)")
            XCTAssertFalse(row.isHittable, "Page \(page): the list jumped to the top of the page that went in.\n\(app.debugDescription)")
        }
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
