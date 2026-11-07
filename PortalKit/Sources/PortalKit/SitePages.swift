import Foundation

/// SitePage is one documentation page of a site, as the pages tree lists it and as one page is read.
///
/// A page that was never published has no revision: its title and words are the draft's. A published page shows its current
/// revision, and a draft saved after that waits for the next publish.
public struct SitePage: Decodable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let siteId: String?
    public let organizationId: String?
    public let parentPageId: String?
    /// The order among the pages with the same parent: lower comes first.
    public let position: Int64?
    public let currentRevisionId: String?
    public let createdAt: String?
    public let modifiedAt: String?
    public let deletedAt: String?
    public let createdByUserId: String?
    public let modifiedByUserId: String?
    /// The published title, or the draft's while the page is unpublished.
    public let title: String?
    public let icon: String?
    public let isPublished: Bool?
    public let draftTitle: String?
    public let draftContent: String?
    public let draftSummary: String?
    public let draftModifiedAt: String?
    public let draftModifiedByUserId: String?
    /// What the viewer may do at the page's site, such as `page:edit`. Only a read of the page says; a mutation does not.
    public let viewerCapabilities: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, siteId, organizationId, parentPageId, position, currentRevisionId, createdAt, modifiedAt, deletedAt
        case createdByUserId, modifiedByUserId, title, icon, isPublished, draftTitle, draftContent, draftSummary
        case draftModifiedAt, draftModifiedByUserId, viewerCapabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        siteId = try container.decodeIfPresent(String.self, forKey: .siteId)
        organizationId = try container.decodeIfPresent(String.self, forKey: .organizationId)
        parentPageId = try container.decodeIfPresent(String.self, forKey: .parentPageId)
        position = try Self.decodeWholeNumber(container, forKey: .position)
        currentRevisionId = try container.decodeIfPresent(String.self, forKey: .currentRevisionId)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        modifiedAt = try container.decodeIfPresent(String.self, forKey: .modifiedAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        createdByUserId = try container.decodeIfPresent(String.self, forKey: .createdByUserId)
        modifiedByUserId = try container.decodeIfPresent(String.self, forKey: .modifiedByUserId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        isPublished = try container.decodeIfPresent(Bool.self, forKey: .isPublished)
        draftTitle = try container.decodeIfPresent(String.self, forKey: .draftTitle)
        draftContent = try container.decodeIfPresent(String.self, forKey: .draftContent)
        draftSummary = try container.decodeIfPresent(String.self, forKey: .draftSummary)
        draftModifiedAt = try container.decodeIfPresent(String.self, forKey: .draftModifiedAt)
        draftModifiedByUserId = try container.decodeIfPresent(String.self, forKey: .draftModifiedByUserId)
        viewerCapabilities = try container.decodeIfPresent([String].self, forKey: .viewerCapabilities)
    }

    public init(
        id: String, siteId: String? = nil, organizationId: String? = nil, parentPageId: String? = nil, position: Int64? = nil,
        currentRevisionId: String? = nil, createdAt: String? = nil, modifiedAt: String? = nil, deletedAt: String? = nil,
        createdByUserId: String? = nil, modifiedByUserId: String? = nil, title: String? = nil, icon: String? = nil, isPublished: Bool? = true,
        draftTitle: String? = nil, draftContent: String? = nil, draftSummary: String? = nil, draftModifiedAt: String? = nil,
        draftModifiedByUserId: String? = nil, viewerCapabilities: [String]? = nil
    ) {
        self.id = id
        self.siteId = siteId
        self.organizationId = organizationId
        self.parentPageId = parentPageId
        self.position = position
        self.currentRevisionId = currentRevisionId
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.createdByUserId = createdByUserId
        self.modifiedByUserId = modifiedByUserId
        self.title = title
        self.icon = icon
        self.isPublished = isPublished
        self.draftTitle = draftTitle
        self.draftContent = draftContent
        self.draftSummary = draftSummary
        self.draftModifiedAt = draftModifiedAt
        self.draftModifiedByUserId = draftModifiedByUserId
        self.viewerCapabilities = viewerCapabilities
    }

    /// A whole number the server may send as a JSON number or as text, as a 64-bit number can be.
    static func decodeWholeNumber<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Int64? {
        if let number = try? container.decodeIfPresent(Int64.self, forKey: key) { return number }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) { return Int64(text) }
        return nil
    }

    public func can(_ capability: String) -> Bool { viewerCapabilities?.contains(capability) ?? false }

    /// Whether the viewer may change the page's title and words: `page:edit`.
    public var canEdit: Bool { can("page:edit") }

    /// Whether the viewer may publish the page: `page:publish`.
    public var canPublish: Bool { can("page:publish") }

    /// Whether readers cannot see the page yet because it was never published.
    public var isDraft: Bool { isPublished != true }

    /// Whether the page shows a revision: one that is published and has a current revision. Any other page shows its draft.
    public var showsRevision: Bool { isPublished == true && !(currentRevisionId ?? "").isEmpty }

    public var modifiedDate: Date? { PortalDate.parse(modifiedAt) }

    /// The title to show, as the web does: the current revision's when the page shows one, else the page's own title, else the
    /// draft's. Empty when the page has none, for the screen to call it untitled.
    public func shownTitle(revision: SitePageRevision?) -> String {
        if showsRevision {
            return Self.firstFilled([revision?.title, title, draftTitle])
        }
        return Self.firstFilled([draftTitle, title])
    }

    /// The words to show: the current revision's when the page shows one (nothing until it is read), else the draft's.
    public func shownContent(revision: SitePageRevision?) -> String {
        showsRevision ? (revision?.content ?? "") : (draftContent ?? "")
    }

    /// The title for a list, which has no revision to read.
    public var listTitle: String { Self.firstFilled([title, draftTitle]) }

    private static func firstFilled(_ texts: [String?]) -> String {
        for text in texts {
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        return ""
    }

    /// The page with the viewer's capabilities put back. A mutation does not work them out and answers without them, so the screen
    /// keeps the ones it read.
    public func replacingViewerCapabilities(_ capabilities: [String]?) -> SitePage {
        SitePage(
            id: id, siteId: siteId, organizationId: organizationId, parentPageId: parentPageId, position: position, currentRevisionId: currentRevisionId,
            createdAt: createdAt, modifiedAt: modifiedAt, deletedAt: deletedAt, createdByUserId: createdByUserId, modifiedByUserId: modifiedByUserId,
            title: title, icon: icon, isPublished: isPublished, draftTitle: draftTitle, draftContent: draftContent, draftSummary: draftSummary,
            draftModifiedAt: draftModifiedAt, draftModifiedByUserId: draftModifiedByUserId, viewerCapabilities: capabilities)
    }

    /// What the editor starts with: the draft the server holds, and the published words when the page has no draft words.
    public func editingDraft(revision: SitePageRevision?) -> SitePageDraft {
        SitePageDraft(
            title: Self.firstFilled([draftTitle, title]), content: draftContent ?? revision?.content ?? "", summary: draftSummary ?? "")
    }
}

