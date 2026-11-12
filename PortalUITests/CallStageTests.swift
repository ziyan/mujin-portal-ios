import XCTest

/// The call stage a conversation shows during a call: its mute and leave buttons are real taps, in an assistant call and in a call
/// with people. They once sat where the navigation bar took every touch, so they drew but did nothing.
@MainActor
final class CallStageTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testMuteAndLeaveWorkInAnAssistantCall() {
        checkMuteAndLeave(screen: "voice")
    }

    func testMuteAndLeaveWorkInACallWithPeople() {
        checkMuteAndLeave(screen: "chat-in-call")
    }

    /// Leaving the conversation does not end a call with the assistant: it goes on in a bar, which brings the conversation back.
    func testAnAssistantCallGoesOnInABarWhenItsConversationIsLeft() {
        let app = DemoApp.launch(screen: "voice")
        let leave = DemoApp.button(app, "callStageLeave")
        XCTAssertTrue(DemoApp.waitUntilExists(leave, timeout: 90), "The call did not start.\n\(app.debugDescription)")
        DemoApp.goBack(app)
        let bar = DemoApp.element(app, "assistantCallBar")
        XCTAssertTrue(DemoApp.waitUntilExists(bar, timeout: 20), "Leaving the conversation ended the call.\n\(app.debugDescription)")
        bar.tap()
        XCTAssertTrue(DemoApp.waitUntilExists(leave, timeout: 20), "The bar did not bring the call back.\n\(app.debugDescription)")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: bar)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "The bar stayed over its own conversation.\n\(app.debugDescription)")
    }

    /// Another conversation shows the call going elsewhere in a strip under its own header, and the strip leads back to the call.
    func testAnotherConversationShowsTheCallInAStripUnderItsHeader() {
        let app = DemoApp.launch(screen: "voice")
        let leave = DemoApp.button(app, "callStageLeave")
        XCTAssertTrue(DemoApp.waitUntilExists(leave, timeout: 90), "The call did not start.\n\(app.debugDescription)")
        DemoApp.goBack(app)
        let other = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Questions about site01")).firstMatch
        DemoApp.scrollToElement(other, in: app)
        other.tap()
        let strip = DemoApp.element(app, "ongoingCallStrip")
        XCTAssertTrue(DemoApp.waitUntilExists(strip, timeout: 20), "The other conversation does not show the call.\n\(app.debugDescription)")
        XCTAssertGreaterThanOrEqual(
            strip.frame.minY, app.navigationBars.firstMatch.frame.maxY - 1, "The strip is not under the header.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.element(app, "assistantCallBar").exists, "The app's bar shows over the strip too.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.element(app, "ongoingCallStripHangUp").exists, "The strip has no way to hang up.\n\(app.debugDescription)")
        strip.tap()
        XCTAssertTrue(DemoApp.waitUntilExists(leave, timeout: 20), "The strip did not lead back to the call.\n\(app.debugDescription)")
    }

    private func checkMuteAndLeave(screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = DemoApp.launch(screen: screen)
        let mute = DemoApp.button(app, "callStageMute")
        XCTAssertTrue(DemoApp.waitUntilExists(mute, timeout: 90), "The call has no mute button.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertEqual(mute.label, "Mute", file: file, line: line)
        XCTAssertTrue(DemoApp.waitUntilHittable(mute, timeout: 15), "Mute cannot be tapped.\n\(app.debugDescription)", file: file, line: line)
        mute.tap()
        XCTAssertTrue(DemoApp.waitUntilLabel(mute, contains: "Unmute", timeout: 10), "Tapping mute did not mute: \"\(mute.label)\".\n\(app.debugDescription)", file: file, line: line)
        mute.tap()
        XCTAssertTrue(DemoApp.waitUntilLabel(mute, contains: "Mute", timeout: 10), "Tapping again did not unmute: \"\(mute.label)\".", file: file, line: line)

        let leave = DemoApp.button(app, "callStageLeave")
        XCTAssertTrue(DemoApp.waitUntilHittable(leave, timeout: 15), "Leave cannot be tapped.\n\(app.debugDescription)", file: file, line: line)
        leave.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: leave)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 15), .completed, "Leaving did not end the call.\n\(app.debugDescription)", file: file, line: line)
    }
}
