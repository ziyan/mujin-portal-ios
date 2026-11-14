import XCTest

/// A Markdown table wider than the phone: one finger drags it sideways in its row, two fingers spreading open it full screen, and
/// so does its full screen button. Full screen it zooms and closes as a picture does.
@MainActor
final class MarkdownTableZoomTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func revealTable(_ app: XCUIApplication) -> XCUIElement {
        let table = DemoApp.element(app, "markdownTable")
        XCTAssertTrue(table.waitForExistence(timeout: 90), "The page never showed its table.\n\(app.debugDescription)")
        DemoApp.scrollToElement(table, in: app)
        return table
    }

    private func viewer(_ app: XCUIApplication) -> XCUIElement { DemoApp.element(app, "markdownTableViewer") }

    func testAWideTableDragsSideways() {
        let app = DemoApp.launch(screen: "site-page-rich")
        let table = revealTable(app)
        Thread.sleep(forTimeInterval: 1)
        let before = table.screenshot().pngRepresentation
        // A slow drag that stops where it ends, as one finger on the table does; a swipe is a flick the page may take for its own.
        let start = table.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = table.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertNotEqual(table.screenshot().pngRepresentation, before, "A drag did not move the table sideways.")
        XCTAssertFalse(viewer(app).exists, "A one finger drag opened the table full screen.")
    }

    func testAPinchOpensTheTableFullScreenWhereItZoomsAndCloses() {
        let app = DemoApp.launch(screen: "site-page-rich")
        revealTable(app).pinch(withScale: 2, velocity: 1)
        XCTAssertTrue(viewer(app).waitForExistence(timeout: 10), "A pinch did not open the table full screen.\n\(app.debugDescription)")
        let shown = viewer(app)
        let before = shown.screenshot().pngRepresentation
        shown.pinch(withScale: 3, velocity: 2)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertNotEqual(shown.screenshot().pngRepresentation, before, "A pinch did not zoom the table.")
        shown.doubleTap()
        let close = DemoApp.button(app, "markdownTableViewerCloseButton")
        XCTAssertTrue(DemoApp.waitUntilHittable(close, timeout: 10), "The viewer has no way to close.\n\(app.debugDescription)")
        close.tap()
        XCTAssertTrue(DemoApp.element(app, "markdownTable").waitForExistence(timeout: 10), "Closing did not come back to the page.")
        XCTAssertFalse(viewer(app).exists, "The viewer stayed open.")
    }

    func testTheFormulasAndDiagramOfAPageKeepTheirOwnNames() {
        let app = DemoApp.launch(screen: "site-page-rich")
        XCTAssertTrue(DemoApp.element(app, "sitePageWords").waitForExistence(timeout: 90), "The page never appeared.\n\(app.debugDescription)")
        let paragraph = DemoApp.element(app, "mathParagraph")
        XCTAssertTrue(paragraph.waitForExistence(timeout: 30), "The formulas in the words are not drawn.\n\(app.debugDescription)")
        XCTAssertTrue(paragraph.label.contains("frac{n}{t}"), "VoiceOver reads \"\(paragraph.label)\", without the formula.")
        XCTAssertTrue(DemoApp.element(app, "mathFormula").waitForExistence(timeout: 30), "The formula on its own line is not drawn.\n\(app.debugDescription)")
        let diagram = DemoApp.element(app, "mermaidDiagram")
        DemoApp.scrollToElement(diagram, in: app)
    }

    func testTheFullScreenButtonOpensTheTable() {
        let app = DemoApp.launch(screen: "site-page-rich")
        _ = revealTable(app)
        let open = DemoApp.button(app, "markdownTableOpenButton")
        DemoApp.scrollToElement(open, in: app)
        XCTAssertTrue(DemoApp.waitUntilHittable(open, timeout: 10), "The table has no full screen button.\n\(app.debugDescription)")
        open.tap()
        XCTAssertTrue(viewer(app).waitForExistence(timeout: 10), "The button did not open the table full screen.\n\(app.debugDescription)")
    }
}
