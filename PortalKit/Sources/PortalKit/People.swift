import Foundation

/// OrganizationMember is one row of an organization's member list.
public struct OrganizationMember: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let email: String?
    public let name: String?
    public let isActive: Bool?
    public let hasAvatar: Bool?
    public let modifiedAt: String?

    public init(id: String, email: String? = nil, name: String? = nil, isActive: Bool? = nil, hasAvatar: Bool? = nil, modifiedAt: String? = nil) {
        self.id = id
        self.email = email
        self.name = name
        self.isActive = isActive
        self.hasAvatar = hasAvatar
        self.modifiedAt = modifiedAt
    }

    /// The name, or the address of a person who gave none.
    public var shownName: String { (name ?? "").isEmpty ? (email ?? id) : name! }
    /// A member is active unless the server says otherwise.
    public var isDeactivated: Bool { isActive == false }
}

/// UserProfile is one person as their own page shows them.
public struct UserProfile: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let email: String?
    public let name: String?
    public let timezone: String?
    public let locale: String?
    public let jobRole: String?
    /// Only the person themselves is told their responsibilities.
    public let jobActivities: [String]?
    public let organizationId: String?
    public let isActive: Bool?
    public let createdAt: String?
    public let loggedInAt: String?
    public let hasAvatar: Bool?
    public let modifiedAt: String?

    public var shownName: String { (name ?? "").isEmpty ? (email ?? id) : name! }
    public var isDeactivated: Bool { isActive == false }
}

/// AccessGroup is a group of people in an organization. Access to sites comes from the sites and roles of the groups a person is in.
public struct AccessGroup: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let organizationId: String?
    public let name: String?
    public let description: String?
    public let oidcGroupName: String?
    public let oidcRoleName: String?
    public let isDefault: Bool?
    public let siteIds: [String]?
    /// The ids of the roles the group's members hold at each of its sites.
    public let roles: [String]?
    public let createdAt: String?
    public let modifiedAt: String?

    public var shownName: String { (name ?? "").isEmpty ? id : name! }
    public var siteCount: Int { siteIds?.count ?? 0 }
    public var roleCount: Int { roles?.count ?? 0 }
}

/// AccessRole is a named set of permissions that groups hand to their members.
public struct AccessRole: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let organizationId: String?
    public let name: String?
    public let description: String?
    public let permissions: [String]?
    public let createdAt: String?
    public let modifiedAt: String?
    public let deletedAt: String?

    public var shownName: String { (name ?? "").isEmpty ? id : name! }
    public var permissionCount: Int { permissions?.count ?? 0 }
}

/// SiteRoleAssignment says a person holds a role at a site, through a group.
public struct SiteRoleAssignment: Codable, Equatable, Hashable, Sendable {
    public let userId: String?
    public let siteId: String?
    public let roleId: String?
}

/// UserSiteRoles is the roles one person holds at one site.
public struct UserSiteRoles: Equatable, Identifiable, Sendable {
    public let siteId: String
    public let siteName: String
    public let roleNames: [String]
    public var id: String { siteId }
}

public enum UserSites {
    /// One entry per site, sorted by site name, each with the names of the roles held there. A site with no role listed has an empty list;
    /// a role whose name is unknown is left out of the names.
    public static func roles(sites: [SiteSummary], assignments: [SiteRoleAssignment], roleNames: [String: String]) -> [UserSiteRoles] {
        var roleIdsBySite: [String: [String]] = [:]
        for assignment in assignments {
            guard let siteId = assignment.siteId, let roleId = assignment.roleId, !siteId.isEmpty, !roleId.isEmpty else { continue }
            if roleIdsBySite[siteId, default: []].contains(roleId) { continue }
            roleIdsBySite[siteId, default: []].append(roleId)
        }
        return sites.filter { $0.isArchived != true }
            .sorted { ($0.name ?? $0.id).localizedCaseInsensitiveCompare($1.name ?? $1.id) == .orderedAscending }
            .map { site in
                let names = (roleIdsBySite[site.id] ?? []).compactMap { roleNames[$0] }.filter { !$0.isEmpty }.sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
                return UserSiteRoles(siteId: site.id, siteName: site.name ?? site.id, roleNames: names)
            }
    }
}

