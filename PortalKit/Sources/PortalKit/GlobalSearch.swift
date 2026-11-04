import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// GlobalSearchResultKind says what a search result is. It is the server's own list, so the Portal web app's palette and the
/// app show the same rows under the same headings.
public enum GlobalSearchResultKind: String, Codable, CaseIterable, Hashable, Sendable {
    case shortcut
    case controller
    case virtualController
    case site
    case cell
    case camera
    case organization
    case person
    case directChat
    case groupChat
    case conversation
    case ticket
    case release
    case page
    case incident
}

/// GlobalSearchResult is one row of a global search: a thing to open, or a shortcut to a screen.
public struct GlobalSearchResult: Codable, Equatable, Hashable, Sendable {
    public let resultKind: GlobalSearchResultKind
    /// The entity's id within its kind, or a shortcut's catalog id. A ticket's id is its number as text.
    public let id: String
    public let title: String
    /// One line of context: a shortcut's section, a ticket's status, a controller's site. Empty when there is none.
    public let subtitle: String
    /// The Portal web path the row opens, such as `/ticket/12`.
    public let path: String
    /// Set for a shortcut only: the name of its symbol in the server's fixed vocabulary.
    public let iconName: String?
    /// Both are set only for a row outside the person's own organization.
    public let organizationId: String?
    public let organizationName: String?

    public init(
        resultKind: GlobalSearchResultKind, id: String, title: String, subtitle: String = "", path: String, iconName: String? = nil,
        organizationId: String? = nil, organizationName: String? = nil
    ) {
        self.resultKind = resultKind
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.iconName = iconName
        self.organizationId = organizationId
        self.organizationName = organizationName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultKind = try container.decode(GlobalSearchResultKind.self, forKey: .resultKind)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        path = try container.decode(String.self, forKey: .path)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        organizationId = try container.decodeIfPresent(String.self, forKey: .organizationId)
        organizationName = try container.decodeIfPresent(String.self, forKey: .organizationName)
    }

    /// What keys a row in a list: two kinds may share an id.
    public var rowKey: String { "\(resultKind.rawValue)|\(id)" }

    /// The organization to show beside the row, when it is not the person's own.
    public var foreignOrganizationName: String? {
        guard let name = organizationName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }

    /// The screen of the app this row opens, or nil when the app has none and the row opens on the web.
    public var link: PortalLink? {
        // A tab of a page: the app's screen for the page would not open on the tab.
        if resultKind == .shortcut, path.contains("?") { return nil }
        return isSubpage ? PortalLink(subpagePath: path) : PortalLink(path: path)
    }

    /// Whether this is a page below an entity: the server writes the entity's id after the page's.
    private var isSubpage: Bool { resultKind == .shortcut && id.contains(":") }
}

/// GlobalSearchGroup is a heading of the results. The two kinds of chat share one.
public enum GlobalSearchGroup: String, CaseIterable, Hashable, Sendable {
    case shortcut
    case controller
    case virtualController
    case site
    case cell
    case camera
    case organization
    case person
    case chat
    case conversation
    case ticket
    case release
    case page
    case incident

    public init(kind: GlobalSearchResultKind) {
        switch kind {
        case .shortcut: self = .shortcut
        case .controller: self = .controller
        case .virtualController: self = .virtualController
        case .site: self = .site
        case .cell: self = .cell
        case .camera: self = .camera
        case .organization: self = .organization
        case .person: self = .person
        case .directChat, .groupChat: self = .chat
        case .conversation: self = .conversation
        case .ticket: self = .ticket
        case .release: self = .release
        case .page: self = .page
        case .incident: self = .incident
        }
    }

    /// The heading, in the words the Portal web app uses.
    public var title: String {
        switch self {
        case .shortcut: "Go to"
        case .controller: "Controllers"
        case .virtualController: "Virtual controllers"
        case .site: "Sites"
        case .cell: "Cells"
        case .camera: "Cameras"
        case .organization: "Organizations"
        case .person: "People"
        case .chat: "Chats"
        case .conversation: "Assistant conversations"
        case .ticket: "Tickets"
        case .release: "Releases"
        case .page: "Pages"
        case .incident: "Incidents"
        }
    }
}

/// GlobalSearchSection is one heading with its rows, in the server's order.
public struct GlobalSearchSection: Equatable, Identifiable, Sendable {
    public let group: GlobalSearchGroup
    public let results: [GlobalSearchResult]
    public var id: GlobalSearchGroup { group }
}

/// GlobalSearchRules holds the rules of the search that do not touch the screen.
public enum GlobalSearchRules {
    /// How many rows one search asks for, as the web palette does.
    public static let resultLimit = 30
    /// A query shorter than this returns suggested shortcuts only.
    public static let minimumQueryLength = 2

    /// The text to send: surrounding spaces and line breaks removed.
    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a query asks for matches in the data, not just the suggested shortcuts.
    public static func isSearching(_ text: String) -> Bool {
        normalized(text).count >= minimumQueryLength
    }

