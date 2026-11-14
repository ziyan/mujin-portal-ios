import XCTest

/// Staff in a chat a customer reads see the Staff only switch in the composer: one round lock beside [+], in the pill, the card and the
/// voice message bar.
@MainActor
final class StaffOnlyTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testStaffSeeTheSwitchAndItMakesTheNextMessageInternal() {
        let app = DemoApp.launch(screen: "chat-internal", persona: "staff")
        let lock = DemoApp.button(app, "staffOnlyLock")
        XCTAssertTrue(DemoApp.waitUntilExists(lock, timeout: 90), "The pill has no Staff only lock.\n\(app.debugDescription)")
        XCTAssertEqual(lock.value as? String, "Off", "The switch starts on.\n\(app.debugDescription)")
        lock.tap()
        XCTAssertTrue(DemoApp.waitUntilValue(lock, contains: "On", timeout: 10), "The lock did not turn the switch on.\n\(app.debugDescription)")
        let field = DemoApp.element(app, "chatMessageField")
        XCTAssertTrue(DemoApp.waitUntilLabel(field, contains: "Internal note", timeout: 10), "The field does not say the note is internal.\n\(app.debugDescription)")
        field.tap()
        XCTAssertTrue(DemoApp.waitUntilExists(lock, timeout: 10), "The card has no Staff only lock.\n\(app.debugDescription)")
        lock.tap()
        XCTAssertTrue(DemoApp.waitUntilValue(lock, contains: "Off", timeout: 10), "The lock in the card did not turn the switch off.\n\(app.debugDescription)")
    }

    func testStaffSeeTheSwitchBesideTheVoiceMessageBar() {
        let app = DemoApp.launch(screen: "chat-voice-composer", persona: "staff")
        XCTAssertTrue(DemoApp.waitUntilExists(DemoApp.element(app, "voiceHoldButton"), timeout: 90), "The voice message bar did not show.\n\(app.debugDescription)")
        let lock = DemoApp.button(app, "staffOnlyLock")
        XCTAssertTrue(DemoApp.waitUntilExists(lock, timeout: 10), "The voice message bar has no Staff only lock.\n\(app.debugDescription)")
        lock.tap()
        XCTAssertTrue(DemoApp.waitUntilValue(lock, contains: "On", timeout: 10), "The lock did not turn the switch on.\n\(app.debugDescription)")
    }

    func testCustomersDoNotSeeTheSwitch() {
        let app = DemoApp.launch(screen: "chat-internal")
        XCTAssertTrue(DemoApp.waitUntilExists(DemoApp.element(app, "chatMessageField"), timeout: 90), "The chat did not open.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.button(app, "staffOnlyLock").exists, "A customer sees the Staff only switch.\n\(app.debugDescription)")
    }
}
