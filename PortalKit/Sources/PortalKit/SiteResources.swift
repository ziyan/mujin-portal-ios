import Foundation

/// SiteOrchestrators is one controller's orchestrators, as the site's orchestrators page lists them.
public struct SiteOrchestrators: Decodable, Equatable, Identifiable, Sendable {
    public struct Snapshot: Decodable, Equatable, Sendable {
        public let observedAt: String?
        public let activeRunModeName: String?
        public let orchestrators: [Orchestrator]?
    }

    public struct Orchestrator: Decodable, Equatable, Identifiable, Sendable {
        public let orchestratorId: String?
        public let orchestratorType: String?
        public let processStatus: String?
        public let runStatus: String?
        public let hasError: Bool?
        public let isProcessingCommand: Bool?
        public let statusMessage: String?
        /// The orchestrator's own verbatim state, from which the line's own status is read.
        public let state: JSONValue?

        public var id: String { orchestratorId ?? orchestratorType ?? "" }

        public init(
            orchestratorId: String? = nil, orchestratorType: String? = nil, processStatus: String? = nil, runStatus: String? = nil, hasError: Bool? = nil,
            isProcessingCommand: Bool? = nil, statusMessage: String? = nil, state: JSONValue? = nil
        ) {
            self.orchestratorId = orchestratorId
            self.orchestratorType = orchestratorType
            self.processStatus = processStatus
            self.runStatus = runStatus
            self.hasError = hasError
            self.isProcessingCommand = isProcessingCommand
            self.statusMessage = statusMessage
            self.state = state
        }

        /// Where each orchestrator type keeps its own status inside the verbatim state, as the web's
        /// `ownStatusPaths` does. A type absent here has no own status.
        static let ownStatusPaths: [String: [String]] = [
            "productioncycle": ["productionCycleStatus"],
            "warehouseexecution": ["warehouseExecutionState", "warehouseExecutionStatus"],
            "fleet": ["fleetManagementState", "fleetManagementStatus"],
        ]

        /// The line's own status (Running, Paused, Stopped and so on), or nil for a type that has none
        /// or a state that does not carry it. This is not `runStatus`, which only says whether the
        /// orchestrator is executing a command right now (Idle, Active or Working).
        public var ownStatus: String? {
            guard let path = Self.ownStatusPaths[orchestratorType ?? ""], var current = state else { return nil }
            if let object = current.objectValue { current = .object(object) }
            for key in path {
                guard let next = current[key] else { return nil }
                current = next
            }
            guard let text = current.stringValue, !text.isEmpty else { return nil }
            return text
        }

        /// The type in words: the known concatenated names split, any other with its underscores turned into spaces.
        public var displayName: String {
            let type = orchestratorType ?? id
            switch type {
            case "productioncycle": return "Production cycle"
            case "warehouseexecution": return "Warehouse execution"
            case "fleet": return "Fleet"
            default: return type.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }

        /// True only when the line itself is running. Paused, Stopping and the other in-between
        /// statuses are not running.
        public var isRunning: Bool { ownStatus == "Running" }

        /// The line is changing or held: Paused, Pausing, Stopping, Starting or Resuming.
        public var isInTransition: Bool { ["Paused", "Pausing", "Stopping", "Starting", "Resuming"].contains(ownStatus ?? "") }
    }

    public let controllerId: String?
    public let isAvailable: Bool?
    public let orchestrators: Snapshot?

    public var id: String { controllerId ?? "" }

    public init(controllerId: String?, isAvailable: Bool? = true, orchestrators: Snapshot? = nil) {
        self.controllerId = controllerId
        self.isAvailable = isAvailable
        self.orchestrators = orchestrators
    }

    public var list: [Orchestrator] { orchestrators?.orchestrators ?? [] }
}

/// SiteOrchestratorSummary is what the site page's row says: how many lines run, and whether any has an error.
/// An orchestrator whose type reports no own status cannot be said to run or not, so it is left out of
/// `totalCount` and counted in `withoutOwnStatusCount` instead.
public struct SiteOrchestratorSummary: Equatable, Sendable {
    public let runningCount: Int
    public let totalCount: Int
    public let withoutOwnStatusCount: Int
    public let hasError: Bool
    public let unreachableControllerCount: Int

