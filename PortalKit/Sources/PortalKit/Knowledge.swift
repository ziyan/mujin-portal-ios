import Foundation

/// MemoryPage is one page of what the assistant knows: a path in one of four
/// pools (`user`, `site`, `organization`, `global`), with numbered facts.
public struct MemoryPage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let path: String?
    public let memoryScope: String?
    public let siteId: String?
    public let siteName: String?
    public let userId: String?
    public let organizationId: String?
    public let pageKind: String?
    public let name: String?
    public let summary: String?
    public let liveFactCount: Int?
    public let importance: Double?
    public let dormantAt: String?
    public let modifiedAt: String?
    public let aliases: [String]?
    public let isWritableByReader: Bool?
    public let facts: [MemoryFact]?
    public let links: [MemoryLink]?

    public init(
        id: String, path: String? = nil, memoryScope: String? = "user", name: String? = nil, summary: String? = nil, liveFactCount: Int? = nil,
        facts: [MemoryFact]? = nil, links: [MemoryLink]? = nil, aliases: [String]? = nil, isWritableByReader: Bool? = nil, pageKind: String? = nil,
        siteId: String? = nil, siteName: String? = nil, dormantAt: String? = nil
    ) {
        self.id = id
        self.path = path
        self.memoryScope = memoryScope
        self.name = name
        self.summary = summary
        self.liveFactCount = liveFactCount
        self.facts = facts
        self.links = links
        self.aliases = aliases
        self.isWritableByReader = isWritableByReader
        self.pageKind = pageKind
        self.siteId = siteId
        self.siteName = siteName
        self.dormantAt = dormantAt
        self.userId = nil
        self.organizationId = nil
        self.importance = nil
        self.modifiedAt = nil
    }

    /// The name to show: the page's own, else its path.
    public var shownName: String { MemoryPageName.shown(name: name, path: path) }
    public var isDormant: Bool { !(dormantAt ?? "").isEmpty }

    /// The site a site page belongs to, as a person reads it: the site's name, else "Site" and its id. Nil for a page in any other pool.
    public var siteTitle: String? {
        guard memoryScope == "site" else { return nil }
        let trimmed = (siteName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let identifier = (siteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? "Site" : "Site \(identifier)"
    }
}

/// MemoryPageName is how a page is titled for a person: its own name, else the last part of its path in words.
/// A path is never shown.
public enum MemoryPageName {
    public static func shown(name: String?, path: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return readable(path: path ?? "")
    }

    /// `people/jordan-lee/preferences` becomes `Preferences`; hyphens and underscores become spaces.
    public static func readable(path: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        let words = last.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

/// MemoryFact is one numbered statement on a page, with where it came from.
public struct MemoryFact: Codable, Equatable, Identifiable, Sendable {
    public struct Evidence: Codable, Equatable, Sendable {
        public let evidenceKind: String?
        public let conversationId: String?
        public let conversationMessageId: String?
        public let quote: String?
    }

    public let id: String
    public let number: Int?
    /// `fact`, `preference`, `decision`, `event` or `howto`.
    public let factKind: String?
    public let sentence: String?
    public let importedTitle: String?
    public let tags: [String]?
    public let happenedAt: String?
    public let confidence: Double?
    /// The model could not find its quote in what was said.
    public let isInferred: Bool?
    public let supersededByFactId: String?
    public let dormantAt: String?
    public let createdAt: String?
    public let evidence: [Evidence]?
    public let pagePath: String?
    public let pageName: String?
    /// What a person reads for the page this fact is on.
    public var shownPageName: String { MemoryPageName.shown(name: pageName, path: pagePath) }
    public let memoryScope: String?
    public let siteId: String?

    public init(
        id: String, number: Int? = nil, factKind: String? = "fact", sentence: String? = nil, isInferred: Bool? = nil, supersededByFactId: String? = nil,
        dormantAt: String? = nil, evidence: [Evidence]? = nil, pagePath: String? = nil, pageName: String? = nil, memoryScope: String? = nil,
        siteId: String? = nil, createdAt: String? = nil
    ) {
        self.id = id
        self.number = number
        self.factKind = factKind
        self.sentence = sentence
        self.isInferred = isInferred
        self.supersededByFactId = supersededByFactId
        self.dormantAt = dormantAt
        self.evidence = evidence
        self.pagePath = pagePath
        self.pageName = pageName
        self.memoryScope = memoryScope
        self.siteId = siteId
        self.createdAt = createdAt
        self.importedTitle = nil
        self.tags = nil
        self.happenedAt = nil
        self.confidence = nil
    }

    /// A fact is live when nothing replaced it and it has not faded; the rest is history.
    public var isLive: Bool { (supersededByFactId ?? "").isEmpty && (dormantAt ?? "").isEmpty }
}

/// MemoryLink joins two pages.
public struct MemoryLink: Codable, Equatable, Identifiable, Sendable {
    public let fromMemoryPageId: String?
    public let toMemoryPageId: String?
    /// `related`, `part_of`, `uses`, `works_on`, `located_at`, `owned_by`, `caused_by` or `follows`.
    public let relation: String?
    /// `stated` or `proposed`.
    public let linkStatus: String?
    public let fromPagePath: String?
    public let toPagePath: String?
    public let fromPageName: String?
    public let toPageName: String?
    public let linkWeight: Double?
    public let createdAt: String?

    public var id: String { "\(fromMemoryPageId ?? "")|\(toMemoryPageId ?? "")|\(relation ?? "")" }

    public init(
        fromMemoryPageId: String?, toMemoryPageId: String?, relation: String? = "related", linkStatus: String? = "stated", fromPagePath: String? = nil,
        toPagePath: String? = nil, fromPageName: String? = nil, toPageName: String? = nil
    ) {
        self.fromMemoryPageId = fromMemoryPageId
        self.toMemoryPageId = toMemoryPageId
        self.relation = relation
        self.linkStatus = linkStatus
        self.fromPagePath = fromPagePath
        self.toPagePath = toPagePath
        self.fromPageName = fromPageName
        self.toPageName = toPageName
        self.linkWeight = nil
        self.createdAt = nil
    }
}

/// MemoryRevision is one change in a page's history.
public struct MemoryRevision: Codable, Equatable, Identifiable, Sendable {
    public let revisionNumber: Int?
    public let revisionKind: String?
    public let actorKind: String?
    public let previousValue: String?
    public let newValue: String?
    public let changeReason: String?
    public let memoryFactId: String?
    public let createdAt: String?
    public var id: String { "\(revisionNumber ?? 0)|\(createdAt ?? "")" }
}

/// MemoryCitation is a `[[path#number]]` the assistant wrote in an answer.
public struct MemoryCitation: Equatable, Sendable {
    public let path: String
    public let number: Int
    public var label: String { "\(path)#\(number)" }

    /// The page's name as a person reads it: the last part of its path, in words.
    public var displayName: String {
        MemoryPageName.readable(path: path)
    }

    private static let expression = try! NSRegularExpression(pattern: #"\[\[([a-z0-9][a-z0-9_-]*(?:/[a-z0-9][a-z0-9_-]*)*)#([0-9]+)\]\]"#)

    /// The scheme the app uses to turn a citation into a link that opens the page.
    public static let linkScheme = "portal-memory"

    /// The text with each citation made a Markdown link to `portal-memory:<path>#<number>`,
    /// skipping code spans and fences.
    public static func linking(_ markdown: String) -> String {
        var output = ""
        var isInFence = false
        for (index, line) in markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { output += "\n" }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInFence.toggle()
                output += line
                continue
            }
            output += isInFence ? String(line) : linkingLine(String(line))
        }
        return output
    }

    private static func linkingLine(_ line: String) -> String {
        // Text between backticks is code and is left alone.
        let segments = line.components(separatedBy: "`")
        return segments.enumerated().map { index, segment in
            index % 2 == 1 ? "`" + segment + "`" : replacing(in: segment)
        }.joined()
    }

    private static func replacing(in text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var result = text
        for match in expression.matches(in: text, range: range).reversed() {
            guard let whole = Range(match.range, in: result), let path = Range(match.range(at: 1), in: result), let number = Range(match.range(at: 2), in: result) else { continue }
            let citation = "\(result[path])#\(result[number])"
            let name = MemoryCitation(path: String(result[path]), number: Int(result[number]) ?? 0).displayName
            result.replaceSubrange(whole, with: "[\(name)](\(linkScheme):\(citation))")
        }
        return result
    }

    /// Reads a link made by `linking`.
    public init?(url: URL) {
        guard url.scheme == Self.linkScheme else { return nil }
        // The system's Markdown parser writes the # of a link as %23, so it is read either way.
        let address = url.absoluteString
        let text = (address.removingPercentEncoding ?? address).dropFirst(Self.linkScheme.count + 1)
        let parts = text.split(separator: "#", maxSplits: 1)
        guard parts.count == 2, let number = Int(parts[1]) else { return nil }
        self.path = String(parts[0])
        self.number = number
    }

    public init(path: String, number: Int) {
        self.path = path
        self.number = number
    }
}

extension Documents {
    static let memoryPageFields = "id path memoryScope siteId siteName userId organizationId pageKind name summary liveFactCount importance dormantAt modifiedAt"

    static let memoryFactFields = """
        id number factKind sentence importedTitle tags happenedAt confidence isInferred supersededByFactId dormantAt createdAt
        evidence { evidenceKind conversationId conversationMessageId quote }
        """

    static let memoryLinkFields = "fromMemoryPageId toMemoryPageId relation linkStatus fromPagePath toPagePath fromPageName toPageName linkWeight createdAt"

    public static let listMemoryPages = """
        query ListMemoryPages($scopes: [String], $query: String, $shouldIncludeDormant: Boolean, $options: ListOptionsInput) {
          ListMemoryPages(scopes: $scopes, query: $query, shouldIncludeDormant: $shouldIncludeDormant, options: $options) {
            memoryPages { \(memoryPageFields) }
            meta { totalCount }
          }
        }
        """

    public static let getMemoryPage = """
        query GetMemoryPage($memoryPageId: String, $path: String, $scope: String, $siteId: String) {
          GetMemoryPage(memoryPageId: $memoryPageId, path: $path, scope: $scope, siteId: $siteId) {
            \(memoryPageFields) aliases isWritableByReader
            facts { \(memoryFactFields) }
            links { \(memoryLinkFields) }
          }
        }
        """

    public static let searchMemory = """
        query SearchMemory($query: String, $limit: Int64) {
          SearchMemory(query: $query, limit: $limit) {
            memoryPages { \(memoryPageFields) }
            memoryFacts { id number sentence isInferred pagePath pageName memoryScope siteId supersededByFactId dormantAt }
          }
        }
        """

    public static let listMemoryRevisions = """
        query ListMemoryRevisions($memoryPageId: String, $limit: Int64) {
          ListMemoryRevisions(memoryPageId: $memoryPageId, limit: $limit) {
            revisionNumber revisionKind actorKind previousValue newValue changeReason memoryFactId createdAt
          }
        }
        """

    public static let addMemoryFact = """
        mutation AddMemoryFact($path: String, $sentence: String, $scope: String, $siteId: String, $factKind: String) {
          AddMemoryFact(path: $path, sentence: $sentence, scope: $scope, siteId: $siteId, factKind: $factKind) {
            memoryPage { \(memoryPageFields) }
            memoryFact { \(memoryFactFields) }
            isPageCreated isDuplicate
          }
        }
        """

    public static let editMemoryFact = """
        mutation EditMemoryFact($memoryFactId: String, $sentence: String, $factKind: String, $isConfirmed: Boolean, $shouldRestore: Boolean) {
          EditMemoryFact(memoryFactId: $memoryFactId, sentence: $sentence, factKind: $factKind, isConfirmed: $isConfirmed, shouldRestore: $shouldRestore) {
            \(memoryFactFields)
          }
        }
        """

    public static let forgetMemoryFact = """
        mutation ForgetMemoryFact($memoryFactId: String) { ForgetMemoryFact(memoryFactId: $memoryFactId) { memoryFactId memoryPageId number } }
        """

    public static let forgetMemoryPage = """
        mutation ForgetMemoryPage($memoryPageId: String) { ForgetMemoryPage(memoryPageId: $memoryPageId) }
        """

    public static let editMemoryPage = """
        mutation EditMemoryPage($memoryPageId: String, $name: String, $summary: String) {
          EditMemoryPage(memoryPageId: $memoryPageId, name: $name, summary: $summary) { \(memoryPageFields) aliases }
        }
        """

    static var knowledgeDocuments: [String] {
        [
            listMemoryPages, getMemoryPage, searchMemory, listMemoryRevisions, addMemoryFact, editMemoryFact, forgetMemoryFact, forgetMemoryPage,
            editMemoryPage,
        ]
    }
}

extension Connection {
    public func memoryPages(query: String = "", scopes: [String]? = nil, includeDormant: Bool = false, first: Int = 100) async throws -> [MemoryPage] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let memoryPages: [MemoryPage]? }
            let ListMemoryPages: List?
        }
        var variables: [String: JSONValue] = ["shouldIncludeDormant": .bool(includeDormant), "options": .object(["first": .number(Double(first))])]
        if !query.isEmpty { variables["query"] = .string(query) }
        if let scopes { variables["scopes"] = .array(scopes.map { .string($0) }) }
        return try await execute(Documents.listMemoryPages, variables: variables, as: Answer.self).ListMemoryPages?.memoryPages ?? []
    }

    /// A page by id, or by path, preferring the caller's own pool, then site, organization and global.
    public func memoryPage(id: String? = nil, path: String? = nil, scope: String? = nil, siteId: String? = nil) async throws -> MemoryPage {
        struct Answer: Decodable, Sendable { let GetMemoryPage: MemoryPage }
        var variables: [String: JSONValue] = [:]
        if let id { variables["memoryPageId"] = .string(id) }
        if let path { variables["path"] = .string(path) }
        if let scope { variables["scope"] = .string(scope) }
        if let siteId { variables["siteId"] = .string(siteId) }
        return try await execute(Documents.getMemoryPage, variables: variables, as: Answer.self).GetMemoryPage
    }

    public func searchMemory(_ query: String, limit: Int = 30) async throws -> (pages: [MemoryPage], facts: [MemoryFact]) {
        struct Answer: Decodable, Sendable {
            struct Found: Decodable, Sendable {
                let memoryPages: [MemoryPage]?
                let memoryFacts: [MemoryFact]?
            }
            let SearchMemory: Found?
        }
        let found = try await execute(Documents.searchMemory, variables: ["query": .string(query), "limit": .number(Double(limit))], as: Answer.self).SearchMemory
        return (found?.memoryPages ?? [], found?.memoryFacts ?? [])
    }

    public func memoryRevisions(pageId: String, limit: Int = 50) async throws -> [MemoryRevision] {
        struct Answer: Decodable, Sendable { let ListMemoryRevisions: [MemoryRevision]? }
        return try await execute(Documents.listMemoryRevisions, variables: ["memoryPageId": .string(pageId), "limit": .number(Double(limit))], as: Answer.self)
            .ListMemoryRevisions ?? []
    }

    /// Adds a fact to the page at `path`; the page is made when it is new.
    public func addMemoryFact(path: String, sentence: String, scope: String, siteId: String? = nil) async throws {
        var variables: [String: JSONValue] = ["path": .string(path), "sentence": .string(sentence), "scope": .string(scope), "factKind": .string("fact")]
        if let siteId { variables["siteId"] = .string(siteId) }
        _ = try await execute(Documents.addMemoryFact, variables: variables, as: JSONValue.self)
    }

    public func editMemoryFact(id: String, sentence: String) async throws {
        _ = try await execute(Documents.editMemoryFact, variables: ["memoryFactId": .string(id), "sentence": .string(sentence)], as: JSONValue.self)
    }

    /// Deletes a fact for good.
    public func forgetMemoryFact(id: String) async throws {
        _ = try await execute(Documents.forgetMemoryFact, variables: ["memoryFactId": .string(id)], as: JSONValue.self)
    }

    public func forgetMemoryPage(id: String) async throws {
        _ = try await execute(Documents.forgetMemoryPage, variables: ["memoryPageId": .string(id)], as: JSONValue.self)
    }
}

