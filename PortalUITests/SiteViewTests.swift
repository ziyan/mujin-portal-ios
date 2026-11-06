import XCTest

/// A controller can be left out of its site's and cells' views, a site can name one controller whose figures stand for the whole site,
/// and active alarms are listed by level. The demo has a site whose simulation controller is excluded and whose warehouse controller
/// is the source of the site's figures. Every picked-parts figure below is the sum of the controllers that count.
@MainActor
final class SiteViewTests: XCTestCase {
    /// The levels on when nothing was chosen, whatever an earlier test left on the phone.
    private static let defaultLevels = ["-activeAlarmLevels", "critical,error"]

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func link(_ app: XCUIApplication, _ controllerId: String) -> XCUIElement {
        DemoApp.element(app, "controllerLink.\(controllerId)")
    }

    private func text(_ app: XCUIApplication, _ exact: String) -> XCUIElement { app.staticTexts[exact] }

    private func tile(_ app: XCUIApplication, _ identifier: String) -> XCUIElement { DemoApp.element(app, identifier) }

    /// The picked-parts tile of the page: its combined label holds the figure.
    private func pickedPartsTile(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Picked parts")).firstMatch
    }

    private func waitForLabel(_ element: XCUIElement, containing fragment: String, timeout: TimeInterval = 30) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", fragment), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// A lazy list does not make a row until it is near the screen, so the page is swiped up until the row exists.
    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<15 where !element.exists { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) never appeared.\n\(app.debugDescription)")
    }

    /// Scrolls until the row exists, then until it can be tapped.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        scrollUntilExists(element, in: app)
        DemoApp.scrollToElement(element, in: app)
    }

    private func toggleRightEdge(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    private func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 20) == .completed
    }

    // MARK: - A site

    func testASiteNamesWhereItsTotalsComeFromAndWhatItLeavesOut() {
        let app = DemoApp.launch(screen: "exclusion-site", arguments: Self.defaultLevels)
        XCTAssertTrue(text(app, "Site totals and alarms come from:").waitForExistence(timeout: 90), "The site does not say where its totals come from.\n\(app.debugDescription)")
        XCTAssertTrue(link(app, "controller05").exists, "The source is not named as a link.\n\(app.debugDescription)")
        XCTAssertTrue(text(app, "Excluded from this view:").exists, "The site does not say what it leaves out.\n\(app.debugDescription)")
        XCTAssertTrue(link(app, "controller04").exists, "The excluded controller is not named as a link.\n\(app.debugDescription)")
    }

    func testASiteWithASourceReadsItsFiguresFromTheSourceAlone() {
        let app = DemoApp.launch(screen: "exclusion-site", arguments: Self.defaultLevels)
        let tile = pickedPartsTile(app)
        XCTAssertTrue(tile.waitForExistence(timeout: 90), "There is no picked-parts tile.\n\(app.debugDescription)")
        XCTAssertTrue(waitForLabel(tile, containing: "2,000"), "The tile does not hold the source's figure: \"\(tile.label)\".")
    }

    func testWithoutASourceTheExcludedControllerStaysOutOfTheTotals() {
        let app = DemoApp.launch(screen: "exclusion-site-nosource", arguments: Self.defaultLevels)
        let tile = pickedPartsTile(app)
        XCTAssertTrue(tile.waitForExistence(timeout: 90), "There is no picked-parts tile.\n\(app.debugDescription)")
        // 1,000 + 200 + 300 + 2,000 of the four that count; the simulation controller's 5,000 are not in it.
        XCTAssertTrue(waitForLabel(tile, containing: "3,500"), "The tile is not the sum of the controllers that count: \"\(tile.label)\".")
        XCTAssertFalse(text(app, "Site totals and alarms come from:").exists, "A site with no source says it has one.")
        XCTAssertTrue(text(app, "Excluded from this view:").exists, "The site does not say what it leaves out.")
    }

    func testTheNoteOpensTheExcludedController() {
        let app = DemoApp.launch(screen: "exclusion-site", arguments: Self.defaultLevels)
        let excluded = link(app, "controller04")
        XCTAssertTrue(excluded.waitForExistence(timeout: 90), "The excluded controller is not named.\n\(app.debugDescription)")
        excluded.tap()
        XCTAssertTrue(DemoApp.element(app, "excludedBadge").waitForExistence(timeout: 30), "The controller page does not say it is excluded.\n\(app.debugDescription)")
    }

    func testTheControllersListKeepsTheExcludedControllerWithABadgeAndMarksTheSource() {
        let app = DemoApp.launch(screen: "exclusion-controllers", arguments: Self.defaultLevels)
        XCTAssertTrue(text(app, "controller04").waitForExistence(timeout: 90), "The excluded controller is not in the list.\n\(app.debugDescription)")
        XCTAssertTrue(text(app, "Excluded from site views").exists, "The excluded controller has no badge.\n\(app.debugDescription)")
        XCTAssertTrue(text(app, "Site total").exists, "The source is not marked.\n\(app.debugDescription)")
    }

    // MARK: - A cell

    func testACellNamesOnlyWhatItLeavesOut() {
        let app = DemoApp.launch(screen: "exclusion-cell", arguments: Self.defaultLevels)
        XCTAssertTrue(text(app, "Excluded from this view:").waitForExistence(timeout: 90), "The cell does not say what it leaves out.\n\(app.debugDescription)")
        XCTAssertTrue(link(app, "controller04").exists, "The excluded controller is not named.\n\(app.debugDescription)")
        XCTAssertFalse(text(app, "Site totals and alarms come from:").exists, "A cell says where the site's totals come from.")
        let tile = pickedPartsTile(app)
        // 1,000 + 300 of the two that count in this cell.
        XCTAssertTrue(waitForLabel(tile, containing: "1,300"), "The cell's figure is not the sum of its controllers that count: \"\(tile.label)\".")
    }

    func testACellThatLeavesNothingOutSaysNothingAndLeavesTheSourceOutBesideOthers() {
        let app = DemoApp.launch(screen: "exclusion-cell-source", arguments: Self.defaultLevels)
        let tile = pickedPartsTile(app)
        XCTAssertTrue(tile.waitForExistence(timeout: 90), "There is no picked-parts tile.\n\(app.debugDescription)")
        // The source holds the whole site's figures, so beside another controller it is left out: only the other one's 200.
        XCTAssertTrue(waitForLabel(tile, containing: "200"), "The cell counted the source: \"\(tile.label)\".")
        XCTAssertFalse(tile.label.contains("2,200"), "The cell counted the source: \"\(tile.label)\".")
        XCTAssertFalse(text(app, "Excluded from this view:").exists, "The cell names a controller that is not in it.")
    }

    // MARK: - A controller

    func testAnExcludedControllerCanBePutBack() {
        let app = DemoApp.launch(screen: "exclusion-controller", arguments: Self.defaultLevels)
        let badge = DemoApp.element(app, "excludedBadge")
        XCTAssertTrue(badge.waitForExistence(timeout: 90), "The controller page does not say it is excluded.\n\(app.debugDescription)")
        let toggle = app.switches["excludeFromSiteViewsToggle"]
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1", "The toggle does not show the controller is excluded.")
        let help = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Its alarms, orchestrators, mobile robots and telemetry stop counting")).firstMatch
        XCTAssertTrue(help.exists, "The help text is missing.\n\(app.debugDescription)")
        XCTAssertTrue(help.label.hasSuffix("Its own pages keep working."), "The help text is cut: \"\(help.label)\".")
        toggleRightEdge(toggle)
        XCTAssertTrue(waitForValue(toggle, "0"), "The toggle did not turn off.\n\(app.debugDescription)")
    }

    func testAControllerCanBeLeftOut() {
        let app = DemoApp.launch(screen: "exclusion-controller-included", arguments: Self.defaultLevels)
        XCTAssertTrue(app.navigationBars["controller01"].waitForExistence(timeout: 90), "The controller page did not open.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.element(app, "excludedBadge").exists, "A controller that counts says it is excluded.")
        let toggle = app.switches["excludeFromSiteViewsToggle"]
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "0", "The toggle does not show the controller counts.")
        toggleRightEdge(toggle)
        XCTAssertTrue(waitForValue(toggle, "1"), "The toggle did not turn on.\n\(app.debugDescription)")
        // The page says so at its top too.
        app.swipeDown()
        for _ in 0..<10 where !DemoApp.element(app, "excludedBadge").exists { app.swipeDown() }
        XCTAssertTrue(DemoApp.element(app, "excludedBadge").exists, "The controller page does not say it is now excluded.\n\(app.debugDescription)")
    }

    func testAPersonWhoCannotEditTheControllerHasNoToggle() {
        let app = DemoApp.launch(screen: "exclusion-controller-readonly", arguments: Self.defaultLevels)
        XCTAssertTrue(app.navigationBars["controller02"].waitForExistence(timeout: 90), "The controller page did not open.\n\(app.debugDescription)")
        for _ in 0..<6 { app.swipeUp() }
        XCTAssertFalse(app.switches["excludeFromSiteViewsToggle"].exists, "A person who cannot edit the controller is offered the toggle.\n\(app.debugDescription)")
    }

    func testAnOlderServerHasNoToggleAndTheControllerPageStillShowsItsOwnAlarms() {
        let app = DemoApp.launch(screen: "controller-own-alarms")
        let alarm = text(app, "Gripper suction pressure is low")
        scrollUntilExists(alarm, in: app)
        XCTAssertFalse(app.switches["excludeFromSiteViewsToggle"].exists, "An older server is offered the toggle.")
        XCTAssertFalse(DemoApp.element(app, "alarmLevelBar").exists, "An older server's alarms are filtered by level.")
        XCTAssertTrue(text(app, "Conveyor 2 is running slowly").exists, "An older server's warning is hidden.")
    }

    // MARK: - Alarm levels

    func testTheSitePageCountsCriticalAndErrorByDefaultAndTheChipsAddLevels() {
        let app = DemoApp.launch(screen: "alarm-levels", arguments: Self.defaultLevels)
        let tile = tile(app, "statTile.alarms")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 90), "The site did not open.\n\(app.debugDescription)")
        scrollUntilExists(tile, in: app)
        // Critical, Error (in capitals) and the alarm of a level nobody knows.
        XCTAssertTrue(waitForLabel(tile, containing: "3"), "The count is not of Critical and Error: \"\(tile.label)\".")
        let warning = DemoApp.element(app, "alarmLevel.warning")
        reveal(warning, in: app)
        XCTAssertTrue(warning.label.contains("2"), "The Warning chip does not count both warnings: \"\(warning.label)\".")
        XCTAssertTrue(DemoApp.element(app, "alarmLevel.critical").label.contains("1"), "The Critical chip does not count its alarm.")
        XCTAssertTrue(DemoApp.element(app, "alarmLevel.error").label.contains("1"), "The Error chip does not count an alarm in capitals.")
        XCTAssertTrue(DemoApp.element(app, "alarmLevel.info").label.contains("1"), "The Info chip does not count its alarm.")
        warning.tap()
        for _ in 0..<15 where !(tile.exists && tile.isHittable) { app.swipeDown() }
        XCTAssertTrue(waitForLabel(tile, containing: "5"), "Turning Warning on did not add its alarms to the count: \"\(tile.label)\".")
    }

    func testTheAlarmListHidesTheLevelsThatAreOffButAlwaysShowsAnUnknownLevel() {
        let app = DemoApp.launch(screen: "alarm-levels-list", arguments: Self.defaultLevels)
        XCTAssertTrue(text(app, "Safety scanner tripped at the dock").waitForExistence(timeout: 90), "The critical alarm is not listed.\n\(app.debugDescription)")
        XCTAssertTrue(text(app, "Gripper suction pressure is low").exists, "An error written in capitals is hidden.")
        XCTAssertTrue(text(app, "A new kind of alarm").exists, "An alarm of an unknown level is hidden.")
        XCTAssertFalse(text(app, "Conveyor 2 is running slowly").exists, "A warning is shown with Warning off.")
        XCTAssertFalse(text(app, "Label stock is low").exists, "A warning written with a capital is shown with Warning off.")
        DemoApp.element(app, "alarmLevel.warning").tap()
        XCTAssertTrue(text(app, "Conveyor 2 is running slowly").waitForExistence(timeout: 30), "Turning Warning on did not list its alarms.\n\(app.debugDescription)")
        XCTAssertTrue(text(app, "Label stock is low").exists, "A warning written with a capital is not listed.")
    }

    func testAListWhoseAlarmsAreAllAtOtherLevelsSaysHowMany() {
        let app = DemoApp.launch(screen: "alarm-levels-warnings", arguments: Self.defaultLevels)
        let note = DemoApp.element(app, "alarmLevelEmptyNote")
        scrollUntilExists(note, in: app)
        XCTAssertEqual(note.label, "No active alarms at these levels. 2 at other levels.")
    }

    func testAControllersAlarmsAreFilteredByLevelToo() {
        let app = DemoApp.launch(screen: "alarm-levels-controller", arguments: Self.defaultLevels)
        let bar = DemoApp.element(app, "alarmLevelBar")
        scrollUntilExists(bar, in: app)
        XCTAssertTrue(text(app, "Safety scanner tripped at the dock").exists, "The controller's critical alarm is not listed.\n\(app.debugDescription)")
        XCTAssertFalse(text(app, "Conveyor 2 is running slowly").exists, "The controller lists a warning with Warning off.")
    }

    func testAnOlderServerListsEveryLevelWithNoFilter() {
        let app = DemoApp.launch(screen: "site-alarms")
        XCTAssertTrue(text(app, "Gripper suction pressure is low").waitForExistence(timeout: 90), "The alarm is not listed.\n\(app.debugDescription)")
        XCTAssertTrue(text(app, "Conveyor 2 is running slowly").exists, "An older server's warning is hidden.")
        XCTAssertFalse(DemoApp.element(app, "alarmLevelBar").exists, "An older server's alarms are filtered by level.")
    }
}
