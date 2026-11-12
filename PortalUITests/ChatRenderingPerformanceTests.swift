import XCTest

/// A long chat full of formulas and diagrams: how it scrolls, how much memory it holds, and that a drawing, once made, is a picture
/// that does not draw again as it scrolls.
@MainActor
final class ChatRenderingPerformanceTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = true
    }

    private func drawings(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["mathParagraph", "mathFormula", "mermaidDiagram"]))
    }

    func testALongChatOfFormulasScrollsAndHoldsPicturesNotWebViews() {
        let app = DemoApp.launch(screen: "rendering-formulas")
        let newest = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Formula message 120")).firstMatch
        XCTAssertTrue(DemoApp.waitUntilExists(newest, timeout: 90), "The conversation did not open.\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 3)

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric, XCTMemoryMetric(application: app), XCTCPUMetric(application: app)], options: options) {
            for _ in 0..<3 { app.swipeDown(velocity: .fast) }
            for _ in 0..<3 { app.swipeUp(velocity: .fast) }
        }

        // Settled, every drawing on screen is a picture: the web views that made them are gone.
        Thread.sleep(forTimeInterval: 3)
        let webViewCount = app.webViews.count
        let pictureCount = app.images.matching(NSPredicate(format: "identifier IN %@", ["mathParagraph", "mathFormula", "mermaidDiagram"])).count
        print("[rendering-performance] web views after settling: \(webViewCount); drawings shown as pictures: \(pictureCount)")
        XCTAssertLessThanOrEqual(webViewCount, 4, "Drawings that settled are still web views.\n\(app.debugDescription)")
        XCTAssertGreaterThan(pictureCount, 0, "No drawing became a picture.\n\(app.debugDescription)")

        // Scrolled away and back, a drawing shows its picture at once, with no web view drawing it again.
        app.swipeDown(velocity: .fast)
        app.swipeUp(velocity: .fast)
        Thread.sleep(forTimeInterval: 0.3)
        let pending = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", ["mathParagraphPending", "mathFormulaPending", "mermaidDiagramPending"])).count
        XCTAssertEqual(pending, 0, "A drawing drew again after scrolling back.\n\(app.debugDescription)")
        XCTAssertGreaterThan(drawings(app).count, 0)
    }
}
