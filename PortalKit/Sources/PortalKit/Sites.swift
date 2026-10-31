import Foundation

/// SiteAlarm is one alarm active on a controller of a site.
public struct SiteAlarm: Equatable, Identifiable, Sendable {
    public let controllerId: String
    public let level: String
    public let message: String
    public let status: String
    public let occurredAt: String?
    public let originLabel: String?

    public var id: String { "\(controllerId)|\(occurredAt ?? "")|\(message)" }
    public var occurredDate: Date? { PortalDate.parse(occurredAt) }

    /// Lower is worse, for sorting the worst first.
    public var severityRank: Int {
        switch level.lowercased() {
        case "critical", "fatal": 0
        case "error", "alarm": 1
        case "warning", "warn": 2
        default: 3
        }
    }
}

/// SiteRobots is the robots of a site, from every controller that answered.
public struct SiteRobots: Equatable, Sendable {
    public struct Robot: Equatable, Identifiable, Sendable {
        public let controllerId: String
        public let name: String
        public let isOnline: Bool
        public let hasError: Bool
        public let errorText: String?
        public let powerLevel: Double?
        public let isCharging: Bool
        public var id: String { "\(controllerId)|\(name)" }
    }

    public var robots: [Robot] = []
    public var unavailableControllerCount = 0

    public init() {}
    public var robotCount: Int { robots.count }
    public var onlineCount: Int { robots.filter(\.isOnline).count }
    public var errorCount: Int { robots.filter(\.hasError).count }
}

public struct ControllerSummary: Codable, Equatable, Hashable, Identifiable, Sendable {
    public struct Connection: Codable, Equatable, Hashable, Sendable { public let id: String? }
    public struct State: Codable, Equatable, Hashable, Sendable {
        public let version: String?
        public let publishedAt: String?
    }
    public let id: String
    public let comment: String?
    public let siteId: String?
    public let organizationId: String?
    public let region: String?
    public let connection: Connection?
    public let hypervisorState: State?

    public init(id: String, comment: String? = nil, siteId: String? = nil, organizationId: String? = nil, region: String? = nil, connection: Connection? = nil, hypervisorState: State? = nil) {
        self.id = id
        self.comment = comment
        self.siteId = siteId
        self.organizationId = organizationId
        self.region = region
        self.connection = connection
        self.hypervisorState = hypervisorState
    }

    /// A controller with a live connection to Portal is online.
    public var isOnline: Bool { !(connection?.id ?? "").isEmpty }
    public var version: String? { hypervisorState?.version }

    /// Where the controller's own web UI is served: `<id>.<the server's host>`.
    public func webURL(server: ServerAddress) -> URL? {
        guard var components = URLComponents(url: server.url, resolvingAgainstBaseURL: false), let host = components.host else { return nil }
        components.host = "\(id).\(host)"
        components.path = "/"
        return components.url
    }
}

public struct IncidentSummary: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let description: String?
    public let kind: String?
    public let siteId: String?
    public let controllerId: String?
    public let organizationId: String?
    /// `new`, `confirmed`, `dismissed` or `resolved`.
    public let reviewStatus: String?
    /// `active` or `cleared`.
    public let activityStatus: String?
    public let detectedAt: String?
    public let confidence: Double?
    public let previewAttachmentId: String?
    public let viewerCapabilities: [String]?

    public init(
        id: String, title: String? = nil, description: String? = nil, kind: String? = nil, siteId: String? = nil, controllerId: String? = nil,
        organizationId: String? = nil, reviewStatus: String? = nil, activityStatus: String? = nil, detectedAt: String? = nil,
        confidence: Double? = nil, previewAttachmentId: String? = nil, viewerCapabilities: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.kind = kind
        self.siteId = siteId
        self.controllerId = controllerId
        self.organizationId = organizationId
        self.reviewStatus = reviewStatus
        self.activityStatus = activityStatus
        self.detectedAt = detectedAt
        self.confidence = confidence
        self.previewAttachmentId = previewAttachmentId
        self.viewerCapabilities = viewerCapabilities
    }

    public var detectedDate: Date? { PortalDate.parse(detectedAt) }
    public var isActive: Bool { activityStatus == "active" }
    public var needsReview: Bool { (reviewStatus ?? "new") == "new" }
}

