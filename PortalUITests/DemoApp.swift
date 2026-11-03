import XCTest

/// Launches the app in its demo mode, which serves invented data and needs no server or sign-in. The screen name is the
/// same one the screenshots job passes as PORTAL_DEMO_SCREEN.
@MainActor
enum DemoApp {
    static func launch(screen: String, persona: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launchEnvironment["PORTAL_DEMO_SCREEN"] = screen
        if let persona { app.launchEnvironment["PORTAL_DEMO_PERSONA"] = persona }
        app.launch()
        return app
    }

    /// Any element with this accessibility identifier, whatever its type.
    static func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scrolls the screen up until the element can be tapped.
    static func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 45), "\(element) never appeared", file: file, line: line)
        var attempts = 0
        while !element.isHittable && attempts < 10 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) cannot be tapped", file: file, line: line)
    }

    /// Goes back one screen with the back button of the screen on top.
    static func goBack(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let backButton = app.navigationBars.element(boundBy: 0).buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 10), "There is no back button", file: file, line: line)
        backButton.tap()
    }
}
