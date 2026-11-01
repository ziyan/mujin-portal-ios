import Foundation

/// BackupEntry is one backup of a controller's configuration.
public struct BackupEntry: Decodable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let controllerId: String?
    public let label: String?
    public let createdAt: String?
    public let expiresAt: String?
    public let sizeBytes: Int64?
    public let sourceVersion: String?
    public let selection: String?

    public init(
        id: String, controllerId: String? = nil, label: String? = nil, createdAt: String? = nil, expiresAt: String? = nil, sizeBytes: Int64? = nil,
        sourceVersion: String? = nil, selection: String? = nil
    ) {
        self.id = id
        self.controllerId = controllerId
        self.label = label
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.sizeBytes = sizeBytes
        self.sourceVersion = sourceVersion
        self.selection = selection
    }

    public var date: Date? { PortalDate.parse(createdAt) }
    public var shownName: String { (label ?? "").isEmpty ? id : label! }
}

/// ControllerSyncProgress is how far one kind of resource has been copied to Portal from a controller.
public struct ControllerSyncProgress: Decodable, Equatable, Identifiable, Sendable {
    public let resourceType: String?
    public let pushedCount: Int64?
    public let totalCount: Int64?
    public var id: String { resourceType ?? "" }

    public init(resourceType: String?, pushedCount: Int64?, totalCount: Int64?) {
        self.resourceType = resourceType
        self.pushedCount = pushedCount
        self.totalCount = totalCount
    }

    /// Between 0 and 1, or nil when the total is not known.
    public var fraction: Double? {
        guard let total = totalCount, total > 0 else { return nil }
        return min(1, max(0, Double(pushedCount ?? 0) / Double(total)))
    }
}

/// ControllerCapability names the verbs a viewer holds at a controller's site.
public enum ControllerCapability {
    public static let edit = "controller:edit"
    public static let deleteBackup = "backup:delete"
}

extension ControllerSummary {
    /// Editing the comment needs `controller:edit` at the site.
    public var canEdit: Bool { can(ControllerCapability.edit) }
    public var canDeleteBackups: Bool { can(ControllerCapability.deleteBackup) }
}

public enum ControllerMoveAccess {
    /// The server lets a holder of `site:assign` over the controller's organization (an administrator holds it) move a controller,
    /// and only to a site of the same organization. The person's permissions tell whether to offer it.
    public static func canOffer(permissions: [String]) -> Bool {
        permissions.contains("site:assign") || permissions.contains("organization:operate-all") || permissions.contains("platform:administer")
    }

    /// The sites a controller may be moved to: those of its own organization.
    public static func destinations(_ sites: [SiteSummary], controller: ControllerSummary) -> [SiteSummary] {
        sites.filter { $0.organizationId == controller.organizationId && $0.isArchived != true }
    }
}

extension Documents {
    public static let listBackups = """
        query ListBackups($controllerId: String, $options: ListOptionsInput) {
          ListBackups(controllerId: $controllerId, options: $options) { backups { id controllerId label createdAt expiresAt sizeBytes sourceVersion selection } meta { totalCount } }
        }
        """

    public static let deleteBackup = """
        mutation DeleteBackup($controllerId: String, $backupId: String) { DeleteBackup(controllerId: $controllerId, backupId: $backupId) { backupId } }
        """

    public static let getControllerSyncProgress = """
        query GetControllerSyncProgress($controllerId: String) {
          GetControllerSyncProgress(controllerId: $controllerId) { retrievedAt syncState { reportedAt progress { resourceType pushedCount totalCount } } }
        }
        """

    public static let modifyController = """
        mutation ModifyController($controllerId: String, $controller: ControllerInput) {
          ModifyController(controllerId: $controllerId, controller: $controller) { controller { id comment siteId } }
        }
        """

    public static let assignControllersToSite = """
        mutation AssignControllersToSite($controllerIds: [String], $siteId: String) {
          AssignControllersToSite(controllerIds: $controllerIds, siteId: $siteId) { controllerIds siteId }
        }
        """

    static var controllerManagementDocuments: [String] {
        [listBackups, deleteBackup, getControllerSyncProgress, modifyController, assignControllersToSite]
    }
}

extension Connection {
    /// Every backup of a controller, newest first, paged until the total the server reports.
    public func backups(controllerId: String, pageSize: Int = 100) async throws -> [BackupEntry] {
        struct Answer: Decodable, Sendable {
            struct Meta: Decodable, Sendable { let totalCount: Int? }
            struct List: Decodable, Sendable {
                let backups: [BackupEntry]?
                let meta: Meta?
            }
            let ListBackups: List
        }
        var collected: [BackupEntry] = []
        while true {
            let variables: [String: JSONValue] = [
                "controllerId": .string(controllerId),
                "options": .object(["first": .number(Double(pageSize)), "after": .number(Double(collected.count))]),
            ]
            let list = try await execute(Documents.listBackups, variables: variables, as: Answer.self).ListBackups
            let page = list.backups ?? []
            collected += page
            if page.isEmpty { break }
            if let total = list.meta?.totalCount, collected.count >= total { break }
            if page.count < pageSize, list.meta?.totalCount == nil { break }
        }
        return collected.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    public func deleteBackup(controllerId: String, backupId: String) async throws {
        _ = try await execute(Documents.deleteBackup, variables: ["controllerId": .string(controllerId), "backupId": .string(backupId)], as: JSONValue.self)
    }

    /// How far the controller's resources have been copied to Portal, one entry per resource type.
    public func syncProgress(controllerId: String) async throws -> [ControllerSyncProgress] {
        struct Answer: Decodable, Sendable {
            struct Snapshot: Decodable, Sendable {
                struct State: Decodable, Sendable { let progress: [ControllerSyncProgress]? }
                let syncState: State?
            }
            let GetControllerSyncProgress: Snapshot?
        }
        return try await execute(Documents.getControllerSyncProgress, variables: ["controllerId": .string(controllerId)], as: Answer.self)
            .GetControllerSyncProgress?.syncState?.progress ?? []
    }

    public func setControllerComment(id: String, comment: String) async throws {
        _ = try await execute(
            Documents.modifyController, variables: ["controllerId": .string(id), "controller": .object(["comment": .string(comment)])], as: JSONValue.self)
    }

    public func moveController(id: String, toSite siteId: String) async throws {
        _ = try await execute(
            Documents.assignControllersToSite, variables: ["controllerIds": .array([.string(id)]), "siteId": .string(siteId)], as: JSONValue.self)
    }
}

/// ControllerLive narrows what a site reports to one controller.
public enum ControllerLive {
    public static func alarms(_ alarms: [SiteAlarm], controllerId: String) -> [SiteAlarm] {
        alarms.filter { $0.controllerId == controllerId }.sorted { $0.severityRank < $1.severityRank }
    }

    public static func orchestrators(_ rows: [SiteOrchestrators], controllerId: String) -> SiteOrchestrators? {
        rows.first { $0.controllerId == controllerId }
    }

    public static func robots(_ robots: SiteRobots, controllerId: String) -> [SiteRobots.Robot] {
        robots.robots.filter { $0.controllerId == controllerId }
    }

    public static func incidents(_ incidents: [IncidentSummary], controllerId: String) -> [IncidentSummary] {
        incidents.filter { $0.controllerId == controllerId }
    }
}
