import XCTest

/// Launches the app in its demo mode, which serves invented data and needs no server or sign-in. The screen name is the
/// same one the screenshots job passes as PORTAL_DEMO_SCREEN.
@MainActor
enum DemoApp {
    static func launch(screen: String, persona: String? = nil, environment: [String: String] = [:], arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + arguments
        app.launchEnvironment["PORTAL_DEMO_SCREEN"] = screen
        if let persona { app.launchEnvironment["PORTAL_DEMO_PERSONA"] = persona }
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 90), "The app did not come to the foreground")
        return app
    }

    /// Any element with this accessibility identifier, whatever its type.
    static func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// A button with this accessibility identifier. A tile or a button is a Button to the accessibility tree; asking for that
    /// type keeps the query cheap on a busy runner.
    static func button(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.buttons.matching(identifier: identifier).firstMatch
    }

    /// Whether the center of the element is in the band of the window where a tap lands on it: below the navigation bar and
    /// well above the tab bar and the floating buttons that sit over the bottom of a scrolled page. An element that exists
    /// but has no frame yet (a row that has not been laid out, or one still moving) is not in the band.
    static func isInTapBand(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        guard window.height > 0, frame.width > 0, frame.height > 0 else { return false }
        return frame.midY > window.minY + window.height * 0.15 && frame.midY < window.minY + window.height * 0.70
    }

    /// Waits until the element has stopped moving: a page that is still loading, or still scrolling to a section, moves
    /// the tile between the moment it is found and the moment it is tapped.
    static func waitUntilStill(_ element: XCUIElement, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var stableReadings = 0
        var lastFrame = CGRect.null
        while Date() < deadline {
            let frame = element.exists ? element.frame : CGRect.null
            if frame == lastFrame, !frame.isNull, !frame.isEmpty { stableReadings += 1 } else { stableReadings = 0 }
            if stableReadings >= 3 { return true }
            lastFrame = frame
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    /// Whether the element appears within the timeout. Unlike `waitForExistence`, a query whose snapshot times out while the app
    /// is still busy launching is asked again rather than failing the test.
    static func waitUntilExists(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Whether the element's label comes to contain the text within the timeout: a label that follows a tap or a save is read once it has
    /// settled, not at the first frame after it.
    static func waitUntilLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 20) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Whether the element's value comes to contain the text within the timeout, for a field filled after it appears.
    static func waitUntilValue(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 20) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Whether the system reports the element hittable within the timeout. A predicate keeps a snapshot that fails while the
    /// page is still moving from failing the test: it is evaluated again until the timeout.
    static func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Brings the element into the tap band, scrolling the page up or down, and returns once it is still and hittable.
    static func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 90), "\(element) never appeared", file: file, line: line)
        // Whether the last move pushed the page up (to show what is below), so a row that left the screen can be brought back.
        var didLastMovePageUp: Bool?
        // The way short drags go while the row is missing: chosen once, the other way from the move that lost it, and kept, so
        // drag after drag goes on toward it instead of each one undoing the last.
        var missingDragIsUp: Bool?
        for attempt in 0..<20 {
            if isInTapBand(element, in: app), waitUntilStill(element), isInTapBand(element, in: app), waitUntilHittable(element) { return }
            guard element.exists, element.frame.height > 0 else {
                // A row a scroll carried out of a lazy list leaves the accessibility tree, so its frame says nothing. It went the way the
                // page last moved: short drags the other way bring it back without overshooting again.
                let isUp = missingDragIsUp ?? !(didLastMovePageUp ?? true)
                missingDragIsUp = isUp
                dragPage(app, isUp: isUp)
                didLastMovePageUp = isUp
                continue
            }
            missingDragIsUp = nil
            let window = app.windows.firstMatch.frame
            let isAboveBand = element.frame.midY <= window.minY + window.height * 0.15
            if attempt >= 4 {
                dragPage(app, isUp: !isAboveBand)
            } else if isAboveBand {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            didLastMovePageUp = !isAboveBand
        }
        XCTFail("\(element) could not be scrolled into the tap band", file: file, line: line)
    }

    /// A short drag that stops where it ends: a swipe can carry a page past the band in both directions, as in a sheet.
    private static func dragPage(_ app: XCUIApplication, isUp: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: isUp ? 0.65 : 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: isUp ? 0.4 : 0.65))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Goes back one screen with the back button of the screen on top. It is asked for by name because the system adds it to the
    /// bar after the screen's own buttons, so for a moment the first button of the bar can be another one.
    static func goBack(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let systemBackButton = app.navigationBars.buttons["BackButton"]
        if systemBackButton.waitForExistence(timeout: 10) {
            systemBackButton.tap()
            return
        }
        let backButton = app.navigationBars.element(boundBy: 0).buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 10), "There is no back button", file: file, line: line)
        backButton.tap()
    }
}
