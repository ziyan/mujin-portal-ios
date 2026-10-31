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

        public var id: String { orchestratorId ?? orchestratorType ?? "" }

        public init(
            orchestratorId: String? = nil, orchestratorType: String? = nil, processStatus: String? = nil, runStatus: String? = nil, hasError: Bool? = nil,
            isProcessingCommand: Bool? = nil, statusMessage: String? = nil
        ) {
            self.orchestratorId = orchestratorId
            self.orchestratorType = orchestratorType
            self.processStatus = processStatus
            self.runStatus = runStatus
            self.hasError = hasError
            self.isProcessingCommand = isProcessingCommand
            self.statusMessage = statusMessage
        }

        public var isRunning: Bool { (runStatus ?? "").lowercased().contains("run") }
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

/// SiteOrchestratorSummary is what the site page's row says: how many run, and whether any has an error.
public struct SiteOrchestratorSummary: Equatable, Sendable {
    public let runningCount: Int
    public let totalCount: Int
    public let hasError: Bool
    public let unreachableControllerCount: Int

    public init(_ rows: [SiteOrchestrators]) {
        let all = rows.flatMap(\.list)
        runningCount = all.filter(\.isRunning).count
        totalCount = all.count
        hasError = all.contains { $0.hasError == true }
        unreachableControllerCount = rows.filter { $0.isAvailable == false }.count
    }
}

/// SiteMember is a person of a site's organization who may work at the site.
public struct SiteMember: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let email: String?

    public init(id: String, name: String? = nil, email: String? = nil) {
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
              orchestrators { orchestratorId orchestratorType processStatus runStatus hasError isProcessingCommand statusMessage }
            }
          }
        }
        """

    public static let listSiteUserIDs = """
        query ListSiteUserIDs($siteId: String) { ListSiteUserIDs(siteId: $siteId) }
        """

    public static let listOrganizationUsers = """
        query ListOrganizationUsers($organizationId: String, $options: ListOptionsInput) {
          ListOrganizationUsers(organizationId: $organizationId, options: $options) { users { id email name } }
        }
        """

    static var siteResourceDocuments: [String] { [listSiteOrchestrators, listSiteUserIDs, listOrganizationUsers] }
}

extension Connection {
    public func siteOrchestrators(siteId: String) async throws -> [SiteOrchestrators] {
        struct Answer: Decodable, Sendable { let ListSiteOrchestrators: [SiteOrchestrators]? }
        return try await execute(Documents.listSiteOrchestrators, variables: ["siteId": .string(siteId)], as: Answer.self).ListSiteOrchestrators ?? []
    }

    /// The people of a site: its user ids, named from the organization's users.
    public func siteMembers(siteId: String, organizationId: String) async throws -> [SiteMember] {
        struct Ids: Decodable, Sendable { let ListSiteUserIDs: [String]? }
        struct Users: Decodable, Sendable {
            struct List: Decodable, Sendable { let users: [SiteMember]? }
            let ListOrganizationUsers: List?
        }
        let ids = Set(try await execute(Documents.listSiteUserIDs, variables: ["siteId": .string(siteId)], as: Ids.self).ListSiteUserIDs ?? [])
        guard !ids.isEmpty else { return [] }
        let users = try await execute(
            Documents.listOrganizationUsers, variables: ["organizationId": .string(organizationId), "options": .object(["first": .number(500)])], as: Users.self
        ).ListOrganizationUsers?.users ?? []
        return users.filter { ids.contains($0.id) }.sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
    }
}