public enum MemberDirectory {
    /// Members sorted by name. A search matches the name or the address. Deactivated members are left out unless asked for.
    public static func filter(_ members: [OrganizationMember], query: String = "", includesDeactivated: Bool = false) -> [OrganizationMember] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return members.filter { includesDeactivated || !$0.isDeactivated }
            .filter { text.isEmpty || $0.shownName.localizedCaseInsensitiveContains(text) || ($0.email ?? "").localizedCaseInsensitiveContains(text) }
            .sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
    }

    public static func deactivatedCount(_ members: [OrganizationMember]) -> Int { members.filter(\.isDeactivated).count }
}

/// SelectionChanges is what saving a changed selection has to do.
public struct SelectionChanges: Equatable, Sendable {
    public let added: [String]
    public let removed: [String]
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty }

    /// What to add and what to remove to get from `current` to `wanted`, each sorted so the calls are made in a steady order.
    public init(current: Set<String>, wanted: Set<String>) {
        added = wanted.subtracting(current).sorted()
        removed = current.subtracting(wanted).sorted()
    }
}

/// PeopleAccess decides what the viewer may see and do among the people of an organization. It follows the server's rules, so no
/// screen offers something that will be refused: a platform administrator reaches every organization, an organization
/// administrator (the `organization:operate-all` permission) reaches their own, and any other organization permission counts in the
/// viewer's own organization only.
public struct PeopleAccess: Equatable, Sendable {
    public let permissions: Set<String>
    public let isMujinUser: Bool
    public let viewerOrganizationId: String?

    public init(permissions: [String], isMujinUser: Bool, viewerOrganizationId: String?) {
        self.permissions = Set(permissions)
        self.isMujinUser = isMujinUser
        self.viewerOrganizationId = viewerOrganizationId
    }

    public var isPlatformAdministrator: Bool { permissions.contains("platform:administer") }

    public func isOwnOrganization(_ organizationId: String?) -> Bool {
        guard let organizationId, !organizationId.isEmpty else { return false }
        return organizationId == viewerOrganizationId
    }

    /// An administrator of the organization: a platform administrator, or the organization's own administrator.
    public func isAdministrator(of organizationId: String?) -> Bool {
        isPlatformAdministrator || (isOwnOrganization(organizationId) && permissions.contains("organization:operate-all"))
    }

    /// Whether the viewer holds an organization permission over the organization.
    public func holds(_ permission: String, in organizationId: String?) -> Bool {
        isAdministrator(of: organizationId) || (isOwnOrganization(organizationId) && permissions.contains(permission))
    }

    /// The member list: any member of the organization reads it, and Mujin users read every organization's.
    public func canSeeMembers(in organizationId: String?) -> Bool { isMujinUser || isOwnOrganization(organizationId) }

    /// Adding a person to the organization, and the rest of user management.
    public func canManageUsers(in organizationId: String?) -> Bool { holds("user:manage", in: organizationId) && canSeeMembers(in: organizationId) }

    public func canDeactivateUsers(in organizationId: String?) -> Bool { holds("user:deactivate", in: organizationId) && canSeeMembers(in: organizationId) }

    /// The server lists groups for an administrator only, so a person who may edit groups but is not one cannot open the list.
    public func canSeeGroups(in organizationId: String?) -> Bool { isAdministrator(of: organizationId) }

    public func canEditGroups(in organizationId: String?) -> Bool { canSeeGroups(in: organizationId) && holds("group:manage", in: organizationId) }

    /// The server lists the roles of the viewer's own organization to anyone in it, and of any organization to a platform administrator.
    public func canSeeRoles(in organizationId: String?) -> Bool { isPlatformAdministrator || isOwnOrganization(organizationId) }

    public func canEditRoles(in organizationId: String?) -> Bool { canSeeRoles(in: organizationId) && holds("role:manage", in: organizationId) }

    /// The roles screen is offered to those who can change roles; for everyone else it would only be a list.
    public func canOpenRoles(in organizationId: String?) -> Bool { canEditRoles(in: organizationId) }

    /// Whether the People screens have anything for the viewer in that organization.
    public func hasPeopleScreens(in organizationId: String?) -> Bool {
        canSeeMembers(in: organizationId)
            && (canManageUsers(in: organizationId) || canDeactivateUsers(in: organizationId) || canSeeGroups(in: organizationId)
                || canOpenRoles(in: organizationId))
    }

