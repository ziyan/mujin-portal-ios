import XCTest

/// A newer app shows a bar that can be dismissed: the dismissal lasts for that update, and the next one shows again.
@MainActor
final class AppUpdateTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(screen: String, build: Int) -> XCUIApplication {
        DemoApp.launch(screen: screen, environment: ["PORTAL_DEMO_UPDATE": "1.0:\(build)"])
    }

    func testDismissingAnUpdateLastsUntilANewerOne() {
        // A build no earlier run dismissed: the simulator keeps what the app remembers.
        let build = Int(Date().timeIntervalSince1970)
        var app = launch(screen: "main-chat", build: build)
        let bar = DemoApp.element(app, "appUpdateBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 60), "The bar did not show.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.element(app, "appUpdateInstall").exists, "The bar offers no way to update.\n\(app.debugDescription)")
        let dismiss = DemoApp.element(app, "appUpdateDismiss")
        XCTAssertTrue(DemoApp.waitUntilHittable(dismiss, timeout: 30), "The bar cannot be dismissed.\n\(app.debugDescription)")
        dismiss.tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 10), "The bar stayed after it was dismissed.\n\(app.debugDescription)")
        app.terminate()

        app = launch(screen: "main-chat", build: build)
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 60), "The app did not open.\n\(app.debugDescription)")
        XCTAssertFalse(
            DemoApp.element(app, "appUpdateBar").waitForExistence(timeout: 5), "A dismissed update came back after a restart.\n\(app.debugDescription)")
        app.terminate()

        app = launch(screen: "main-chat", build: build + 1)
        XCTAssertTrue(DemoApp.element(app, "appUpdateBar").waitForExistence(timeout: 60), "A newer update did not show.\n\(app.debugDescription)")
    }

    func testAboutKeepsOfferingADismissedUpdate() {
        let build = Int(Date().timeIntervalSince1970) + 1000
        var app = launch(screen: "main-chat", build: build)
        let dismiss = DemoApp.element(app, "appUpdateDismiss")
        XCTAssertTrue(dismiss.waitForExistence(timeout: 60), "The bar did not show.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.waitUntilHittable(dismiss, timeout: 30), "The bar cannot be dismissed.\n\(app.debugDescription)")
        dismiss.tap()
        app.terminate()

        app = launch(screen: "about", build: build)
        XCTAssertTrue(DemoApp.element(app, "appUpdateRow").waitForExistence(timeout: 60), "About does not offer the update.\n\(app.debugDescription)")
    }
}
