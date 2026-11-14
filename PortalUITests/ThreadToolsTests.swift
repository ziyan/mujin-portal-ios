import XCTest

/// Questions, approvals and todos belong to the view they were made in. An approval waiting only in a thread opens the conversation
/// on that thread, which shows it with the thread's own todo list; the main history points to it in one line.
@MainActor
final class ThreadToolsTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testAnApprovalWaitingInAThreadOpensTheThreadAndTheMainHistoryPointsToIt() {
        let app = DemoApp.launch(screen: "thread-conversation-waiting")
        // The card names the tool; the reason the server gives for asking is not drawn.
        let approval = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "The assistant wants to use shell")).firstMatch
        XCTAssertTrue(DemoApp.waitUntilExists(approval, timeout: 90), "The conversation did not open on the thread's approval.\n\(app.debugDescription)")
        XCTAssertTrue(app.navigationBars.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Thread")).firstMatch.exists,
            "The approval did not show in the thread.\n\(app.debugDescription)")
        let threadTodo = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Restart the door 4 controller")).firstMatch
        XCTAssertTrue(DemoApp.waitUntilExists(threadTodo, timeout: 20), "The thread does not show its own todo list.\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Send the weekly door report")).firstMatch.exists,
            "The thread shows the main history's todo.\n\(app.debugDescription)")

        DemoApp.goBack(app)
        let pointer = DemoApp.element(app, "waitingInThreadLine")
        XCTAssertTrue(DemoApp.waitUntilExists(pointer, timeout: 20), "The main history does not point to the thread.\n\(app.debugDescription)")
        XCTAssertFalse(approval.exists, "The thread's approval also shows in the main history.\n\(app.debugDescription)")
        let mainTodo = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Send the weekly door report")).firstMatch
        XCTAssertTrue(DemoApp.waitUntilExists(mainTodo, timeout: 20), "The main history does not show its todo list.\n\(app.debugDescription)")
        DemoApp.button(app, "openWaitingThreadButton").tap()
        XCTAssertTrue(DemoApp.waitUntilExists(approval, timeout: 20), "Open thread did not open the thread.\n\(app.debugDescription)")
    }
}
