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