/// SitePageRevision is one published version of a page. Revisions are never changed after they are made.
public struct SitePageRevision: Decodable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let pageId: String?
    public let organizationId: String?
    /// 1 for the first publish, counting up per page.
    public let revisionNumber: Int64?
    public let title: String?
    public let content: String?
    /// What the author said changed, when they said.
    public let summary: String?
    public let authorUserId: String?
    public let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, pageId, organizationId, revisionNumber, title, content, summary, authorUserId, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        pageId = try container.decodeIfPresent(String.self, forKey: .pageId)
        organizationId = try container.decodeIfPresent(String.self, forKey: .organizationId)
        revisionNumber = try SitePage.decodeWholeNumber(container, forKey: .revisionNumber)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        authorUserId = try container.decodeIfPresent(String.self, forKey: .authorUserId)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    public init(
        id: String, pageId: String? = nil, organizationId: String? = nil, revisionNumber: Int64? = nil, title: String? = nil, content: String? = nil,
        summary: String? = nil, authorUserId: String? = nil, createdAt: String? = nil
    ) {
        self.id = id
        self.pageId = pageId
        self.organizationId = organizationId
        self.revisionNumber = revisionNumber
        self.title = title
        self.content = content
        self.summary = summary
        self.authorUserId = authorUserId
        self.createdAt = createdAt
    }

    public var date: Date? { PortalDate.parse(createdAt) }

    /// The revision a publish just made, from the draft that was sent and the page the server answered with, so the screen can show
    /// it without reading it back. Nil when the page has no current revision.
    public static func published(draft: SitePageDraft, page: SitePage) -> SitePageRevision? {
        guard let revisionId = page.currentRevisionId, !revisionId.isEmpty else { return nil }
        return SitePageRevision(
            id: revisionId, pageId: page.id, organizationId: page.organizationId, title: SitePageRules.trimmedTitle(draft.title), content: draft.content,
            summary: draft.summary, authorUserId: page.modifiedByUserId, createdAt: page.modifiedAt)
    }

    /// The revisions newest first: the highest revision number, then the latest time.
    public static func newestFirst(_ revisions: [SitePageRevision]) -> [SitePageRevision] {
        revisions.sorted { first, second in
            let firstNumber = first.revisionNumber ?? 0
            let secondNumber = second.revisionNumber ?? 0
            if firstNumber != secondNumber { return firstNumber > secondNumber }
            return (first.date ?? .distantPast) > (second.date ?? .distantPast)
        }
    }
}