    /// Whether More shows People at all: Mujin users choose an organization, anyone else needs something to do in their own.
    public var hasPeopleEntry: Bool { hasPeopleScreens(in: viewerOrganizationId) || (isMujinUser && (isPlatformAdministrator || hasAnyPeoplePermission)) }

    private var hasAnyPeoplePermission: Bool {
        !permissions.isDisjoint(with: ["organization:operate-all", "user:manage", "user:deactivate", "group:manage", "group:members", "role:manage"])
    }
}

/// PermissionGroup is the permissions of one kind of thing, such as everything about tickets.
public struct PermissionGroup: Equatable, Identifiable, Sendable {
    /// The part of the key before the colon, such as `virtual_controller`.
    public let resource: String
    public let permissions: [String]
    public var id: String { resource }

    /// "Virtual controller" for `virtual_controller`.
    public var title: String {
        let words = resource.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// How many of the group's permissions the set holds.
    public func selectedCount(in selected: Set<String>) -> Int { permissions.filter { selected.contains($0) }.count }
}

public enum PermissionCatalog {
    /// The permissions grouped by what they are about, groups and the permissions in them sorted by name. A key with no colon is a group of its own.
    public static func grouped(_ catalog: [String]) -> [PermissionGroup] {
        var keysByResource: [String: [String]] = [:]
        for key in Set(catalog) where !key.isEmpty {
            let resource = key.split(separator: ":", maxSplits: 1).first.map(String.init) ?? key
            keysByResource[resource, default: []].append(key)
        }
        return keysByResource.map { PermissionGroup(resource: $0.key, permissions: $0.value.sorted()) }
            .sorted { $0.resource.localizedCaseInsensitiveCompare($1.resource) == .orderedAscending }
    }

    /// The set with one permission switched on or off, as the list the server stores: sorted, without duplicates.
    public static func setting(_ permission: String, isOn: Bool, in held: [String]) -> [String] {
        var next = Set(held)
        if isOn { next.insert(permission) } else { next.remove(permission) }
        return next.sorted()
    }
}

extension Documents {
    static let accessGroupFields = "id organizationId name description oidcGroupName oidcRoleName isDefault siteIds roles createdAt modifiedAt"
    static let accessRoleFields = "id organizationId name description permissions createdAt modifiedAt deletedAt"

    public static let listOrganizationMembers = """
        query ListOrganizationUsers($organizationId: String, $options: ListOptionsInput) {
          ListOrganizationUsers(organizationId: $organizationId, options: $options) {
            users { id email name isActive hasAvatar modifiedAt }
            meta { totalCount }
          }
        }
        """

    public static let getUserProfile = """
        query GetUser($userId: String) {
          GetUser(userId: $userId) { id email name timezone locale jobRole jobActivities organizationId isActive createdAt loggedInAt hasAvatar modifiedAt }
        }
        """

    public static let listUserSites = """
        query ListUserSites($userId: String) { ListUserSites(userId: $userId) { id name organizationId isArchived } }
        """

    public static let listSiteRoleAssignments = """
        query ListSiteRoleAssignments($siteId: String, $userId: String) {
          ListSiteRoleAssignments(siteId: $siteId, userId: $userId) { userId siteId roleId }
        }
        """

    public static let listUserGroups = """
        query ListUserGroups($userId: String!) { ListUserGroups(userId: $userId) { \(accessGroupFields) } }
        """

    public static let setUserActive = """
        mutation SetUserActive($userId: String!, $isActive: Boolean!) {
          SetUserActive(userId: $userId, isActive: $isActive) { user { id isActive modifiedAt } }
        }
        """

    public static let listGroups = """
        query ListGroups($organizationId: String, $options: ListOptionsInput) {
          ListGroups(organizationId: $organizationId, options: $options) {
            groups { \(accessGroupFields) }
            meta { totalCount }
          }
        }
        """

    public static let getGroup = """
        query GetGroup($groupId: String!) { GetGroup(groupId: $groupId) { \(accessGroupFields) } }
        """

    public static let listGroupUserIDs = """
        query ListGroupUserIDs($groupId: String!) { ListGroupUserIDs(groupId: $groupId) }
        """

