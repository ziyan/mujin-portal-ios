import XCTest

/// The documentation pages of a site: the row on the site screen, the tree, a page with its words, the draft and publish rules of the
/// editor, the history, and the links that open a page in the app instead of the browser. Each test waits for the screen it is about
/// before it looks at anything on it.
@MainActor
final class SitePagesTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// The title of the page on screen, once the page has loaded.
    private func pageTitle(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let title = DemoApp.element(app, "sitePageTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 90), "The page never appeared.\n\(app.debugDescription)", file: file, line: line)
        return title
    }

    /// Opens the editor of the page on screen and returns its title field.
    private func openEditor(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let edit = DemoApp.button(app, "sitePageEditButton")
        XCTAssertTrue(edit.waitForExistence(timeout: 30), "The page offers no way to edit.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertTrue(DemoApp.waitUntilHittable(edit, timeout: 30), "The edit button cannot be tapped.\n\(app.debugDescription)", file: file, line: line)
        edit.tap()
        let field = DemoApp.element(app, "sitePageTitleField")
        XCTAssertTrue(field.waitForExistence(timeout: 30), "The editor did not open.\n\(app.debugDescription)", file: file, line: line)
        return field
    }

    /// Waits for the editor to go away.
    private func waitForEditorToClose(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let field = DemoApp.element(app, "sitePageTitleField")
        let deadline = Date().addingTimeInterval(30)
        while field.exists, Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertFalse(field.exists, "The editor stayed open.\n\(app.debugDescription)", file: file, line: line)
    }

    private func text(_ app: XCUIApplication, _ words: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    /// A list builds its rows as they come near the screen, so a row further down does not exist until the page has scrolled to it.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<12 {
            if element.waitForExistence(timeout: 2) { return true }
            app.swipeUp()
        }
        return element.exists
    }

    // MARK: - The site screen and the tree

    func testTheSiteScreenOffersThePagesAndOpensTheTree() {
        let app = DemoApp.launch(screen: "site-pages-row")
        XCTAssertTrue(DemoApp.element(app, "sitePage").waitForExistence(timeout: 90), "The site page never appeared.\n\(app.debugDescription)")
        let row = DemoApp.button(app, "sitePagesRow")
        DemoApp.scrollToElement(row, in: app)
        row.tap()
        XCTAssertTrue(DemoApp.element(app, "sitePagesList").waitForExistence(timeout: 30), "The tree did not open.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.element(app, "sitePageRow-page01").waitForExistence(timeout: 30), "The tree has no first page.\n\(app.debugDescription)")
    }

    func testAnOlderServerHasNoPagesRow() {
        let app = DemoApp.launch(screen: "site")
        XCTAssertTrue(DemoApp.element(app, "sitePage").waitForExistence(timeout: 90), "The site page never appeared.\n\(app.debugDescription)")
        // The chat row sits in the same section, so once it is there the section is drawn.
        XCTAssertTrue(reveal(DemoApp.element(app, "siteChatRow"), in: app), "The Resources section never appeared.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.element(app, "sitePagesRow").exists, "A server without pages offered them.\n\(app.debugDescription)")
    }

    func testATappedPageOpensWithItsTitleAndWords() {
        let app = DemoApp.launch(screen: "site-pages")
        let row = DemoApp.element(app, "sitePageRow-page01")
        XCTAssertTrue(row.waitForExistence(timeout: 90), "The tree never appeared.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.waitUntilHittable(row, timeout: 30), "The page cannot be tapped.\n\(app.debugDescription)")
        row.tap()
        XCTAssertEqual(pageTitle(app).label, "Pick station operating guide")
        XCTAssertTrue(text(app, "Walk the belt from the infeed").waitForExistence(timeout: 30), "The words of the page are not shown.\n\(app.debugDescription)")
    }

    func testTheTreeCanBeSearchedByTitle() {
        let app = DemoApp.launch(screen: "site-pages")
        XCTAssertTrue(DemoApp.element(app, "sitePageRow-page01").waitForExistence(timeout: 90), "The tree never appeared.\n\(app.debugDescription)")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30), "The tree has no search field.\n\(app.debugDescription)")
        search.tap()
        search.typeText("gripper")
        XCTAssertTrue(DemoApp.element(app, "sitePageRow-page04").waitForExistence(timeout: 30), "The search found no match.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.element(app, "sitePageRow-page01").exists, "The search kept a page that does not match.\n\(app.debugDescription)")
    }

    func testASiteWithNoPagesSaysSo() {
        let app = DemoApp.launch(screen: "site-pages-empty")
        XCTAssertTrue(app.staticTexts["No pages yet"].waitForExistence(timeout: 90), "The empty site does not say it has no pages.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.button(app, "sitePageNewButton").waitForExistence(timeout: 15), "A person who may edit is offered no new page.\n\(app.debugDescription)")
    }

    func testAFailedLoadOffersAnotherTry() {
        let app = DemoApp.launch(screen: "site-pages-error")
        XCTAssertTrue(app.staticTexts["Could not load the documentation"].waitForExistence(timeout: 90), "The failure is not shown.\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["Try again"].exists, "There is no way to try again.\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["Open on the web"].exists, "There is no way to open the pages on the web.\n\(app.debugDescription)")
    }

    // MARK: - A page

    func testALongPageShowsAllOfItsWords() {
        let app = DemoApp.launch(screen: "site-page")
        _ = pageTitle(app)
        XCTAssertTrue(text(app, "Walk the belt from the infeed").waitForExistence(timeout: 30), "The start of the page is not shown.\n\(app.debugDescription)")
        XCTAssertTrue(reveal(text(app, "A guide that is out of date"), in: app), "The end of the page is not shown.\n\(app.debugDescription)")
    }

    func testAPageThatIsNotThereOffersTheWeb() {
        let app = DemoApp.launch(screen: "site-page-missing")
        XCTAssertTrue(DemoApp.element(app, "sitePageNotFound").waitForExistence(timeout: 90), "A missing page does not say so.\n\(app.debugDescription)")
        let web = app.buttons["Open on the web"]
        XCTAssertTrue(web.waitForExistence(timeout: 15), "A missing page offers no way to open it on the web.\n\(app.debugDescription)")
        web.tap()
        let close = DemoApp.element(app, "webBrowserClose")
        XCTAssertTrue(close.waitForExistence(timeout: 30), "The browser did not open.\n\(app.debugDescription)")
    }

    func testAPersonWhoCannotEditSeesNoWayToEdit() {
        let app = DemoApp.launch(screen: "site-page-readonly")
        _ = pageTitle(app)
        XCTAssertTrue(text(app, "Walk the belt from the infeed").waitForExistence(timeout: 30), "The words of the page are not shown.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.button(app, "sitePageEditButton").exists, "A person who cannot edit was offered the editor.\n\(app.debugDescription)")
    }

    // MARK: - Editing

    func testSavingADraftKeepsWhatReadersSeeAndPublishingChangesIt() {
        let app = DemoApp.launch(screen: "site-page")
        let title = pageTitle(app)
        XCTAssertEqual(title.label, "Pick station operating guide")

        // A saved draft is kept, and the page readers see stays as it was.
        var field = openEditor(app)
        field.tap()
        field.typeText("-Z9")
        let save = DemoApp.button(app, "sitePageSaveDraftButton")
        XCTAssertTrue(DemoApp.waitUntilHittable(save, timeout: 15), "Save draft cannot be tapped.\n\(app.debugDescription)")
        save.tap()
        waitForEditorToClose(app)
        XCTAssertFalse(pageTitle(app).label.contains("Z9"), "A saved draft changed the page readers see.\n\(app.debugDescription)")
        field = openEditor(app)
        XCTAssertTrue((field.value as? String ?? "").contains("Z9"), "The saved draft was not kept.\n\(app.debugDescription)")

        // Publishing makes the draft the page.
        let publish = DemoApp.button(app, "sitePagePublishButton")
        XCTAssertTrue(publish.waitForExistence(timeout: 15), "A person who may publish is not offered it.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.waitUntilHittable(publish, timeout: 15), "Publish cannot be tapped.\n\(app.debugDescription)")
        publish.tap()
        waitForEditorToClose(app)
        XCTAssertTrue(pageTitle(app).label.contains("Z9"), "A published draft did not become the page.\n\(app.debugDescription)")
    }

    func testAPublishedDraftPageLosesItsDraftMark() {
        let app = DemoApp.launch(screen: "site-page-draft")
        _ = pageTitle(app)
        XCTAssertTrue(DemoApp.element(app, "sitePageDraftBadge").waitForExistence(timeout: 15), "A page never published is not marked as a draft.\n\(app.debugDescription)")
        _ = openEditor(app)
        let publish = DemoApp.button(app, "sitePagePublishButton")
        XCTAssertTrue(publish.waitForExistence(timeout: 15), "A person who may publish is not offered it.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.waitUntilHittable(publish, timeout: 15), "Publish cannot be tapped.\n\(app.debugDescription)")
        publish.tap()
        waitForEditorToClose(app)
        _ = pageTitle(app)
        let deadline = Date().addingTimeInterval(15)
        let badge = DemoApp.element(app, "sitePageDraftBadge")
        while badge.exists, Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertFalse(badge.exists, "A published page is still marked as a draft.\n\(app.debugDescription)")
    }

    func testAPersonWhoCanEditButNotPublishIsOnlyOfferedADraft() {
        let app = DemoApp.launch(screen: "site-page-author")
        _ = pageTitle(app)
        _ = openEditor(app)
        XCTAssertTrue(DemoApp.button(app, "sitePageSaveDraftButton").waitForExistence(timeout: 15), "The editor offers no way to save a draft.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.button(app, "sitePagePublishButton").exists, "A person who may not publish was offered it.\n\(app.debugDescription)")
    }

    func testANewPageStartsAsADraft() {
        let app = DemoApp.launch(screen: "site-pages")
        XCTAssertTrue(DemoApp.element(app, "sitePageRow-page01").waitForExistence(timeout: 90), "The tree never appeared.\n\(app.debugDescription)")
        let add = DemoApp.button(app, "sitePageNewButton")
        XCTAssertTrue(DemoApp.waitUntilHittable(add, timeout: 30), "The new page button cannot be tapped.\n\(app.debugDescription)")
        add.tap()
        let field = DemoApp.element(app, "sitePageNewTitleField")
        XCTAssertTrue(field.waitForExistence(timeout: 30), "The new page sheet did not open.\n\(app.debugDescription)")
        field.tap()
        field.typeText("Loading dock notes")
        let create = DemoApp.button(app, "sitePageCreateButton")
        XCTAssertTrue(DemoApp.waitUntilHittable(create, timeout: 15), "Create cannot be tapped.\n\(app.debugDescription)")
        create.tap()
        XCTAssertEqual(pageTitle(app).label, "Loading dock notes")
        XCTAssertTrue(DemoApp.element(app, "sitePageDraftBadge").waitForExistence(timeout: 15), "A new page is not marked as a draft.\n\(app.debugDescription)")
    }

    // MARK: - History

    func testTheHistoryListsTheVersionsAndOpensOneToRead() {
        let app = DemoApp.launch(screen: "site-page")
        _ = pageTitle(app)
        let history = DemoApp.button(app, "sitePageHistoryRow")
        XCTAssertTrue(reveal(history, in: app), "The page has no history row.\n\(app.debugDescription)")
        for _ in 0..<10 where !history.isHittable { app.swipeUp() }
        XCTAssertTrue(DemoApp.waitUntilHittable(history, timeout: 15), "The history row cannot be tapped.\n\(app.debugDescription)")
        history.tap()
        for revision in ["revision-page01-3", "revision-page01-2", "revision-page01-1"] {
            XCTAssertTrue(DemoApp.element(app, "sitePageRevisionRow-\(revision)").waitForExistence(timeout: 30), "The history lacks \(revision).\n\(app.debugDescription)")
        }
        let older = DemoApp.element(app, "sitePageRevisionRow-revision-page01-2")
        XCTAssertTrue(DemoApp.waitUntilHittable(older, timeout: 15), "A version cannot be tapped.\n\(app.debugDescription)")
        older.tap()
        XCTAssertTrue(DemoApp.element(app, "sitePageRevisionTitle").waitForExistence(timeout: 30), "The version did not open.\n\(app.debugDescription)")
        XCTAssertFalse(DemoApp.button(app, "sitePageEditButton").exists, "An earlier version can be edited.\n\(app.debugDescription)")
    }

    // MARK: - Links

    func testASearchResultForAPageOpensItInTheApp() {
        let app = DemoApp.launch(screen: "site-pages-search")
        let row = DemoApp.button(app, "searchRow-page|page01")
        XCTAssertTrue(row.waitForExistence(timeout: 90), "The search found no page.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.waitUntilHittable(row, timeout: 30), "The page cannot be tapped.\n\(app.debugDescription)")
        row.tap()
        XCTAssertTrue(DemoApp.element(app, "linkedPageClose").waitForExistence(timeout: 60), "The result opened no sheet.\n\(app.debugDescription)")
        XCTAssertEqual(pageTitle(app).label, "Pick station operating guide")
        XCTAssertFalse(DemoApp.element(app, "webBrowserClose").exists, "The page opened in the browser.\n\(app.debugDescription)")
    }
}