public struct IncidentEvidence: Codable, Equatable, Identifiable, Sendable {
    public let attachmentId: String
    public let contentType: String?
    public let filename: String?
    public let role: String?
    public var id: String { attachmentId }
    public var isImage: Bool { (contentType ?? "").lowercased().hasPrefix("image/") }

    public init(attachmentId: String, contentType: String? = nil, filename: String? = nil, role: String? = nil) {
        self.attachmentId = attachmentId
        self.contentType = contentType
        self.filename = filename
        self.role = role
    }
}

public enum SiteData {
    /// Alarms from every controller, the worst first, then the most recent.
    public static func alarms(_ rows: [(controllerId: String, alarms: [SiteAlarm])]) -> [SiteAlarm] {
        rows.flatMap(\.alarms).sorted {
            if $0.severityRank != $1.severityRank { return $0.severityRank < $1.severityRank }
            return ($0.occurredDate ?? .distantPast) > ($1.occurredDate ?? .distantPast)
        }
    }

    /// Incidents of one site: the ones that need review and are active first.
    public static func incidents(_ all: [IncidentSummary], siteId: String?) -> [IncidentSummary] {
        all.filter { siteId == nil || $0.siteId == siteId }.sorted {
            if $0.needsReview != $1.needsReview { return $0.needsReview }
            return ($0.detectedDate ?? .distantPast) > ($1.detectedDate ?? .distantPast)
        }
    }
}

extension Documents {
    public static let listSiteAlarms = """
        query ListSiteActiveAlarms($siteId: String) {
          ListSiteActiveAlarms(siteId: $siteId) {
            controllerId isAvailable
            alarms { alarms { alarmLevel alarmMessage alarmStatus occurredAt originLabel } }
          }
        }
        """

    public static let listSiteRobots = """
        query ListSiteMobileRobots($siteId: String) {
          ListSiteMobileRobots(siteId: $siteId) {
            controllerId isAvailable
            mobileRobots { robots { name isOnline hasError error powerLevel isCharging } }
          }
        }
        """

    public static let listControllers = """
        query ListControllers($organizationId: String, $options: ListOptionsInput) {
          ListControllers(organizationId: $organizationId, options: $options) {
            controllers { id comment siteId organizationId region connection { id } hypervisorState { version publishedAt } }
            meta { totalCount }
          }
        }
        """

    public static let listIncidents = """
        query ListIncidents($organizationId: String, $options: ListOptionsInput) {
          ListIncidents(organizationId: $organizationId, options: $options) {
            incidents {
              id title description kind siteId controllerId organizationId reviewStatus activityStatus detectedAt confidence previewAttachmentId
              viewerCapabilities
            }
            meta { totalCount }
          }
        }
        """

    public static let listIncidentEvidence = """
        query ListIncidentEvidence($incidentId: String) {
          ListIncidentEvidence(incidentId: $incidentId) { incidentEvidence { attachmentId contentType filename role } }
        }
        """

    public static let transitionIncident = """
        mutation TransitionIncident($incidentId: String, $reviewStatus: String) {
          TransitionIncident(incidentId: $incidentId, reviewStatus: $reviewStatus) { incident { id reviewStatus } }
        }
        """

    static var siteDocuments: [String] {
        [listSiteAlarms, listSiteRobots, listControllers, listIncidents, listIncidentEvidence, transitionIncident]
    }
}

