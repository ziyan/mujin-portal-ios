import XCTest

/// Pictures Markdown outside the chat: a site documentation page with formulas, a diagram and a wide table, the table dragged
/// sideways and opened full screen with a pinch, and a ticket comment with a formula. Each is shown in light and dark, at the
/// default text size and the largest, and named `<what>-<appearance>-<size>.png`. Pictures go to the folder RENDERING_SHOTS_DIRECTORY
/// names, when the run sets it, and are attached to the result besides.
@MainActor
final class RichMarkdownDocumentTests: XCTestCase {
    private struct Look {
        let appearance: XCUIDevice.Appearance
        let appearanceName: String
        let isLargestText: Bool
        var sizeName: String { isLargestText ? "largest" : "default" }
    }

    private static let looks = [
        Look(appearance: .light, appearanceName: "light", isLargestText: false), Look(appearance: .dark, appearanceName: "dark", isLargestText: false),
        Look(appearance: .light, appearanceName: "light", isLargestText: true), Look(appearance: .dark, appearanceName: "dark", isLargestText: true),
    ]

    override func setUp() async throws {
        continueAfterFailure = true
    }

    override func tearDown() async throws {
        XCUIDevice.shared.appearance = .light
    }

    func testASitePageDrawsItsFormulasDiagramAndTable() {
        for look in Self.looks {
            let app = launch(screen: "site-page-rich", look: look)
            let words = DemoApp.element(app, "sitePageWords")
            guard words.waitForExistence(timeout: 90) else {
                XCTFail("[\(look.appearanceName) \(look.sizeName)] the page did not show.\n\(app.debugDescription)")
                app.terminate()
                continue
            }
            let suffix = "\(look.appearanceName)-\(look.sizeName)"
            XCTAssertTrue(DemoApp.element(app, "mathFormula").waitForExistence(timeout: 30), "[\(suffix)] the formula on its own line is not drawn.")
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\\frac")).firstMatch.exists, "[\(suffix)] a formula shows its source.")
            Thread.sleep(forTimeInterval: 2)
            save(app.screenshot().pngRepresentation, name: "document-page-top-\(suffix)")

            let diagram = DemoApp.element(app, "mermaidDiagram")
            DemoApp.scrollToElement(diagram, in: app)
            Thread.sleep(forTimeInterval: 1.5)
            save(app.screenshot().pngRepresentation, name: "document-page-diagram-\(suffix)")

            let table = DemoApp.element(app, "markdownTable")
            DemoApp.scrollToElement(table, in: app)
            Thread.sleep(forTimeInterval: 1)
            save(app.screenshot().pngRepresentation, name: "document-table-\(suffix)")
            table.swipeLeft()
            Thread.sleep(forTimeInterval: 1)
            save(app.screenshot().pngRepresentation, name: "document-table-dragged-\(suffix)")

            table.pinch(withScale: 2, velocity: 1)
            let viewer = DemoApp.element(app, "markdownTableViewer")
            if viewer.waitForExistence(timeout: 10) {
                Thread.sleep(forTimeInterval: 1)
                save(app.screenshot().pngRepresentation, name: "document-table-full-screen-\(suffix)")
                viewer.pinch(withScale: 3, velocity: 2)
                Thread.sleep(forTimeInterval: 1)
                save(app.screenshot().pngRepresentation, name: "document-table-pinched-\(suffix)")
            } else {
                XCTFail("[\(suffix)] a pinch did not open the table full screen.")
            }
            app.terminate()
        }
    }

    func testATicketCommentDrawsItsFormula() {
        for look in Self.looks {
            let app = launch(screen: "ticket-formula", look: look)
            let suffix = "\(look.appearanceName)-\(look.sizeName)"
            let comment = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "which is inside the limit")).firstMatch
            guard comment.waitForExistence(timeout: 90) else {
                XCTFail("[\(suffix)] the comment did not show.\n\(app.debugDescription)")
                app.terminate()
                continue
            }
            DemoApp.scrollToElement(comment, in: app)
            let formula = DemoApp.element(app, "mathFormula")
            XCTAssertTrue(formula.waitForExistence(timeout: 30), "[\(suffix)] the comment's formula is not drawn.")
            DemoApp.scrollToElement(formula, in: app)
            Thread.sleep(forTimeInterval: 2)
            save(app.screenshot().pngRepresentation, name: "ticket-comment-formula-\(suffix)")
            app.terminate()
        }
    }

    private func launch(screen: String, look: Look) -> XCUIApplication {
        XCUIDevice.shared.appearance = look.appearance
        var arguments: [String] = []
        if look.isLargestText { arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        return DemoApp.launch(screen: screen, arguments: arguments)
    }

    private func save(_ png: Data, name: String) {
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["RENDERING_SHOTS_DIRECTORY"], !folder.isEmpty {
            let directory = URL(fileURLWithPath: folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}
