import Foundation

/// PlatformAccess decides which platform settings the viewer is offered. It follows the server's rules, as the web does, so no screen
/// shows a control the server refuses: a platform administrator reaches everything, an organization administrator (the
/// `organization:operate-all` permission) reaches their own organization, and a platform verb such as `provider:manage` opens the one
/// area it covers. Billing is offered to administrators of the Mujin organization only, as the web offers it.
public struct PlatformAccess: Equatable, Sendable {
    public let people: PeopleAccess

    public init(permissions: [String], isMujinUser: Bool, viewerOrganizationId: String?) {
        people = PeopleAccess(permissions: permissions, isMujinUser: isMujinUser, viewerOrganizationId: viewerOrganizationId)
    }

    public init(people: PeopleAccess) { self.people = people }

    public var isMujinUser: Bool { people.isMujinUser }
    public var isPlatformAdministrator: Bool { people.isPlatformAdministrator }

    /// An administrator of some organization: a platform administrator, or the administrator of their own.
    public var isOrganizationAdministrator: Bool { people.isPlatformAdministrator || people.permissions.contains("organization:operate-all") }

    /// A platform-scoped verb: the platform administrator holds all of them, anyone else needs the verb itself.
    public func hasPlatformVerb(_ verb: String) -> Bool { people.isPlatformAdministrator || people.permissions.contains(verb) }

    // MARK: an organization

    /// Changing the organization's name.
    public func canEditOrganization(_ organizationId: String?) -> Bool { people.holds("organization:modify", in: organizationId) }

    /// Switching an organization off or on again, which only a platform administrator does.
    public var canSetOrganizationActive: Bool { isPlatformAdministrator }

    /// The audit log: a platform administrator reads every organization's, others read their own when they hold a reading permission.
    public func canReadAudit(of organizationId: String?) -> Bool {
        if isPlatformAdministrator { return true }
        guard people.isOwnOrganization(organizationId) else { return false }
        return ["organization:read-all", "organization:operate-all", "audit:read"].contains { people.permissions.contains($0) }
    }

    /// The audit log of every organization at once.
    public var canReadPlatformAudit: Bool { isPlatformAdministrator }

    /// Billing of one organization.
    public func canViewBilling(of organizationId: String?) -> Bool {
        isMujinUser && isOrganizationAdministrator && (isPlatformAdministrator || people.isOwnOrganization(organizationId))
    }

    public func canManageBilling(of organizationId: String?) -> Bool {
        canViewBilling(of: organizationId) && people.holds("billing:manage", in: organizationId)
    }

    // MARK: the platform

    public var canReadUsage: Bool { hasPlatformVerb("usage:read") }
    public var canSeePlans: Bool { hasPlatformVerb("plan:manage") || hasPlatformVerb("billing:administer") }
    public var canManageProviders: Bool { hasPlatformVerb("provider:manage") }
    public var canManageAgents: Bool { hasPlatformVerb("agent:manage") }
    public var canManageGrants: Bool { canManageProviders || canManageAgents }
    public var canDecideRegistrations: Bool { hasPlatformVerb("organization:create") }

    /// Incident alerts are for administrators, who decide which sites they are told about.
    public var canSeeIncidentAlerts: Bool { isOrganizationAdministrator }

    /// What a Mujin user is offered beyond one organization.
    public var hasPlatformPages: Bool {
        canReadPlatformAudit || canReadUsage || canSeePlans || canManageProviders || canManageAgents || canDecideRegistrations
    }

    /// What a person is offered for their own organization.
    public func hasOrganizationPages(_ organizationId: String?) -> Bool {
        canEditOrganization(organizationId) || canReadAudit(of: organizationId) || canViewBilling(of: organizationId)
    }

    /// Whether Platform settings has anything for the viewer.
    public var hasEntry: Bool { hasPlatformPages || hasOrganizationPages(people.viewerOrganizationId) || canSeeIncidentAlerts }
}

extension Documents {
    public static let getOrganizationProfile = """
        query GetOrganizationProfile($organizationId: String!) {
          GetOrganization(organizationId: $organizationId) { id name isMujin isActive hasLogo modifiedAt }
        }
        """

    public static let modifyOrganization = """
        mutation ModifyOrganization($organizationId: String!, $organization: OrganizationInput!) {
          ModifyOrganization(organizationId: $organizationId, organization: $organization) { organization { id name isActive modifiedAt } }
        }
        """

    public static let setOrganizationActive = """
        mutation SetOrganizationActive($organizationId: String!, $isActive: Boolean!) {
          SetOrganizationActive(organizationId: $organizationId, isActive: $isActive) { organization { id isActive modifiedAt } }
        }
        """

    static var platformAccessDocuments: [String] { [getOrganizationProfile, modifyOrganization, setOrganizationActive] }
}

extension Connection {
    public func organizationProfile(id: String) async throws -> OrganizationSummary? {
        struct Answer: Decodable, Sendable { let GetOrganization: OrganizationSummary? }
        return try await execute(Documents.getOrganizationProfile, variables: ["organizationId": .string(id)], as: Answer.self).GetOrganization
    }

    /// Every organization, the switched-off ones too, for a platform administrator who may switch one back on.
    public func allOrganizations(first: Int = 500) async throws -> [OrganizationSummary] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let organizations: [OrganizationSummary]? }
            let ListOrganizations: List?
        }
        let rows = try await execute(Documents.listOrganizations, variables: ["options": .object(["first": .number(Double(first))])], as: Answer.self)
            .ListOrganizations?.organizations ?? []
        return rows.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
    }

    public func renameOrganization(id: String, name: String) async throws {
        _ = try await execute(
            Documents.modifyOrganization, variables: ["organizationId": .string(id), "organization": .object(["name": .string(name)])], as: JSONValue.self)
    }

    public func setOrganizationActive(id: String, isActive: Bool) async throws {
        _ = try await execute(Documents.setOrganizationActive, variables: ["organizationId": .string(id), "isActive": .bool(isActive)], as: JSONValue.self)
    }
}
