import Foundation

/// AuditFieldChange is one field that an audit event changed, with the words for what it was and what it became.
public struct AuditFieldChange: Equatable, Hashable, Identifiable, Sendable {
    public let field: String
    /// Empty when the field did not exist before.
    public let beforeText: String
    /// Empty when the field no longer exists.
    public let afterText: String
    public var id: String { field }
}

/// AuditEvent is one entry of the audit log: who did what to which resource, and what it changed.
public struct AuditEvent: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: String?
    public let organizationId: String?
    public let actorType: String?
    public let userId: String?
    public let controllerId: String?
    public let systemActor: String?
    public let sourceIp: String?
    public let userAgent: String?
    public let requestId: String?
    public let requestRoute: String?
    public let requestMethod: String?
    public let resourceType: String?
    public let resourceId: String?
    public let action: String?
    public let actorLabel: String?
    public let before: JSONValue?
    public let after: JSONValue?

    public var createdDate: Date? { PortalDate.parse(createdAt) }

    /// Who acted: the label the server resolved, or the kind of actor when it gave none.
    public var actorName: String {
        let label = (actorLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        let kind = (actorType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return kind.isEmpty ? "Unknown" : kind.prefix(1).uppercased() + kind.dropFirst()
    }

    /// "Create", "Update" or "Delete".
    public var actionName: String {
        let text = (action ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Change" : text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The kind of resource in words: "virtual_controller" is "Virtual controller" and "token" is "API token".
    public var resourceKindName: String {
        let sentence = AuditWording.words(resourceType ?? "")
        guard !sentence.isEmpty else { return "Resource" }
        return AuditWording.capitalizingFirst(sentence)
    }

    /// What was done to what, as one sentence in English ("Revoked an API token"). The pieces are for localizing it.
    public var summary: AuditSummary { AuditWording.summary(action: action, resourceType: resourceType) }

    /// The name of the resource when its snapshot holds one, and the end of its id when not.
    public var resourceName: String {
        for payload in [after, before] {
            for key in ["name", "title", "email", "comment"] {
                if let text = payload?[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
            }
        }
        let identifier = resourceId ?? ""
        return identifier.count > 10 ? "…" + identifier.suffix(8) : identifier
    }

    /// The fields that changed, in name order. A create has only what it set, a delete only what it removed.
    public var changes: [AuditFieldChange] { AuditChanges.diff(before: before, after: after) }
}

/// AuditSummary is what an audit entry did, split so a screen can translate each part: a format with one `%@` for the verb, and the
/// noun that fills it, with its article.
public struct AuditSummary: Equatable, Sendable {
    /// "Created %@", "Changed %@", "Deleted %@", "Revoked %@".
    public let verbFormat: String
    /// "a site", "an API token".
    public let noun: String

    public var english: String { verbFormat.replacingOccurrences(of: "%@", with: noun) }
}

public enum AuditWording {
    /// Words that are written in capitals.
    static let acronyms: Set<String> = ["api", "ssh", "vpn", "id", "ai", "url", "oidc", "sso", "ip", "mfa", "wms", "wes", "nvr", "pdf", "sql"]
    /// Acronyms that start with a vowel sound when said out loud, and so take "an".
    static let vowelSoundAcronyms: Set<String> = ["api", "ssh", "id", "ai", "sso", "ip", "mfa", "nvr", "sql"]

    /// The nouns of the resource kinds Portal writes to the log, each with its article.
    static let nouns: [String: String] = [
        "organization": "an organization", "organization_registration": "a registration", "domain": "a domain", "user": "a person", "token": "an API token",
        "session": "a session", "controller": "a controller", "virtual_controller": "a virtual controller", "virtual_controller_snapshot": "a snapshot",
        "backup": "a backup", "wireguard_peer": "a VPN device", "sshkey": "an SSH key", "passkey": "a passkey", "site": "a site", "cell": "a cell",
        "ticket": "a ticket", "ticket_comment": "a ticket comment", "attachment": "an attachment", "camera": "a camera", "incident": "an incident",
        "incident_subscription": "an incident alert", "page": "a page", "role": "a role", "group": "a group", "group_site": "a site of a group",
        "group_role": "a role of a group", "user_group": "a group membership", "provider": "an AI provider", "agent": "an AI agent",
        "organization_provider": "an AI provider grant", "organization_agent": "an AI agent grant", "conversation": "a conversation", "chat": "a chat",
        "job": "an automation", "release": "a release", "email_template": "an email template", "favorite": "a favorite", "memory_page": "a memory page",
    ]

    /// Deletes that are better said another way.
    static let removalVerbs: [String: String] = [
        "token": "Revoked %@", "sshkey": "Revoked %@", "wireguard_peer": "Revoked %@", "session": "Ended %@", "passkey": "Removed %@",
    ]

    /// "virtual_controller" is "virtual controller", "sshkey" is "SSH key" and "token" is "API token".
    public static func words(_ resourceType: String) -> String {
        let special = ["token": "API token", "sshkey": "SSH key", "wireguard_peer": "VPN device"]
        if let found = special[resourceType] { return found }
        return resourceType.split(separator: "_").map { acronyms.contains($0.lowercased()) ? $0.uppercased() : String($0) }.joined(separator: " ")
    }

    static func capitalizingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// "a ticket comment" for a kind that is known, and for one that is not, its words with the right article: "a foo bar".
    public static func noun(for resourceType: String?) -> String {
        let kind = resourceType ?? ""
        if let known = nouns[kind] { return known }
        let text = words(kind)
        guard let first = text.split(separator: " ").first.map(String.init), !text.isEmpty else { return "a resource" }
        let isAcronym = acronyms.contains(first.lowercased())
        let takesAn = isAcronym ? vowelSoundAcronyms.contains(first.lowercased()) : "aeiou".contains(first.lowercased().first ?? "x")
        return (takesAn ? "an " : "a ") + text
    }

    public static func summary(action: String?, resourceType: String?) -> AuditSummary {
        let kind = resourceType ?? ""
        let verb: String
        switch action ?? "" {
        case "create": verb = "Created %@"
        case "delete": verb = removalVerbs[kind] ?? "Deleted %@"
        default: verb = "Changed %@"
        }
        return AuditSummary(verbFormat: verb, noun: noun(for: resourceType))
    }
}

public enum AuditChanges {
    /// Bookkeeping that changes on every write, which says nothing about what the change meant.
    static let noiseFields: Set<String> = ["createdAt", "modifiedAt"]

    public static func text(_ value: JSONValue?) -> String {
        switch value {
        case nil, .some(.null): return ""
        case .some(.string(let string)): return string
        case .some(.bool(let bool)): return bool ? "true" : "false"
        case .some(.number(let number)): return number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        case .some(let other):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(other)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    public static func diff(before: JSONValue?, after: JSONValue?) -> [AuditFieldChange] {
        func fields(_ value: JSONValue?) -> [String: JSONValue] {
            if case .object(let object)? = value { return object }
            return [:]
        }
        let beforeFields = fields(before)
        let afterFields = fields(after)
        var changes: [AuditFieldChange] = []
        for key in Set(beforeFields.keys).union(afterFields.keys).sorted() where !noiseFields.contains(key) {
            let beforeText = text(beforeFields[key])
            let afterText = text(afterFields[key])
            if beforeText != afterText { changes.append(AuditFieldChange(field: key, beforeText: beforeText, afterText: afterText)) }
        }
        return changes
    }
}

/// AuditRange is how far back the log is read.
public enum AuditRange: String, CaseIterable, Equatable, Hashable, Sendable {
    case lastDay
    case lastWeek
    case lastMonth
    case anyTime

    public func since(now: Date = Date()) -> Date? {
        switch self {
        case .lastDay: return now.addingTimeInterval(-86_400)
        case .lastWeek: return now.addingTimeInterval(-7 * 86_400)
        case .lastMonth: return now.addingTimeInterval(-30 * 86_400)
        case .anyTime: return nil
        }
    }
}

/// AuditFilter narrows the audit log. The server filters; nothing here reads the whole log.
public struct AuditFilter: Equatable, Sendable {
    /// `create`, `update` and `delete`; none means all.
    public var actions: Set<String> = []
    public var range = AuditRange.anyTime
    /// Matched against the address, the request and the resource.
    public var searchText = ""

    public static let actionNames = ["create", "update", "delete"]

    public init(actions: Set<String> = [], range: AuditRange = .anyTime, searchText: String = "") {
        self.actions = actions
        self.range = range
        self.searchText = searchText
    }

    public var isFiltering: Bool { !actions.isEmpty || range != .anyTime || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The aggregation stages the list takes: the filters, then newest first.
    public func aggregations(now: Date = Date()) -> JSONValue {
        func condition(_ operation: String, _ field: String, _ value: JSONValue) -> JSONValue {
            .object(["operation": .string(operation), "field": .array([.string(field)]), "value": value])
        }
        var operands: [JSONValue] = []
        if let since = range.since(now: now) {
            operands.append(condition("greaterEqual", "createdAt", .string(ISO8601DateFormatter().string(from: since))))
        }
        if !actions.isEmpty {
            operands.append(condition("in", "action", .array(actions.sorted().map { .string($0) })))
        }
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let matches = ["sourceIp", "requestId", "resourceId"].map { condition("insensitiveContains", $0, .string(text)) }
            operands.append(.object(["operation": .string("or"), "operands": .array(matches)]))
        }
        var stages: [JSONValue] = []
        if operands.count == 1 {
            stages.append(.object(["filter": operands[0]]))
        } else if operands.count > 1 {
            stages.append(.object(["filter": .object(["operation": .string("and"), "operands": .array(operands)])]))
        }
        stages.append(.object(["sort": .array([.object(["field": .array([.string("createdAt")]), "isDescending": .bool(true)])])]))
        return .array(stages)
    }
}

/// AuditPage is one page of the log and how many entries match in all.
public struct AuditPage: Equatable, Sendable {
    public let events: [AuditEvent]
    public let totalCount: Int
}

extension Documents {
    public static let listAuditEvents = """
        query ListAuditEvents($organizationId: String, $options: ListOptionsInput) {
          ListAuditEvents(organizationId: $organizationId, options: $options) {
            events {
              id createdAt organizationId actorType userId controllerId systemActor sourceIp userAgent requestId requestRoute requestMethod
              resourceType resourceId action actorLabel before after
            }
            meta { totalCount }
          }
        }
        """

    static var auditDocuments: [String] { [listAuditEvents] }
}

extension Connection {
    public static let auditPageSize = 50

    /// A page of the audit log, newest first. `organizationId` is nil for every organization's, which only a platform administrator may read.
    public func auditEvents(organizationId: String?, filter: AuditFilter, offset: Int = 0, now: Date = Date()) async throws -> AuditPage {
        struct Answer: Decodable, Sendable {
            struct Meta: Decodable, Sendable { let totalCount: Int? }
            struct List: Decodable, Sendable {
                let events: [AuditEvent?]?
                let meta: Meta?
            }
            let ListAuditEvents: List?
        }
        var variables: [String: JSONValue] = [
            "options": .object(["first": .number(Double(Self.auditPageSize)), "after": .number(Double(offset)), "aggregations": filter.aggregations(now: now)])
        ]
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        let list = try await execute(Documents.listAuditEvents, variables: variables, as: Answer.self).ListAuditEvents
        let events = (list?.events ?? []).compactMap { $0 }
        return AuditPage(events: events, totalCount: list?.meta?.totalCount ?? events.count)
    }
}