    public static let createGroup = """
        mutation CreateGroup($organizationId: String, $name: String!, $description: String!, $oidcGroupName: String!, $oidcRoleName: String!) {
          CreateGroup(organizationId: $organizationId, name: $name, description: $description, oidcGroupName: $oidcGroupName, oidcRoleName: $oidcRoleName) {
            group { id organizationId name description }
          }
        }
        """

    public static let modifyGroup = """
        mutation ModifyGroup($groupId: String!, $name: String, $description: String) {
          ModifyGroup(groupId: $groupId, name: $name, description: $description) { group { id name description modifiedAt } }
        }
        """

    public static let deleteGroup = """
        mutation DeleteGroup($groupId: String!) { DeleteGroup(groupId: $groupId) { groupId } }
        """

    public static let setDefaultGroup = """
        mutation SetDefaultGroup($groupId: String!) { SetDefaultGroup(groupId: $groupId) { group { id isDefault modifiedAt } } }
        """

    public static let assignSiteToGroup = """
        mutation AssignSiteToGroup($groupId: String!, $siteId: String!) { AssignSiteToGroup(groupId: $groupId, siteId: $siteId) { group { id siteIds roles } } }
        """

    public static let removeSiteFromGroup = """
        mutation RemoveSiteFromGroup($groupId: String!, $siteId: String!) {
          RemoveSiteFromGroup(groupId: $groupId, siteId: $siteId) { group { id siteIds roles } }
        }
        """

    public static let setGroupRoles = """
        mutation SetGroupRoles($groupId: String!, $roleIds: [String!]!) { SetGroupRoles(groupId: $groupId, roleIds: $roleIds) { group { id roles } } }
        """

    public static let assignUsersToGroup = """
        mutation AssignUsersToGroup($groupId: String!, $userIds: [String!]!) { AssignUsersToGroup(groupId: $groupId, userIds: $userIds) { groupId userIds } }
        """

    public static let removeUsersFromGroup = """
        mutation RemoveUsersFromGroup($groupId: String!, $userIds: [String!]!) {
          RemoveUsersFromGroup(groupId: $groupId, userIds: $userIds) { groupId userIds }
        }
        """

    public static let listRoles = """
        query ListRoles($organizationId: String, $options: ListOptionsInput) {
          ListRoles(organizationId: $organizationId, options: $options) {
            roles { \(accessRoleFields) }
            meta { totalCount }
          }
        }
        """

    public static let getRole = """
        query GetRole($roleId: String!) { GetRole(roleId: $roleId) { \(accessRoleFields) } }
        """

    public static let listPermissionCatalog = """
        query ListPermissionCatalog($organizationId: String) { ListPermissionCatalog(organizationId: $organizationId) }
        """

    public static let createRole = """
        mutation CreateRole($organizationId: String, $name: String!, $description: String!) {
          CreateRole(organizationId: $organizationId, name: $name, description: $description) { role { id organizationId name description permissions } }
        }
        """

    public static let modifyRole = """
        mutation ModifyRole($roleId: String!, $name: String, $description: String) {
          ModifyRole(roleId: $roleId, name: $name, description: $description) { role { id name description permissions } }
        }
        """

    public static let deleteRole = """
        mutation DeleteRole($roleId: String!) { DeleteRole(roleId: $roleId) { roleId } }
        """

    public static let setRolePermissions = """
        mutation SetRolePermissions($roleId: String!, $permissions: [String!]!) { SetRolePermissions(roleId: $roleId, permissions: $permissions) { role { id permissions } } }
        """

    static var peopleDocuments: [String] {
        [
            listOrganizationMembers, getUserProfile, listUserSites, listSiteRoleAssignments, listUserGroups, setUserActive, listGroups, getGroup,
            listGroupUserIDs, createGroup, modifyGroup, deleteGroup, setDefaultGroup, assignSiteToGroup, removeSiteFromGroup, setGroupRoles,
            assignUsersToGroup, removeUsersFromGroup, listRoles, getRole, listPermissionCatalog, createRole, modifyRole, deleteRole, setRolePermissions,
        ]
    }
}

extension Connection {
    /// Every member of an organization, page after page.
    public func organizationMembers(organizationId: String, pageSize: Int = 200) async throws -> [OrganizationMember] {
        struct Answer: Decodable, Sendable {
            struct Meta: Decodable, Sendable { let totalCount: Int? }
            struct List: Decodable, Sendable {
                let users: [OrganizationMember]?
                let meta: Meta?
            }
            let ListOrganizationUsers: List?
        }
        var collected: [OrganizationMember] = []
        while true {
            let variables: [String: JSONValue] = [
                "organizationId": .string(organizationId),
                "options": .object(["first": .number(Double(pageSize)), "after": .number(Double(collected.count))]),
            ]
            let list = try await execute(Documents.listOrganizationMembers, variables: variables, as: Answer.self).ListOrganizationUsers
            let page = list?.users ?? []
            collected += page
            if page.isEmpty { break }
            if let total = list?.meta?.totalCount, collected.count >= total { break }
            if page.count < pageSize, list?.meta?.totalCount == nil { break }
        }
        return collected
    }

