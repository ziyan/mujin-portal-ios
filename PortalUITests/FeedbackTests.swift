import XCTest

/// Feedback about Portal itself: a screenshot opens a sheet with a picture of the screen, Settings has the same form without one, and
/// My feedback shows how far each piece has come. None of it shows on a server that does not offer it. The demo has no side buttons to
/// press, so it posts the system's screenshot notification itself a few seconds after the tab opens, and the app answers it as it
/// would on a phone.
@MainActor
final class FeedbackTests: XCTestCase {
    private static let words = "The sheet should remember my words"
    /// Turns the sheet on whatever an earlier test left in the phone's settings.
    private static let askArguments = ["-shouldAskForFeedbackAfterScreenshot", "YES"]

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launchSheet(_ screen: String) -> XCUIApplication {
        DemoApp.launch(screen: screen, arguments: Self.askArguments)
    }

    private func sendButton(_ app: XCUIApplication) -> XCUIElement { DemoApp.button(app, "feedbackSendButton") }

    private func removeScreenshotButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove Screenshot")).firstMatch
    }

    private func text(_ app: XCUIApplication, containing fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 30) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func typeWords(_ app: XCUIApplication, _ words: String = FeedbackTests.words) {
        let field = DemoApp.element(app, "feedbackWordsField")
        XCTAssertTrue(field.waitForExistence(timeout: 30), "There is no box for the words.\n\(app.debugDescription)")
        field.tap()
        field.typeText(words)
    }

    // MARK: - After a screenshot

    func testAScreenshotOpensTheSheetWithThePictureAndSaysWhereItGoes() {
        let app = launchSheet("feedback-drawer")
        let notice = DemoApp.element(app, "feedbackNotice")
        XCTAssertTrue(notice.waitForExistence(timeout: 90), "A screenshot did not open the feedback sheet.\n\(app.debugDescription)")
        XCTAssertTrue(notice.label.contains("This goes to the Portal team"), "The notice does not say who gets it: \"\(notice.label)\".")
        XCTAssertTrue(notice.label.contains("open a ticket for that site instead"), "The notice does not point to a site ticket: \"\(notice.label)\".")
        XCTAssertTrue(DemoApp.button(app, "feedbackSiteTicketButton").exists, "There is no way to open a ticket for a site.\n\(app.debugDescription)")
        XCTAssertTrue(removeScreenshotButton(app).waitForExistence(timeout: 30), "The picture of the screen is not attached.\n\(app.debugDescription)")
        XCTAssertTrue(text(app, containing: "The screenshot is sent with your words").exists, "The sheet does not say the screenshot is sent.\n\(app.debugDescription)")
        XCTAssertTrue(text(app, containing: "people in your organization who can read all tickets").exists, "The sheet does not say who can read it.\n\(app.debugDescription)")
        XCTAssertFalse(sendButton(app).isEnabled, "Send is on before there are words.")
    }

    func testTheSiteTicketRowOpensTheTicketForm() {
        let app = launchSheet("feedback-drawer")
        let row = DemoApp.button(app, "feedbackSiteTicketButton")
        XCTAssertTrue(row.waitForExistence(timeout: 90), "The feedback sheet did not open.\n\(app.debugDescription)")
        row.tap()
        XCTAssertTrue(DemoApp.element(app, "ticketTitleField").waitForExistence(timeout: 30), "The ticket form did not open.\n\(app.debugDescription)")
    }

    func testSendNeedsWordsThenSendsThemAndOffersMyFeedback() {
        let app = launchSheet("feedback-drawer")
        XCTAssertTrue(DemoApp.element(app, "feedbackNotice").waitForExistence(timeout: 90), "The feedback sheet did not open.\n\(app.debugDescription)")
        XCTAssertFalse(sendButton(app).isEnabled, "Send is on before there are words.")
        typeWords(app)
        XCTAssertTrue(waitForEnabled(sendButton(app)), "Send stayed off after the words were typed.\n\(app.debugDescription)")
        sendButton(app).tap()
        let sent = text(app, containing: "Your feedback was sent as ticket #")
        XCTAssertTrue(sent.waitForExistence(timeout: 60), "The sheet does not say the feedback was sent.\n\(app.debugDescription)")
        let myFeedback = DemoApp.button(app, "feedbackMyFeedbackButton")
        XCTAssertTrue(myFeedback.exists, "The sheet does not offer My feedback.\n\(app.debugDescription)")
        myFeedback.tap()
        XCTAssertTrue(app.navigationBars["My feedback"].waitForExistence(timeout: 30), "My feedback did not open.\n\(app.debugDescription)")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND NOT label CONTAINS %@", Self.words, "Portal feedback:")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The feedback just sent is not listed.\n\(app.debugDescription)")
    }

    func testCancelClosesTheSheet() {
        let app = launchSheet("feedback-drawer")
        XCTAssertTrue(DemoApp.element(app, "feedbackNotice").waitForExistence(timeout: 90), "The feedback sheet did not open.\n\(app.debugDescription)")
        typeWords(app)
        DemoApp.button(app, "feedbackCancelButton").tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: DemoApp.element(app, "feedbackNotice"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 30), .completed, "Cancel did not close the sheet.\n\(app.debugDescription)")
    }

    func testThePictureCanBeRemoved() {
        let app = launchSheet("feedback-drawer")
        let remove = removeScreenshotButton(app)
        XCTAssertTrue(remove.waitForExistence(timeout: 90), "The picture of the screen is not attached.\n\(app.debugDescription)")
        remove.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: remove)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 30), .completed, "The picture is still attached.\n\(app.debugDescription)")
        XCTAssertTrue(text(app, containing: "Your words are sent as a ticket").exists, "The sheet still talks about a screenshot.\n\(app.debugDescription)")
    }

    func testAFailureKeepsTheWordsAndThePictureAndSaysWhy() {
        let app = launchSheet("feedback-drawer-error")
        XCTAssertTrue(DemoApp.element(app, "feedbackNotice").waitForExistence(timeout: 90), "The feedback sheet did not open.\n\(app.debugDescription)")
        typeWords(app)
        XCTAssertTrue(waitForEnabled(sendButton(app)), "Send stayed off after the words were typed.\n\(app.debugDescription)")
        sendButton(app).tap()
        let error = DemoApp.element(app, "feedbackError")
        XCTAssertTrue(error.waitForExistence(timeout: 60), "The failure was not shown.\n\(app.debugDescription)")
        XCTAssertTrue(error.label.contains("could not be saved"), "The failure does not say what happened: \"\(error.label)\".")
        let field = DemoApp.element(app, "feedbackWordsField")
        XCTAssertTrue(((field.value as? String) ?? "").contains(Self.words), "The words were lost: \"\(field.value as? String ?? "")\".")
        XCTAssertTrue(removeScreenshotButton(app).exists, "The picture was lost.\n\(app.debugDescription)")
        XCTAssertTrue(waitForEnabled(sendButton(app)), "Send cannot be pressed again.\n\(app.debugDescription)")
        sendButton(app).tap()
        XCTAssertTrue(text(app, containing: "Your feedback was sent as ticket #").waitForExistence(timeout: 60), "The second try did not send.\n\(app.debugDescription)")
    }

    func testNothingOpensWhenAskingIsTurnedOff() {
        let app = DemoApp.launch(screen: "feedback-drawer-off", arguments: ["-shouldAskForFeedbackAfterScreenshot", "NO"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 90), "The app did not open.\n\(app.debugDescription)")
        // The demo posts the screenshot after 2 seconds.
        Thread.sleep(forTimeInterval: 9)
        XCTAssertFalse(DemoApp.element(app, "feedbackNotice").exists, "The sheet opened though asking is turned off.\n\(app.debugDescription)")
    }

    func testNothingOpensDuringACall() {
        let app = launchSheet("feedback-in-call")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 90), "The app did not open.\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 9)
        XCTAssertFalse(DemoApp.element(app, "feedbackNotice").exists, "The sheet opened during a call.\n\(app.debugDescription)")
    }

    // MARK: - Settings

    func testSettingsHasAFormThatNeedsNoScreenshot() {
        let app = DemoApp.launch(screen: "feedback-form")
        let row = DemoApp.button(app, "sendFeedbackRow")
        DemoApp.scrollToElement(row, in: app)
        row.tap()
        XCTAssertTrue(DemoApp.element(app, "feedbackNotice").waitForExistence(timeout: 30), "The form did not open.\n\(app.debugDescription)")
        XCTAssertFalse(removeScreenshotButton(app).exists, "The form has a screenshot nobody took.\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["Attach"].exists, "The form cannot take a picture.\n\(app.debugDescription)")
        XCTAssertFalse(sendButton(app).isEnabled, "Send is on before there are words.")
        typeWords(app)
        XCTAssertTrue(waitForEnabled(sendButton(app)), "Send stayed off after the words were typed.\n\(app.debugDescription)")
        sendButton(app).tap()
        XCTAssertTrue(text(app, containing: "Your feedback was sent as ticket #").waitForExistence(timeout: 60), "The form did not send.\n\(app.debugDescription)")
    }

    func testTheAskingToggleIsOnUntilTurnedOff() {
        let app = DemoApp.launch(screen: "feedback-form")
        let toggle = app.switches["feedbackAfterScreenshotToggle"]
        DemoApp.scrollToElement(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1", "Asking after a screenshot is not on by default.")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let isOff = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [isOff], timeout: 15), .completed, "The toggle did not turn off.\n\(app.debugDescription)")
        // Leave the phone as it was found.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let isOn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [isOn], timeout: 15), .completed, "The toggle did not turn back on.\n\(app.debugDescription)")
    }

    func testAnOlderServerShowsNoFeedbackAnywhereInSettings() {
        let app = DemoApp.launch(screen: "settings")
        let tabBarRow = DemoApp.element(app, "editTabBarRow")
        DemoApp.scrollToElement(tabBarRow, in: app)
        XCTAssertFalse(DemoApp.button(app, "sendFeedbackRow").exists, "Send feedback shows on a server that does not offer it.\n\(app.debugDescription)")
        XCTAssertFalse(app.switches["feedbackAfterScreenshotToggle"].exists, "The toggle shows on a server that does not offer feedback.\n\(app.debugDescription)")
    }

    // MARK: - My feedback

    func testMyFeedbackListsTheWordsTheStatusAndOpensTheTicket() {
        let app = DemoApp.launch(screen: "feedback-list")
        let words = "The filter menu on Tickets is hard to find"
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 90), "The feedback is not listed.\n\(app.debugDescription)")
        XCTAssertTrue(row.label.contains("Open"), "The row does not say where the ticket stands: \"\(row.label)\".")
        XCTAssertFalse(row.label.contains("Portal feedback:"), "The row shows the prefix of the title: \"\(row.label)\".")
        let solved = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Camera tiles are too dim in dark mode")).firstMatch
        XCTAssertTrue(solved.exists, "The solved feedback is not listed.\n\(app.debugDescription)")
        XCTAssertTrue(solved.label.contains("Solved"), "The row does not say it is solved: \"\(solved.label)\".")
        XCTAssertFalse(text(app, containing: "Another person's idea").exists, "Someone else's feedback is listed.")
        row.tap()
        XCTAssertTrue(DemoApp.element(app, "portalFeedbackLabel").waitForExistence(timeout: 30), "The ticket does not say it is Portal feedback.\n\(app.debugDescription)")
    }

    func testMyFeedbackSaysWhenThereIsNone() {
        let app = DemoApp.launch(screen: "feedback-list-empty")
        XCTAssertTrue(text(app, containing: "No feedback yet").waitForExistence(timeout: 90), "The empty list does not say so.\n\(app.debugDescription)")
    }

    func testMyFeedbackSaysWhyItCouldNotLoad() {
        let app = DemoApp.launch(screen: "feedback-list-error")
        XCTAssertTrue(text(app, containing: "Could not load your feedback").waitForExistence(timeout: 90), "The failure is not shown.\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["Try again"].exists, "There is no way to try again.\n\(app.debugDescription)")
    }

    // MARK: - The label

    func testTheTicketsListMarksFeedbackAboutPortal() {
        let app = DemoApp.launch(screen: "feedback-tickets")
        let label = DemoApp.element(app, "portalFeedbackLabel")
        XCTAssertTrue(label.waitForExistence(timeout: 90), "No ticket in the list is marked as Portal feedback.\n\(app.debugDescription)")
        XCTAssertEqual(label.label, "Portal feedback")
    }

    func testTheTicketMarksItselfAsFeedbackAboutPortal() {
        let app = DemoApp.launch(screen: "feedback-ticket")
        let label = DemoApp.element(app, "portalFeedbackLabel")
        XCTAssertTrue(label.waitForExistence(timeout: 90), "The ticket does not say it is Portal feedback.\n\(app.debugDescription)")
        XCTAssertTrue(text(app, containing: "The filter menu on Tickets is hard to find").exists, "The ticket does not show the words.\n\(app.debugDescription)")
    }

    func testAnOrdinaryTicketIsNotMarked() {
        let app = DemoApp.launch(screen: "ticket")
        XCTAssertTrue(text(app, containing: "Gripper drops boxes at pick station 3").waitForExistence(timeout: 90), "The ticket did not open.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.element(app, "portalFeedbackLabel").exists, "An ordinary ticket is marked as Portal feedback.")
    }
}