/// SitePageDraft is the title, words and note of a change that an editor holds before it is saved.
public struct SitePageDraft: Equatable, Sendable {
    public var title: String
    public var content: String
    /// A short note of what changed, kept with the revision a publish makes.
    public var summary: String

    public init(title: String = "", content: String = "", summary: String = "") {
        self.title = title
        self.content = content
        self.summary = summary
    }
}

/// SitePageProblem is why a draft cannot be saved, as the server would refuse it.
public enum SitePageProblem: Equatable, Sendable {
    case titleIsEmpty
    case titleIsTooLong
    case contentIsTooLarge
    case summaryIsTooLong
}

/// SitePageRules are the limits the server holds a page to, checked before a request so the person is told at once.
public enum SitePageRules {
    public static let maximumTitleLength = 256
    public static let maximumContentByteCount = 1 << 20
    public static let maximumSummaryLength = 512

    /// What the server says when a page, a revision or a site is not there, which it also says of one the person may not see.
    public static let notFoundMessage = "not found"

    /// Whether the error says the thing asked for is not there, so the screen can say so instead of "could not load".
    public static func isNotFound(_ error: Error) -> Bool {
        guard case PortalError.refused(let message) = error else { return false }
        return message.lowercased().contains(notFoundMessage)
    }

    /// The words to show under a title. Many pages open with a heading that says the title again, which on the screen would read
    /// twice in a row, so that one heading is left out. The page itself keeps it: only what is drawn changes.
    public static func wordsBelowTitle(_ words: String, title: String) -> String {
        let lines = words.components(separatedBy: "\n")
        guard let headingIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return words }
        let heading = lines[headingIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard heading.hasPrefix("# ") else { return words }
        let headingWords = heading.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        guard headingWords.caseInsensitiveCompare(trimmedTitle(title)) == .orderedSame else { return words }
        let remaining = lines[(headingIndex + 1)...].drop { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return remaining.joined(separator: "\n")
    }

    /// The title as it is sent: without the spaces around it.
    public static func trimmedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first reason the server would refuse the draft, if any. Lengths are counted in bytes, as the server counts them.
    public static func problem(in draft: SitePageDraft) -> SitePageProblem? {
        let title = trimmedTitle(draft.title)
        if title.isEmpty { return .titleIsEmpty }
        if title.utf8.count > maximumTitleLength { return .titleIsTooLong }
        if draft.content.utf8.count > maximumContentByteCount { return .contentIsTooLarge }
        if draft.summary.utf8.count > maximumSummaryLength { return .summaryIsTooLong }
        return nil
    }
}

/// SitePageNode is a page with the pages inside it, for a list that opens and closes them. A page with none has `children` nil,
/// which is what such a list asks for.
public struct SitePageNode: Equatable, Identifiable, Sendable {
    public let page: SitePage
    public let children: [SitePageNode]?