    /// Groups ranked results by heading. Shortcuts come first when any match; the other headings follow in the order their best row
    /// appeared, so the server's ranking decides which group leads. A row keeps the server's order within its group, and a row the
    /// server sent twice is shown once.
    public static func sections(_ results: [GlobalSearchResult]) -> [GlobalSearchSection] {
        var seen = Set<String>()
        var order: [GlobalSearchGroup] = []
        var rows: [GlobalSearchGroup: [GlobalSearchResult]] = [:]
        for result in results where seen.insert(result.rowKey).inserted {
            let group = GlobalSearchGroup(kind: result.resultKind)
            if rows[group] == nil { order.append(group) }
            rows[group, default: []].append(result)
        }
        if let index = order.firstIndex(of: .shortcut), index != 0 {
            order.remove(at: index)
            order.insert(.shortcut, at: 0)
        }
        return order.map { GlobalSearchSection(group: $0, results: rows[$0] ?? []) }
    }
}

/// GlobalSearchFailure sorts what went wrong into what the screen says about it.
public enum GlobalSearchFailure: Equatable, Sendable {
    /// The phone cannot reach the server.
    case offline
    /// The server does not have the search yet.
    case unavailable
    /// Anything else, in the server's or the system's words.
    case other(String)

    public static func classify(_ error: Error) -> GlobalSearchFailure {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .cannotFindHost,
                .cannotConnectToHost, .timedOut, .dnsLookupFailed:
                return .offline
            default:
                break
            }
        }
        if case PortalError.refused(let message) = error, message.contains("Cannot query field") {
            return .unavailable
        }
        return .other((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }
}

/// GlobalSearchRecents remembers the rows a person opened from search, newest first, per account and server.
public struct GlobalSearchRecents: @unchecked Sendable {
    public static let capacity = 5

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(accountKey: String) -> String { "globalSearchRecents|\(accountKey)" }

    /// The remembered rows, newest first. A stored list that cannot be read is empty.
    public func load(accountKey: String) -> [GlobalSearchResult] {
        guard let data = defaults.data(forKey: key(accountKey: accountKey)),
            let rows = try? JSONDecoder().decode([GlobalSearchResult].self, from: data)
        else { return [] }
        return Array(rows.prefix(Self.capacity))
    }

    /// Puts a row at the head of the list, once, and returns the list.
    @discardableResult
    public func remember(_ result: GlobalSearchResult, accountKey: String) -> [GlobalSearchResult] {
        let rows = Self.adding(result, to: load(accountKey: accountKey))
        save(rows, accountKey: accountKey)
        return rows
    }

    public func clear(accountKey: String) {
        defaults.removeObject(forKey: key(accountKey: accountKey))
    }

    private func save(_ rows: [GlobalSearchResult], accountKey: String) {
        if let data = try? JSONEncoder().encode(rows) { defaults.set(data, forKey: key(accountKey: accountKey)) }
    }

    /// The list with the row at its head: an earlier copy of the same row is dropped, and the list keeps `capacity` rows.
    public static func adding(_ result: GlobalSearchResult, to rows: [GlobalSearchResult]) -> [GlobalSearchResult] {
        Array(([result] + rows.filter { $0.rowKey != result.rowKey }).prefix(capacity))
    }
}

extension Documents {
    /// The same query the Portal web app's palette sends.
    public static let globalSearch = """
        query GlobalSearch($query: String!, $limit: Int) {
          GlobalSearch(query: $query, limit: $limit) {
            results { resultKind id title subtitle path iconName organizationId organizationName }
          }
        }
        """

    static var globalSearchDocuments: [String] { [globalSearch, getIncident] }

    public static let getIncident = """
        query GetIncident($incidentId: String) {
          GetIncident(incidentId: $incidentId) {
            incident {
              id title description kind siteId controllerId organizationId reviewStatus activityStatus detectedAt confidence previewAttachmentId
              viewerCapabilities
            }
          }
        }
        """
}

extension ServerCapabilities {
    /// Whether the server answers the global search. A server whose operations could not be read is asked anyway.
    public var offersGlobalSearch: Bool { queryNames.isEmpty || offersQuery("GlobalSearch") }
}

extension Connection {
    /// Searches everywhere the person can see, and the shortcuts to screens. A query under two characters returns suggested
    /// shortcuts. Rows of a kind this app does not know are left out, so a newer server never breaks the list.
    public func globalSearch(query: String, limit: Int = GlobalSearchRules.resultLimit) async throws -> [GlobalSearchResult] {
        struct Answer: Decodable, Sendable {
            struct Page: Decodable, Sendable {
                let results: [Row]?
            }
            struct Row: Decodable, Sendable {
                let value: GlobalSearchResult?
                init(from decoder: Decoder) throws { value = try? GlobalSearchResult(from: decoder) }
            }
            let GlobalSearch: Page?
        }
        let variables: [String: JSONValue] = ["query": .string(GlobalSearchRules.normalized(query)), "limit": .number(Double(limit))]
        let page = try await execute(Documents.globalSearch, variables: variables, as: Answer.self).GlobalSearch
        return (page?.results ?? []).compactMap(\.value)
    }

    /// One incident, for a link that names only its id.
    public func incident(id: String) async throws -> IncidentSummary {
        struct Answer: Decodable, Sendable {
            struct Found: Decodable, Sendable { let incident: IncidentSummary? }
            let GetIncident: Found?
        }
        guard let incident = try await execute(Documents.getIncident, variables: ["incidentId": .string(id)], as: Answer.self).GetIncident?.incident else {
            throw PortalError.refused("Incident not found.")
        }
        return incident
    }
}