extension Connection {
    /// Active alarms across a site's controllers, worst first. Controllers
    /// that could not be reached are counted apart.
    public func siteAlarms(siteId: String) async throws -> (alarms: [SiteAlarm], unavailableControllerCount: Int) {
        struct Answer: Decodable, Sendable {
            struct Row: Decodable, Sendable {
                struct Holder: Decodable, Sendable {
                    struct Alarm: Decodable, Sendable {
                        let alarmLevel: String?
                        let alarmMessage: String?
                        let alarmStatus: String?
                        let occurredAt: String?
                        let originLabel: String?
                    }
                    let alarms: [Alarm]?
                }
                let controllerId: String?
                let isAvailable: Bool?
                let alarms: Holder?
            }
            let ListSiteActiveAlarms: [Row]?
        }
        let rows = try await execute(Documents.listSiteAlarms, variables: ["siteId": .string(siteId)], as: Answer.self).ListSiteActiveAlarms ?? []
        let grouped = rows.map { row in
            (
                controllerId: row.controllerId ?? "",
                alarms: (row.alarms?.alarms ?? []).map {
                    SiteAlarm(
                        controllerId: row.controllerId ?? "", level: $0.alarmLevel ?? "", message: $0.alarmMessage ?? "", status: $0.alarmStatus ?? "",
                        occurredAt: $0.occurredAt, originLabel: $0.originLabel)
                }
            )
        }
        return (SiteData.alarms(grouped), rows.filter { $0.isAvailable == false }.count)
    }

    public func siteRobots(siteId: String) async throws -> SiteRobots {
        struct Answer: Decodable, Sendable {
            struct Row: Decodable, Sendable {
                struct Holder: Decodable, Sendable {
                    struct Robot: Decodable, Sendable {
                        let name: String?
                        let isOnline: Bool?
                        let hasError: Bool?
                        let error: String?
                        let powerLevel: Double?
                        let isCharging: Bool?
                    }
                    let robots: [Robot]?
                }
                let controllerId: String?
                let isAvailable: Bool?
                let mobileRobots: Holder?
            }
            let ListSiteMobileRobots: [Row]?
        }
        let rows = try await execute(Documents.listSiteRobots, variables: ["siteId": .string(siteId)], as: Answer.self).ListSiteMobileRobots ?? []
        var result = SiteRobots()
        for row in rows {
            if row.isAvailable == false { result.unavailableControllerCount += 1 }
            for robot in row.mobileRobots?.robots ?? [] {
                result.robots.append(
                    SiteRobots.Robot(
                        controllerId: row.controllerId ?? "", name: robot.name ?? "", isOnline: robot.isOnline ?? false, hasError: robot.hasError ?? false,
                        errorText: robot.error, powerLevel: robot.powerLevel, isCharging: robot.isCharging ?? false))
            }
        }
        result.robots.sort { ($0.hasError ? 0 : 1, $0.name) < ($1.hasError ? 0 : 1, $1.name) }
        return result
    }

    public func controllers(organizationId: String? = nil) async throws -> [ControllerSummary] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let controllers: [ControllerSummary]? }
            let ListControllers: List?
        }
        var variables: [String: JSONValue] = ["options": .object(["first": .number(500)])]
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        let rows = try await execute(Documents.listControllers, variables: variables, as: Answer.self).ListControllers?.controllers ?? []
        return rows.sorted { ($0.comment ?? $0.id).localizedCaseInsensitiveCompare($1.comment ?? $1.id) == .orderedAscending }
    }

    public func incidents(organizationId: String? = nil, first: Int = 100) async throws -> [IncidentSummary] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let incidents: [IncidentSummary]? }
            let ListIncidents: List?
        }
        var variables: [String: JSONValue] = ["options": .object(["first": .number(Double(first))])]
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        return try await execute(Documents.listIncidents, variables: variables, as: Answer.self).ListIncidents?.incidents ?? []
    }

    public func incidentEvidence(incidentId: String) async throws -> [IncidentEvidence] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let incidentEvidence: [IncidentEvidence]? }
            let ListIncidentEvidence: List?
        }
        return try await execute(Documents.listIncidentEvidence, variables: ["incidentId": .string(incidentId)], as: Answer.self)
            .ListIncidentEvidence?.incidentEvidence ?? []
    }

    /// Confirms, dismisses or resolves an incident.
    public func setIncidentReview(id: String, reviewStatus: String) async throws {
        _ = try await execute(
            Documents.transitionIncident, variables: ["incidentId": .string(id), "reviewStatus": .string(reviewStatus)], as: JSONValue.self)
    }
}