    public var id: String { page.id }
}

/// SitePageTree lays the flat list of a site's pages out as the web's tree does: by parent, and among siblings by position.
public enum SitePageTree {
    /// The pages with this parent in display order: position, then id. A nil parent is the top of the tree, and a page whose
    /// parent is not in the list counts as being at the top.
    public static func children(of parentPageId: String?, in pages: [SitePage]) -> [SitePage] {
        let knownIds = Set(pages.map(\.id))
        let siblings = pages.filter { page in
            let parent = page.parentPageId ?? ""
            if let parentPageId { return parent == parentPageId }
            return parent.isEmpty || !knownIds.contains(parent)
        }
        return siblings.sorted { first, second in
            let firstPosition = first.position ?? 0
            let secondPosition = second.position ?? 0
            if firstPosition != secondPosition { return firstPosition < secondPosition }
            return first.id < second.id
        }
    }

    /// The tree: the pages at the top, each with the pages inside it, in display order. A loop of pages that name each other as
    /// parent is never reached from the top, so it is not drawn.
    public static func nodes(_ pages: [SitePage]) -> [SitePageNode] {
        func node(_ page: SitePage, visited: Set<String>) -> SitePageNode {
            let inside = children(of: page.id, in: pages).filter { !visited.contains($0.id) }
            let seen = visited.union([page.id])
            return SitePageNode(page: page, children: inside.isEmpty ? nil : inside.map { node($0, visited: seen) })
        }
        return children(of: nil, in: pages).map { node($0, visited: []) }
    }

    /// The pages whose title has the words, in the order of the tree. Nothing for no words.
    public static func matches(_ pages: [SitePage], query: String) -> [SitePage] {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return [] }
        var found: [SitePage] = []
        func visit(_ nodes: [SitePageNode]) {
            for node in nodes {
                if node.page.listTitle.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) != nil { found.append(node.page) }
                visit(node.children ?? [])
            }
        }
        visit(nodes(pages))
        return found
    }

    /// The pages above the page, nearest parent first. Stops at the top, at a parent that is not in the list, and at a loop.
    public static func ancestorIds(of pageId: String, in pages: [SitePage]) -> [String] {
        let byId = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ancestors: [String] = []
        var seen: Set<String> = [pageId]
        var cursor = byId[pageId]
        while let parentId = cursor?.parentPageId, !parentId.isEmpty, !seen.contains(parentId), let parent = byId[parentId] {
            ancestors.append(parentId)
            seen.insert(parentId)
            cursor = parent
        }
        return ancestors
    }

    /// The position that puts a new page after its siblings: one past the highest, or 0 when there are none.
    public static func appendPosition(afterSiblings siblings: [SitePage]) -> Int64 {
        guard let highest = siblings.map({ $0.position ?? 0 }).max() else { return 0 }
        return highest + 1
    }
}

extension ServerCapabilities {
    /// Documentation pages: reading them, and the fields that say which page shows a draft and what the viewer may do. An older
    /// server hides the feature rather than failing on a field it lacks.
    public var offersSitePages: Bool {
        offersQuery("ListPages") && offersQuery("GetPage") && offersQuery("GetPageRevision") && offersQuery("ListPageRevisions")
            && ["viewerCapabilities", "isPublished", "draftTitle", "draftContent", "currentRevisionId", "parentPageId"].allSatisfy(pageFieldNames.contains)
    }

    /// Whether the viewer can be offered to change a page: the operations to create, save and publish one.
    public var offersSitePageEditing: Bool {
        offersSitePages && offersMutation("CreatePage") && offersMutation("ModifyPage") && offersMutation("PublishPage")
    }
}