    public func userProfile(id: String) async throws -> UserProfile {
        struct Answer: Decodable, Sendable { let GetUser: UserProfile? }
        guard let profile = try await execute(Documents.getUserProfile, variables: ["userId": .string(id)], as: Answer.self).GetUser else {
            throw PortalError.refused("That person was not found.")
        }
        return profile
    }

    public func userSites(userId: String) async throws -> [SiteSummary] {
        struct Answer: Decodable, Sendable { let ListUserSites: [SiteSummary]? }
        return try await execute(Documents.listUserSites, variables: ["userId": .string(userId)], as: Answer.self).ListUserSites ?? []
    }

    public func siteRoleAssignments(userId: String) async throws -> [SiteRoleAssignment] {
        struct Answer: Decodable, Sendable { let ListSiteRoleAssignments: [SiteRoleAssignment]? }
        return try await execute(Documents.listSiteRoleAssignments, variables: ["userId": .string(userId)], as: Answer.self).ListSiteRoleAssignments ?? []
    }

    public func userGroups(userId: String) async throws -> [AccessGroup] {
        struct Answer: Decodable, Sendable { let ListUserGroups: [AccessGroup]? }
        return try await execute(Documents.listUserGroups, variables: ["userId": .string(userId)], as: Answer.self).ListUserGroups ?? []
    }

    public func setUserActive(id: String, isActive: Bool) async throws {
        _ = try await execute(Documents.setUserActive, variables: ["userId": .string(id), "isActive": .bool(isActive)], as: JSONValue.self)
    }