    public init(_ rows: [SiteOrchestrators]) {
        let all = rows.flatMap(\.list)
        runningCount = all.filter(\.isRunning).count
        totalCount = all.filter { $0.ownStatus != nil }.count
        withoutOwnStatusCount = all.count - totalCount
        hasError = all.contains { $0.hasError == true }
        unreachableControllerCount = rows.filter { $0.isAvailable == false }.count
    }
}

/// SiteMember is a person of a site's organization who may work at the site.
public struct SiteMember: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let email: String?
    public let hasAvatar: Bool?
    public let modifiedAt: String?

    public init(id: String, name: String? = nil, email: String? = nil, hasAvatar: Bool? = nil, modifiedAt: String? = nil) {
        self.hasAvatar = hasAvatar
        self.modifiedAt = modifiedAt
        self.id = id
        self.name = name
        self.email = email
    }

    public var shownName: String { (name ?? "").isEmpty ? (email ?? id) : name! }
}

public enum SiteMembersAccess {
    /// The members page is shown to a Mujin user, and to an administrator of the site's own organization.
    public static func canSee(isMujinUser: Bool, permissions: [String], viewerOrganizationId: String?, siteOrganizationId: String?) -> Bool {
        if isMujinUser { return true }
        guard let siteOrganizationId, !siteOrganizationId.isEmpty, siteOrganizationId == viewerOrganizationId else { return false }
        return permissions.contains("organization:operate-all") || permissions.contains("platform:administer")
    }
}

extension Documents {
    public static let listSiteOrchestrators = """
        query ListSiteOrchestrators($siteId: String, $cellId: String) {
          ListSiteOrchestrators(siteId: $siteId, cellId: $cellId) {
            controllerId isAvailable
            orchestrators {
              observedAt activeRunModeName
              orchestrators { orchestratorId orchestratorType processStatus runStatus hasError isProcessingCommand statusMessage state }
            }
          }
        }
        """

    public static let listSiteUserIDs = """
        query ListSiteUserIDs($siteId: String) { ListSiteUserIDs(siteId: $siteId) }
        """

    public static let listOrganizationUsers = """
        query ListOrganizationUsers($organizationId: String, $options: ListOptionsInput) {
          ListOrganizationUsers(organizationId: $organizationId, options: $options) { users { id email name hasAvatar modifiedAt } }
        }
        """

    static var siteResourceDocuments: [String] { [listSiteOrchestrators, listSiteUserIDs, listOrganizationUsers, getAlarmDetail] }
}

extension Connection {
    public func siteOrchestrators(siteId: String, cellId: String? = nil) async throws -> [SiteOrchestrators] {
        struct Answer: Decodable, Sendable { let ListSiteOrchestrators: [SiteOrchestrators]? }
        return try await execute(Documents.listSiteOrchestrators, variables: Self.siteScope(siteId: siteId, cellId: cellId), as: Answer.self).ListSiteOrchestrators ?? []
    }

    /// The people of a site: its user ids, named from the site organization's
    /// users and, for a viewer of another organization (Mujin staff), from the
    /// viewer's organization too, as the web does. A member neither list names
    /// is still listed, by id, after the named ones.
    public func siteMembers(siteId: String, organizationId: String, viewerOrganizationId: String? = nil) async throws -> [SiteMember] {
        struct Ids: Decodable, Sendable { let ListSiteUserIDs: [String]? }
        struct Users: Decodable, Sendable {
            struct List: Decodable, Sendable { let users: [SiteMember]? }
            let ListOrganizationUsers: List?
        }
        let ids = try await execute(Documents.listSiteUserIDs, variables: ["siteId": .string(siteId)], as: Ids.self).ListSiteUserIDs ?? []
        guard !ids.isEmpty else { return [] }
        var organizationIds = [organizationId]
        if let viewerOrganizationId, !viewerOrganizationId.isEmpty, viewerOrganizationId != organizationId {
            organizationIds.append(viewerOrganizationId)
        }
        var userById: [String: SiteMember] = [:]
        for listedOrganizationId in organizationIds {
            let users = try await execute(
                Documents.listOrganizationUsers,
                variables: ["organizationId": .string(listedOrganizationId), "options": .object(["first": .number(500)])], as: Users.self
            ).ListOrganizationUsers?.users ?? []
            for user in users { userById[user.id] = user }
        }
        let named = ids.compactMap { userById[$0] }.sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
        let unnamed = ids.filter { userById[$0] == nil }.map { SiteMember(id: $0) }
        return named + unnamed
    }
}
