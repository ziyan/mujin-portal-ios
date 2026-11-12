import XCTest

/// Staff in a chat a customer reads see the Staff only switch in the composer: a lock in the pill, a chip beside [+] in the card.
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
        let chip = DemoApp.button(app, "staffOnlyChip")
        XCTAssertTrue(DemoApp.waitUntilExists(chip, timeout: 10), "The card has no Staff only chip.\n\(app.debugDescription)")
        chip.tap()
        XCTAssertTrue(DemoApp.waitUntilValue(chip, contains: "Off", timeout: 10), "The chip did not turn the switch off.\n\(app.debugDescription)")
    }

    func testCustomersDoNotSeeTheSwitch() {
        let app = DemoApp.launch(screen: "chat-internal")
        XCTAssertTrue(DemoApp.waitUntilExists(DemoApp.element(app, "chatMessageField"), timeout: 90), "The chat did not open.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.button(app, "staffOnlyLock").exists, "A customer sees the Staff only switch.\n\(app.debugDescription)")
    }
}