extension Documents {
    /// The fields of a page that is read whole, as the web's page fragment has them. The viewer's capabilities are asked for on a
    /// read only: a mutation does not work them out, and would answer null.
    static let sitePageFields = """
        id createdAt modifiedAt organizationId siteId parentPageId position currentRevisionId createdByUserId modifiedByUserId deletedAt title icon
        isPublished draftTitle draftContent draftSummary draftModifiedAt draftModifiedByUserId
        """

    /// The fields a list of pages needs: no words, which can be large.
    static let sitePageListFields = "id siteId organizationId parentPageId position currentRevisionId modifiedAt title icon isPublished draftTitle"

    static let sitePageRevisionFields = "id createdAt pageId organizationId revisionNumber title content summary authorUserId"

    public static let listSitePages = """
        query ListPages($siteId: String!, $options: ListOptionsInput) {
          ListPages(siteId: $siteId, options: $options) {
            pages { \(sitePageListFields) viewerCapabilities }
            meta { totalCount }
          }
        }
        """

    public static let getSitePage = """
        query GetPage($pageId: String!) { GetPage(pageId: $pageId) { \(sitePageFields) viewerCapabilities } }
        """

    public static let getSitePageRevision = """
        query GetPageRevision($pageRevisionId: String!) { GetPageRevision(pageRevisionId: $pageRevisionId) { \(sitePageRevisionFields) } }
        """

    public static let listSitePageRevisions = """
        query ListPageRevisions($pageId: String!) { ListPageRevisions(pageId: $pageId) { \(sitePageRevisionFields) } }
        """

    public static let createSitePage = """
        mutation CreatePage($siteId: String!, $parentPageId: String, $title: String!, $content: String!, $summary: String, $position: Int64) {
          CreatePage(siteId: $siteId, parentPageId: $parentPageId, title: $title, content: $content, summary: $summary, position: $position) {
            page { \(sitePageFields) }
          }
        }
        """

    public static let modifySitePage = """
        mutation ModifyPage($pageId: String!, $title: String, $content: String, $summary: String) {
          ModifyPage(pageId: $pageId, title: $title, content: $content, summary: $summary) { page { \(sitePageFields) } }
        }
        """

    public static let publishSitePage = """
        mutation PublishPage($pageId: String!, $title: String, $content: String, $summary: String) {
          PublishPage(pageId: $pageId, title: $title, content: $content, summary: $summary) { page { \(sitePageFields) } }
        }
        """

    /// The site a page list belongs to, for its name and what the viewer may do there.
    public static let getSiteForPages = """
        query GetSite($siteId: String!) { GetSite(siteId: $siteId) { id name organizationId viewerCapabilities } }
        """

    static var sitePageDocuments: [String] {
        [
            listSitePages, getSitePage, getSitePageRevision, listSitePageRevisions, createSitePage, modifySitePage, publishSitePage, getSiteForPages,
        ]
    }
}

extension Connection {
    /// The pages of a site, every one, in the order the server lists them. The server answers in pages of 200, as the web asks.
    public func sitePages(siteId: String, pageSize: Int = 200) async throws -> [SitePage] {
        var collected: [SitePage] = []
        while true {
            let list = try await sitePageList(siteId: siteId, pageSize: pageSize, offset: collected.count)
            let page = list.pages ?? []
            collected += page
            if page.isEmpty { break }
            if let total = list.meta?.totalCount, collected.count >= total { break }
            if page.count < pageSize, list.meta?.totalCount == nil { break }
        }
        return collected
    }

    private struct SitePageList: Decodable, Sendable {
        struct Meta: Decodable, Sendable { let totalCount: Int? }
        let pages: [SitePage]?
        let meta: Meta?
    }

    private func sitePageList(siteId: String, pageSize: Int, offset: Int) async throws -> SitePageList {
        struct Answer: Decodable, Sendable { let ListPages: SitePageList }
        var variables: [String: JSONValue] = [
            "siteId": .string(siteId), "options": .object(["first": .number(Double(pageSize)), "after": .number(Double(offset))]),
        ]
        return try await execute(Documents.listSitePages, variables: variables, as: Answer.self).ListPages
    }

