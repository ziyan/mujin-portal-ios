import XCTest

/// A newer app shows a card at the top of the chat list. "Not now" lasts for that update, and the next one shows again.
@MainActor
final class AppUpdateTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(screen: String, build: Int) -> XCUIApplication {
        DemoApp.launch(screen: screen, environment: ["PORTAL_DEMO_UPDATE": "1.0:\(build)"])
    }

    func testNotNowLastsUntilANewerUpdate() {
        // A build no earlier run put off: the simulator keeps what the app remembers.
        let build = Int(Date().timeIntervalSince1970)
        var app = launch(screen: "update-available", build: build)
        let card = DemoApp.element(app, "appUpdateCard")
        XCTAssertTrue(card.waitForExistence(timeout: 60), "The card did not show.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.element(app, "appUpdateOpen").exists, "The card offers no way to update.\n\(app.debugDescription)")
        let notNow = DemoApp.element(app, "appUpdateNotNow")
        XCTAssertTrue(DemoApp.waitUntilHittable(notNow, timeout: 30), "The card cannot be put off.\n\(app.debugDescription)")
        notNow.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 10), "The card stayed after Not now.\n\(app.debugDescription)")
        app.terminate()

        app = launch(screen: "update-available", build: build)
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 60), "The app did not open.\n\(app.debugDescription)")
        XCTAssertFalse(
            DemoApp.element(app, "appUpdateCard").waitForExistence(timeout: 5), "An update put off came back after a restart.\n\(app.debugDescription)")
        app.terminate()

        app = launch(screen: "update-available", build: build + 1)
        XCTAssertTrue(DemoApp.element(app, "appUpdateCard").waitForExistence(timeout: 60), "A newer update did not show.\n\(app.debugDescription)")
    }

    func testSettingsKeepsOfferingAnUpdatePutOff() {
        let build = Int(Date().timeIntervalSince1970) + 1000
        var app = launch(screen: "update-available", build: build)
        let notNow = DemoApp.element(app, "appUpdateNotNow")
        XCTAssertTrue(notNow.waitForExistence(timeout: 60), "The card did not show.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.waitUntilHittable(notNow, timeout: 30), "The card cannot be put off.\n\(app.debugDescription)")
        notNow.tap()
        app.terminate()

        app = launch(screen: "settings", build: build)
        XCTAssertTrue(DemoApp.element(app, "appUpdateRow").waitForExistence(timeout: 60), "Settings does not offer the update.\n\(app.debugDescription)")
    }
}
