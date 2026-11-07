import Foundation
import Testing

@testable import PortalKit

/// The documentation pages of a site: reading them, the tree, what is shown for a draft and for a published page, and the
/// requests that save and publish.
@Suite struct SitePageTests {
    static func decode(_ json: String) throws -> SitePage {
        try JSONDecoder().decode(SitePage.self, from: Data(json.utf8))
    }

    // MARK: - Reading

    @Test func aPageReadsWithItsPositionAsANumberOrAsText() throws {
        let numeric = try Self.decode(#"{"id":"page01","position":3,"parentPageId":null,"title":"Start","isPublished":true}"#)
        #expect(numeric.position == 3)
        #expect(numeric.parentPageId == nil)
        let text = try Self.decode(#"{"id":"page02","position":"7"}"#)
        #expect(text.position == 7)
        let missing = try Self.decode(#"{"id":"page03"}"#)
        #expect(missing.position == nil)
        #expect(missing.viewerCapabilities == nil)
    }

    @Test func theViewerCapabilitiesSayWhatThePersonMayDo() throws {
        let editor = try Self.decode(#"{"id":"page01","viewerCapabilities":["page:edit","page:publish"]}"#)
        #expect(editor.canEdit)
        #expect(editor.canPublish)
        let author = try Self.decode(#"{"id":"page01","viewerCapabilities":["page:edit"]}"#)
        #expect(author.canEdit)
        #expect(!author.canPublish)
        let reader = try Self.decode(#"{"id":"page01","viewerCapabilities":[]}"#)
        #expect(!reader.canEdit)
        #expect(!reader.canPublish)
        #expect(!SitePage(id: "page01").canEdit)
    }

    @Test func aRevisionReadsWithItsNumberAsANumberOrAsText() throws {
        let numeric = try JSONDecoder().decode(SitePageRevision.self, from: Data(#"{"id":"revision01","revisionNumber":4,"summary":null}"#.utf8))
        #expect(numeric.revisionNumber == 4)
        let text = try JSONDecoder().decode(SitePageRevision.self, from: Data(#"{"id":"revision02","revisionNumber":"2"}"#.utf8))
        #expect(text.revisionNumber == 2)
    }

    @Test func revisionsAreListedNewestFirst() {
        let revisions = [
            SitePageRevision(id: "a", revisionNumber: 1, createdAt: "2026-01-01T00:00:00Z"),
            SitePageRevision(id: "c", revisionNumber: 3, createdAt: "2026-03-01T00:00:00Z"),
            SitePageRevision(id: "b", revisionNumber: 2, createdAt: "2026-02-01T00:00:00Z"),
        ]
        #expect(SitePageRevision.newestFirst(revisions).map(\.id) == ["c", "b", "a"])
    }

    // MARK: - What a page shows

    @Test func aPageNeverPublishedShowsItsDraft() {
        let page = SitePage(id: "page01", currentRevisionId: nil, title: "Shown title", isPublished: false, draftTitle: "Draft title", draftContent: "Draft words")
        #expect(page.isDraft)
        #expect(!page.showsRevision)
        #expect(page.shownTitle(revision: nil) == "Draft title")
        #expect(page.shownContent(revision: nil) == "Draft words")
        // A revision is not read for it, and would not be used if it were.
        let revision = SitePageRevision(id: "revision01", title: "Old", content: "Old words")
        #expect(page.shownContent(revision: revision) == "Draft words")
    }

    @Test func aPublishedPageShowsItsCurrentRevisionAndNotALaterDraft() {
        let page = SitePage(
            id: "page01", currentRevisionId: "revision02", title: "Published title", isPublished: true, draftTitle: "Next title", draftContent: "Next words")
        let revision = SitePageRevision(id: "revision02", title: "Published title", content: "Published words")
        #expect(!page.isDraft)
        #expect(page.showsRevision)
        #expect(page.shownTitle(revision: revision) == "Published title")
        #expect(page.shownContent(revision: revision) == "Published words")
        // Until the revision is read there are no words, and never the draft's.
        #expect(page.shownContent(revision: nil) == "")
        #expect(page.shownTitle(revision: nil) == "Published title")
    }

    @Test func aPublishedPageWithoutACurrentRevisionShowsItsDraft() {
        let page = SitePage(id: "page01", currentRevisionId: nil, isPublished: true, draftTitle: "Draft title", draftContent: "Draft words")
        #expect(!page.showsRevision)
        #expect(page.shownContent(revision: nil) == "Draft words")
    }

    @Test func aPageWithNoTitleHasAnEmptyOneForTheScreenToName() {
        #expect(SitePage(id: "page01", title: "  ", draftTitle: nil).listTitle == "")
        #expect(SitePage(id: "page01", title: nil, draftTitle: "Draft only").listTitle == "Draft only")
    }

    @Test func theEditorStartsFromTheDraftAndFallsBackToThePublishedWords() {
        let withDraft = SitePage(id: "page01", title: "Published", isPublished: true, draftTitle: "Next", draftContent: "Next words", draftSummary: "Reworded")
        #expect(withDraft.editingDraft(revision: nil) == SitePageDraft(title: "Next", content: "Next words", summary: "Reworded"))
        let withoutDraftWords = SitePage(id: "page02", title: "Published", isPublished: true, draftTitle: nil, draftContent: nil)
        let revision = SitePageRevision(id: "revision01", content: "Published words")
        #expect(withoutDraftWords.editingDraft(revision: revision) == SitePageDraft(title: "Published", content: "Published words", summary: ""))
    }

    @Test func aMutationsAnswerKeepsWhatThePersonMayDo() {
        let answered = SitePage(id: "page01", title: "Start", viewerCapabilities: nil)
        let kept = answered.replacingViewerCapabilities(["page:edit"])
        #expect(kept.canEdit)
        #expect(kept.id == "page01")
        #expect(kept.title == "Start")
        #expect(answered.replacingViewerCapabilities(nil) == answered)
    }

    @Test func aPublishedRevisionIsMadeFromTheDraftThatWasSent() {
        let page = SitePage(id: "page01", currentRevisionId: "revision07", modifiedAt: "2026-05-01T10:00:00Z", modifiedByUserId: "user01", title: "Start", isPublished: true)
        let revision = SitePageRevision.published(draft: SitePageDraft(title: " Start ", content: "Words", summary: "Reworded"), page: page)
        #expect(revision?.id == "revision07")
        #expect(revision?.title == "Start")
        #expect(revision?.content == "Words")
        #expect(revision?.summary == "Reworded")
        #expect(revision?.authorUserId == "user01")
        #expect(SitePageRevision.published(draft: SitePageDraft(title: "Start"), page: SitePage(id: "page02")) == nil)
    }

    // MARK: - Rules

    @Test func aDraftIsRefusedForTheReasonsTheServerGives() {
        #expect(SitePageRules.problem(in: SitePageDraft(title: "  ", content: "Words")) == .titleIsEmpty)
        #expect(SitePageRules.problem(in: SitePageDraft(title: String(repeating: "a", count: 257))) == .titleIsTooLong)
        #expect(SitePageRules.problem(in: SitePageDraft(title: String(repeating: "a", count: 256))) == nil)
        #expect(SitePageRules.problem(in: SitePageDraft(title: "Title", content: String(repeating: "a", count: (1 << 20) + 1))) == .contentIsTooLarge)
        #expect(SitePageRules.problem(in: SitePageDraft(title: "Title", content: "", summary: String(repeating: "a", count: 513))) == .summaryIsTooLong)
        #expect(SitePageRules.problem(in: SitePageDraft(title: " Title ", content: "", summary: "")) == nil)
    }

    @Test func lengthsAreCountedInBytes() {
        // 86 characters of 3 bytes each is 258 bytes: over the limit though under it in characters.
        #expect(SitePageRules.problem(in: SitePageDraft(title: String(repeating: "\u{6F22}", count: 86))) == .titleIsTooLong)
    }

    @Test func aNotFoundAnswerIsToldApartFromOtherFailures() {
        #expect(SitePageRules.isNotFound(PortalError.refused("not found")))
        #expect(SitePageRules.isNotFound(PortalError.refused("Not Found: page")))
        #expect(!SitePageRules.isNotFound(PortalError.refused("permission denied")))
        #expect(!SitePageRules.isNotFound(PortalError.unreadableAnswer))
        #expect(!SitePageRules.isNotFound(URLError(.notConnectedToInternet)))
    }

    // MARK: - The tree

    static let pages: [SitePage] = [
        SitePage(id: "b-guides", parentPageId: nil, position: 1, title: "Guides"),
        SitePage(id: "a-start", parentPageId: nil, position: 0, title: "Start here"),
        SitePage(id: "d-safety", parentPageId: "b-guides", position: 1, title: "Safety"),
        SitePage(id: "c-setup", parentPageId: "b-guides", position: 0, title: "Setup"),
        SitePage(id: "e-wiring", parentPageId: "c-setup", position: 0, title: "Wiring", isPublished: false, draftTitle: "Wiring"),
        SitePage(id: "f-orphan", parentPageId: "gone", position: 5, title: "Moved away"),
    ]

    @Test func siblingsAreOrderedByPositionThenId() {
        #expect(SitePageTree.children(of: nil, in: Self.pages).map(\.id) == ["a-start", "b-guides", "f-orphan"])
        #expect(SitePageTree.children(of: "b-guides", in: Self.pages).map(\.id) == ["c-setup", "d-safety"])
        let tied = [SitePage(id: "z", position: 2), SitePage(id: "m", position: 2), SitePage(id: "q", position: nil)]
        #expect(SitePageTree.children(of: nil, in: tied).map(\.id) == ["q", "m", "z"])
    }

    @Test func theTreeHoldsEachPageInsideItsParent() {
        let tree = SitePageTree.nodes(Self.pages)
        #expect(tree.map(\.id) == ["a-start", "b-guides", "f-orphan"])
        #expect(tree[0].children == nil)
        let guides = tree[1]
        #expect(guides.children?.map(\.id) == ["c-setup", "d-safety"])
        #expect(guides.children?.first?.children?.map(\.id) == ["e-wiring"])
        #expect(guides.children?.last?.children == nil)
        #expect(SitePageTree.nodes([]).isEmpty)
    }

    @Test func aSearchListsTheMatchesInTheOrderOfTheTree() {
        #expect(SitePageTree.matches(Self.pages, query: "wir").map(\.id) == ["e-wiring"])
        #expect(SitePageTree.matches(Self.pages, query: "SET").map(\.id) == ["c-setup"])
        #expect(SitePageTree.matches(Self.pages, query: "s").map(\.id) == ["a-start", "b-guides", "c-setup", "d-safety"])
        #expect(SitePageTree.matches(Self.pages, query: "nothing like it").isEmpty)
        #expect(SitePageTree.matches(Self.pages, query: "   ").isEmpty)
    }

    @Test func theAncestorsAreListedNearestFirst() {
        #expect(SitePageTree.ancestorIds(of: "e-wiring", in: Self.pages) == ["c-setup", "b-guides"])
        #expect(SitePageTree.ancestorIds(of: "a-start", in: Self.pages).isEmpty)
        #expect(SitePageTree.ancestorIds(of: "f-orphan", in: Self.pages).isEmpty)
        #expect(SitePageTree.ancestorIds(of: "unknown", in: Self.pages).isEmpty)
    }

    @Test func pagesThatPointAtEachOtherDoNotLoopForever() {
        let loop = [SitePage(id: "one", parentPageId: "two"), SitePage(id: "two", parentPageId: "one"), SitePage(id: "three")]
        #expect(SitePageTree.ancestorIds(of: "one", in: loop) == ["two"])
        // Neither is at the top, so neither is drawn, and drawing ends.
        #expect(SitePageTree.nodes(loop).map(\.id) == ["three"])
    }

    @Test func aNewPageGoesAfterItsSiblings() {
        #expect(SitePageTree.appendPosition(afterSiblings: []) == 0)
        #expect(SitePageTree.appendPosition(afterSiblings: [SitePage(id: "a", position: 0), SitePage(id: "b", position: 4), SitePage(id: "c", position: nil)]) == 5)
    }

    // MARK: - Links

    @Test func theTreeAndAPageAreLinksOfTheirOwn() throws {
        #expect(PortalLink(path: "/site/site01/page") == .sitePages(siteId: "site01"))
        #expect(PortalLink(path: "/site/site01/page/") == .sitePages(siteId: "site01"))
        #expect(PortalLink(path: "/site/site01/page/page01") == .sitePage(id: "page01", siteId: "site01"))
        #expect(PortalLink(path: "/site/site01/page/page01/edit") == .sitePage(id: "page01", siteId: "site01"))
        #expect(PortalLink(path: "/site/site01/page/page01/revision/2") == .sitePage(id: "page01", siteId: "site01"))
        #expect(PortalLink.sitePages(siteId: "site01").path == "/site/site01/page")
        let server = try ServerAddress("https://portal.example.test")
        let link = PortalLink.sitePages(siteId: "site01")
        #expect(PortalLink(url: link.url(server: server), server: server) == link)
        #expect(PortalLink(url: URL(string: "https://portal.example.test/site/site01/page/page01")!, server: server) == .sitePage(id: "page01", siteId: "site01"))
        // Other pages below a site still open the site.
        #expect(PortalLink(path: "/site/site01/pages") == .site(id: "site01"))
        #expect(PortalLink(path: "/site/site01") == .site(id: "site01"))
    }

    // MARK: - What the server offers

    static let pageFields: Set<String> = ["id", "viewerCapabilities", "isPublished", "draftTitle", "draftContent", "currentRevisionId", "parentPageId", "title"]
    static let readNames: Set<String> = ["ListPages", "GetPage", "GetPageRevision", "ListPageRevisions"]

    @Test func theFeatureNeedsTheOperationsAndTheFieldsOfThePage() {
        #expect(!ServerCapabilities().offersSitePages)
        #expect(ServerCapabilities(queryNames: Self.readNames, pageFieldNames: Self.pageFields).offersSitePages)
        #expect(ServerCapabilities(queryNames: ["listPages", "getPage", "getPageRevision", "listPageRevisions"], pageFieldNames: Self.pageFields).offersSitePages)
        // A server with the operations and without the draft fields hides it.
        #expect(!ServerCapabilities(queryNames: Self.readNames, pageFieldNames: ["id", "title"]).offersSitePages)
        #expect(!ServerCapabilities(queryNames: Self.readNames, pageFieldNames: Self.pageFields.subtracting(["viewerCapabilities"])).offersSitePages)
        #expect(!ServerCapabilities(queryNames: Self.readNames.subtracting(["ListPageRevisions"]), pageFieldNames: Self.pageFields).offersSitePages)
        #expect(!ServerCapabilities(queryNames: Self.readNames).offersSitePages)
    }

    @Test func editingNeedsTheThreeMutationsToo() {
        let reading = ServerCapabilities(queryNames: Self.readNames, pageFieldNames: Self.pageFields)
        #expect(!reading.offersSitePageEditing)
        let editing = ServerCapabilities(
            queryNames: Self.readNames, mutationNames: ["CreatePage", "ModifyPage", "PublishPage"], pageFieldNames: Self.pageFields)
        #expect(editing.offersSitePageEditing)
        let withoutPublish = ServerCapabilities(queryNames: Self.readNames, mutationNames: ["CreatePage", "ModifyPage"], pageFieldNames: Self.pageFields)
        #expect(!withoutPublish.offersSitePageEditing)
    }

    @Test func theFieldsOfThePageAreReadFromTheSchemaOfTheServer() async {
        let (newer, _) = scriptedConnection { _, _ in
            let queryFields: [[String: Any]] = ["listPages", "getPage", "getPageRevision", "listPageRevisions"].map { ["name": $0] }
            let pageFields: [[String: Any]] = ["id", "viewerCapabilities", "isPublished", "draftTitle", "draftContent", "currentRevisionId", "parentPageId"].map { ["name": $0] }
            return [
                "__schema": ["queryType": ["fields": queryFields], "mutationType": ["fields": []], "subscriptionType": NSNull()],
                "pageType": ["fields": pageFields],
            ]
        }
        #expect(await newer.capabilities().offersSitePages)
        let (older, _) = scriptedConnection { _, _ in
            let queryFields: [[String: Any]] = ["listPages", "getPage", "getPageRevision", "listPageRevisions"].map { ["name": $0] }
            return ["__schema": ["queryType": ["fields": queryFields], "mutationType": ["fields": []], "subscriptionType": NSNull()], "pageType": NSNull()]
        }
        #expect(!(await older.capabilities().offersSitePages))
    }

    // MARK: - Requests

    @Test func theTreeIsAskedForPageAfterPageUntilTheTotalIsReached() async throws {
        let (connection, transport) = scriptedConnection { _, variables in
            let options = variables["options"] as? [String: Any] ?? [:]
            let offset = options["after"] as? Int ?? 0
            let rows: [[String: Any]] = (offset..<min(offset + 2, 5)).map { ["id": "page\($0)", "position": $0, "title": "Page \($0)"] }
            return ["ListPages": ["pages": rows, "meta": ["totalCount": 5]]]
        }
        let pages = try await connection.sitePages(siteId: "site01", pageSize: 2)
        #expect(pages.map(\.id) == ["page0", "page1", "page2", "page3", "page4"])
        #expect(transport.requests.count == 3)
        let first = sentVariables(try #require(transport.requests.first))
        #expect(first["siteId"] as? String == "site01")
    }

    @Test func theTreeDoesNotAskForTheWordsOfEveryPage() {
        #expect(!Documents.listSitePages.contains("draftContent"))
        #expect(Documents.listSitePages.contains("viewerCapabilities"))
        #expect(Documents.getSitePage.contains("draftContent"))
        #expect(Documents.getSitePage.contains("viewerCapabilities"))
    }

    @Test func theMutationsDoNotAskForTheCapabilitiesTheServerDoesNotWorkOut() {
        for document in [Documents.createSitePage, Documents.modifySitePage, Documents.publishSitePage] {
            #expect(!document.contains("viewerCapabilities"))
        }
    }

    private static func expectNotFound(_ read: () async throws -> Void) async {
        do {
            try await read()
            Issue.record("An absent answer was taken as found")
        } catch {
            #expect(SitePageRules.isNotFound(error))
        }
    }

    @Test func aPageThatIsNotThereIsNotFound() async {
        let (connection, _) = scriptedConnection { _, _ in ["GetPage": NSNull(), "GetPageRevision": NSNull(), "GetSite": NSNull()] }
        await Self.expectNotFound { _ = try await connection.sitePage(id: "page01") }
        await Self.expectNotFound { _ = try await connection.sitePageRevision(id: "revision01") }
        await Self.expectNotFound { _ = try await connection.siteForPages(id: "site01") }
    }

    @Test func aPageIsReadWithItsDraftAndWhatThePersonMayDo() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            ["GetPage": ["id": "page01", "title": "Start", "isPublished": false, "draftTitle": "Start", "draftContent": "Words", "viewerCapabilities": ["page:edit"]]]
        }
        let page = try await connection.sitePage(id: "page01")
        #expect(page.isDraft)
        #expect(page.canEdit)
        #expect(page.draftContent == "Words")
        #expect(sentVariables(try #require(transport.requests.last))["pageId"] as? String == "page01")
    }

    @Test func aNewPageStartsEmptyAtTheTopWithTheTitleTrimmed() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["CreatePage": ["page": ["id": "page09", "isPublished": false, "draftTitle": "Floor plan"]]] }
        let page = try await connection.createSitePage(siteId: "site01", parentPageId: nil, title: "  Floor plan ", position: 3)
        #expect(page.id == "page09")
        let variables = sentVariables(try #require(transport.requests.last))
        #expect(variables["siteId"] as? String == "site01")
        #expect(variables["title"] as? String == "Floor plan")
        #expect(variables["content"] as? String == "")
        #expect(variables["parentPageId"] == nil)
        #expect(variables["position"] as? Int == 3)
    }

    @Test func aNewPageInsideAPageNamesItsParent() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["CreatePage": ["page": ["id": "page10"]]] }
        _ = try await connection.createSitePage(siteId: "site01", parentPageId: "page01", title: "Child")
        let variables = sentVariables(try #require(transport.requests.last))
        #expect(variables["parentPageId"] as? String == "page01")
        #expect(variables["position"] == nil)
    }

    @Test func savingADraftSendsTheTitleAndWordsAndLeavesOutAnEmptyNote() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["ModifyPage": ["page": ["id": "page01"]]] }
        try await connection.saveSitePageDraft(pageId: "page01", draft: SitePageDraft(title: " Start ", content: "New words", summary: ""))
        let request = try #require(transport.requests.last)
        let variables = sentVariables(request)
        #expect(variables["pageId"] as? String == "page01")
        #expect(variables["title"] as? String == "Start")
        #expect(variables["content"] as? String == "New words")
        #expect(variables["summary"] == nil)
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(body.contains("mutation ModifyPage"))
        #expect(!body.contains("PublishPage"))
    }

    @Test func publishingSendsTheSameDraftToThePublishMutation() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["PublishPage": ["page": ["id": "page01", "isPublished": true]]] }
        let page = try await connection.publishSitePage(pageId: "page01", draft: SitePageDraft(title: "Start", content: "New words", summary: "Reworded"))
        #expect(page.isPublished == true)
        let request = try #require(transport.requests.last)
        let variables = sentVariables(request)
        #expect(variables["content"] as? String == "New words")
        #expect(variables["summary"] as? String == "Reworded")
        #expect((request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "").contains("mutation PublishPage"))
    }

    @Test func theRevisionsOfAPageComeNewestFirst() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            ["ListPageRevisions": [["id": "r1", "revisionNumber": 1], ["id": "r3", "revisionNumber": 3], ["id": "r2", "revisionNumber": 2]]]
        }
        #expect(try await connection.sitePageRevisions(pageId: "page01").map(\.id) == ["r3", "r2", "r1"])
    }
}