    /// One page. A page the person may not see is the same as one that is not there, and comes back as an error.
    public func sitePage(id: String) async throws -> SitePage {
        struct Answer: Decodable, Sendable { let GetPage: SitePage? }
        guard let page = try await execute(Documents.getSitePage, variables: ["pageId": .string(id)], as: Answer.self).GetPage else {
            throw PortalError.refused(SitePageRules.notFoundMessage)
        }
        return page
    }

    public func sitePageRevision(id: String) async throws -> SitePageRevision {
        struct Answer: Decodable, Sendable { let GetPageRevision: SitePageRevision? }
        guard let revision = try await execute(Documents.getSitePageRevision, variables: ["pageRevisionId": .string(id)], as: Answer.self).GetPageRevision else {
            throw PortalError.refused(SitePageRules.notFoundMessage)
        }
        return revision
    }

    /// The published versions of a page, newest first.
    public func sitePageRevisions(pageId: String) async throws -> [SitePageRevision] {
        struct Answer: Decodable, Sendable { let ListPageRevisions: [SitePageRevision]? }
        let revisions = try await execute(Documents.listSitePageRevisions, variables: ["pageId": .string(pageId)], as: Answer.self).ListPageRevisions ?? []
        return SitePageRevision.newestFirst(revisions)
    }

    /// The site a page list belongs to, for its name and what the viewer may do there.
    public func siteForPages(id: String) async throws -> SiteSummary {
        struct Answer: Decodable, Sendable { let GetSite: SiteSummary? }
        guard let site = try await execute(Documents.getSiteForPages, variables: ["siteId": .string(id)], as: Answer.self).GetSite else {
            throw PortalError.refused(SitePageRules.notFoundMessage)
        }
        return site
    }

    /// Makes a page that nobody but its editors sees until it is published. With no `position` it goes after its siblings.
    public func createSitePage(siteId: String, parentPageId: String?, title: String, content: String = "", position: Int64? = nil) async throws -> SitePage {
        struct Answer: Decodable, Sendable {
            struct Created: Decodable, Sendable { let page: SitePage }
            let CreatePage: Created
        }
        var variables: [String: JSONValue] = [
            "siteId": .string(siteId), "title": .string(SitePageRules.trimmedTitle(title)), "content": .string(content),
        ]
        if let parentPageId, !parentPageId.isEmpty { variables["parentPageId"] = .string(parentPageId) }
        if let position { variables["position"] = .number(Double(position)) }
        return try await execute(Documents.createSitePage, variables: variables, as: Answer.self).CreatePage.page
    }

    /// Saves the draft of a page. Readers keep seeing the published words until the page is published.
    @discardableResult
    public func saveSitePageDraft(pageId: String, draft: SitePageDraft) async throws -> SitePage {
        struct Answer: Decodable, Sendable {
            struct Changed: Decodable, Sendable { let page: SitePage }
            let ModifyPage: Changed
        }
        return try await execute(Documents.modifySitePage, variables: Self.draftVariables(pageId: pageId, draft: draft), as: Answer.self).ModifyPage.page
    }

    /// Saves the draft and makes it the page's current revision, as one request, so a publish needs no save before it.
    @discardableResult
    public func publishSitePage(pageId: String, draft: SitePageDraft) async throws -> SitePage {
        struct Answer: Decodable, Sendable {
            struct Changed: Decodable, Sendable { let page: SitePage }
            let PublishPage: Changed
        }
        return try await execute(Documents.publishSitePage, variables: Self.draftVariables(pageId: pageId, draft: draft), as: Answer.self).PublishPage.page
    }

    /// The variables of a save or a publish. An empty note is left out, which keeps the note already on the draft.
    static func draftVariables(pageId: String, draft: SitePageDraft) -> [String: JSONValue] {
        var variables: [String: JSONValue] = [
            "pageId": .string(pageId), "title": .string(SitePageRules.trimmedTitle(draft.title)), "content": .string(draft.content),
        ]
        if !draft.summary.isEmpty { variables["summary"] = .string(draft.summary) }
        return variables
    }
}