    /// The groups of an organization, sorted by name with the default group first.
    public func groups(organizationId: String) async throws -> [AccessGroup] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let groups: [AccessGroup]? }
            let ListGroups: List?
        }
        let variables: [String: JSONValue] = ["organizationId": .string(organizationId), "options": .object(["first": .number(200)])]
        let rows = try await execute(Documents.listGroups, variables: variables, as: Answer.self).ListGroups?.groups ?? []
        return Self.orderedGroups(rows)
    }

    static func orderedGroups(_ groups: [AccessGroup]) -> [AccessGroup] {
        groups.sorted {
            if ($0.isDefault == true) != ($1.isDefault == true) { return $0.isDefault == true }
            return $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending
        }
    }

    public func group(id: String) async throws -> AccessGroup {
        struct Answer: Decodable, Sendable { let GetGroup: AccessGroup? }
        guard let group = try await execute(Documents.getGroup, variables: ["groupId": .string(id)], as: Answer.self).GetGroup else {
            throw PortalError.refused("That group was not found.")
        }
        return group
    }

    public func groupUserIds(groupId: String) async throws -> [String] {
        struct Answer: Decodable, Sendable { let ListGroupUserIDs: [String]? }
        return try await execute(Documents.listGroupUserIDs, variables: ["groupId": .string(groupId)], as: Answer.self).ListGroupUserIDs ?? []
    }

    /// Makes a group and returns its id. The sign-in provider mapping fields are for the web; the app sends them empty.
    public func createGroup(organizationId: String, name: String, description: String) async throws -> String {
        struct Answer: Decodable, Sendable {
            struct Created: Decodable, Sendable {
                struct Row: Decodable, Sendable { let id: String }
                let group: Row
            }
            let CreateGroup: Created
        }
        let variables: [String: JSONValue] = [
            "organizationId": .string(organizationId), "name": .string(name), "description": .string(description), "oidcGroupName": .string(""),
            "oidcRoleName": .string(""),
        ]
        return try await execute(Documents.createGroup, variables: variables, as: Answer.self).CreateGroup.group.id
    }

    public func modifyGroup(id: String, name: String, description: String) async throws {
        _ = try await execute(
            Documents.modifyGroup, variables: ["groupId": .string(id), "name": .string(name), "description": .string(description)], as: JSONValue.self)
    }

    public func deleteGroup(id: String) async throws {
        _ = try await execute(Documents.deleteGroup, variables: ["groupId": .string(id)], as: JSONValue.self)
    }

    public func setDefaultGroup(id: String) async throws {
        _ = try await execute(Documents.setDefaultGroup, variables: ["groupId": .string(id)], as: JSONValue.self)
    }

    public func assignSite(_ siteId: String, toGroup groupId: String) async throws {
        _ = try await execute(Documents.assignSiteToGroup, variables: ["groupId": .string(groupId), "siteId": .string(siteId)], as: JSONValue.self)
    }

    public func removeSite(_ siteId: String, fromGroup groupId: String) async throws {
        _ = try await execute(Documents.removeSiteFromGroup, variables: ["groupId": .string(groupId), "siteId": .string(siteId)], as: JSONValue.self)
    }

    public func setGroupRoles(groupId: String, roleIds: [String]) async throws {
        _ = try await execute(
            Documents.setGroupRoles, variables: ["groupId": .string(groupId), "roleIds": .array(roleIds.map { .string($0) })], as: JSONValue.self)
    }

    public func assignUsers(_ userIds: [String], toGroup groupId: String) async throws {
        guard !userIds.isEmpty else { return }
        _ = try await execute(
            Documents.assignUsersToGroup, variables: ["groupId": .string(groupId), "userIds": .array(userIds.map { .string($0) })], as: JSONValue.self)
    }

    public func removeUsers(_ userIds: [String], fromGroup groupId: String) async throws {
        guard !userIds.isEmpty else { return }
        _ = try await execute(
            Documents.removeUsersFromGroup, variables: ["groupId": .string(groupId), "userIds": .array(userIds.map { .string($0) })], as: JSONValue.self)
    }

    /// The roles of an organization, sorted by name. With no organization, the roles the viewer can see.
    public func roles(organizationId: String? = nil) async throws -> [AccessRole] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let roles: [AccessRole]? }
            let ListRoles: List?
        }
        var variables: [String: JSONValue] = ["options": .object(["first": .number(200)])]
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        let rows = try await execute(Documents.listRoles, variables: variables, as: Answer.self).ListRoles?.roles ?? []
        return rows.filter { ($0.deletedAt ?? "").isEmpty }.sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
    }

    public func role(id: String) async throws -> AccessRole {
        struct Answer: Decodable, Sendable { let GetRole: AccessRole? }
        guard let role = try await execute(Documents.getRole, variables: ["roleId": .string(id)], as: Answer.self).GetRole else {
            throw PortalError.refused("That role was not found.")
        }
        return role
    }

    public func permissionCatalog(organizationId: String) async throws -> [String] {
        struct Answer: Decodable, Sendable { let ListPermissionCatalog: [String]? }
        return try await execute(Documents.listPermissionCatalog, variables: ["organizationId": .string(organizationId)], as: Answer.self)
            .ListPermissionCatalog ?? []
    }

    public func createRole(organizationId: String, name: String, description: String) async throws -> String {
        struct Answer: Decodable, Sendable {
            struct Created: Decodable, Sendable {
                struct Row: Decodable, Sendable { let id: String }
                let role: Row
            }
            let CreateRole: Created
        }
        let variables: [String: JSONValue] = ["organizationId": .string(organizationId), "name": .string(name), "description": .string(description)]
        return try await execute(Documents.createRole, variables: variables, as: Answer.self).CreateRole.role.id
    }

    public func modifyRole(id: String, name: String, description: String) async throws {
        _ = try await execute(
            Documents.modifyRole, variables: ["roleId": .string(id), "name": .string(name), "description": .string(description)], as: JSONValue.self)
    }

    public func deleteRole(id: String) async throws {
        _ = try await execute(Documents.deleteRole, variables: ["roleId": .string(id)], as: JSONValue.self)
    }

    public func setRolePermissions(roleId: String, permissions: [String]) async throws {
        _ = try await execute(
            Documents.setRolePermissions, variables: ["roleId": .string(roleId), "permissions": .array(permissions.map { .string($0) })], as: JSONValue.self)
    }
}