/// MemoryPageGroup is one section of the knowledge list: a whole pool, or for site pages one site.
public struct MemoryPageGroup: Equatable, Sendable, Identifiable {
    /// `user`, `site`, `organization` or `global` (or whatever the server sent).
    public let memoryScope: String
    /// The site's title for a site group, nil for the other pools.
    public let siteTitle: String?
    public let pages: [MemoryPage]

    public var id: String { siteTitle.map { "\(memoryScope):\($0)" } ?? memoryScope }
}

public enum MemoryPageGrouping {
    static let scopeOrder = ["user", "site", "organization", "global"]

    /// The pages as sections in the order About you, one per site (by name), Your organization, Everyone, then any other pool.
    public static func groups(_ pages: [MemoryPage]) -> [MemoryPageGroup] {
        var order: [(scope: String, siteId: String?, siteTitle: String?)] = []
        var members: [String: [MemoryPage]] = [:]
        for page in pages {
            let scope = page.memoryScope ?? ""
            let siteTitle = page.siteTitle
            let key = siteTitle == nil ? scope : "\(scope):\(page.siteId ?? ""):\(siteTitle ?? "")"
            if members[key] == nil { order.append((scope, page.siteId, siteTitle)) }
            members[key, default: []].append(page)
        }
        let sorted = order.sorted { left, right in
            let leftRank = scopeOrder.firstIndex(of: left.scope) ?? 99
            let rightRank = scopeOrder.firstIndex(of: right.scope) ?? 99
            if leftRank != rightRank { return leftRank < rightRank }
            if let leftTitle = left.siteTitle, let rightTitle = right.siteTitle {
                let comparison = leftTitle.localizedCaseInsensitiveCompare(rightTitle)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return (left.siteId ?? "") < (right.siteId ?? "")
            }
            return false
        }
        return sorted.map { entry in
            let key = entry.siteTitle == nil ? entry.scope : "\(entry.scope):\(entry.siteId ?? ""):\(entry.siteTitle ?? "")"
            return MemoryPageGroup(memoryScope: entry.scope, siteTitle: entry.siteTitle, pages: members[key] ?? [])
        }
    }
}
