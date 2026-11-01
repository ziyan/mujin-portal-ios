import Foundation
import Testing

@testable import PortalKit

@Suite struct PeopleTests {
    static func access(_ permissions: [String], mujin: Bool = false, own: String? = "org1") -> PeopleAccess {
        PeopleAccess(permissions: permissions, isMujinUser: mujin, viewerOrganizationId: own)
    }

    @Test func anOrganizationAdministratorManagesTheirOwnOrganizationOnly() {
        let admin = Self.access(["organization:operate-all"])
        #expect(admin.canManageUsers(in: "org1"))
        #expect(admin.canSeeGroups(in: "org1"))
        #expect(admin.canEditGroups(in: "org1"))
        #expect(admin.canEditRoles(in: "org1"))
        #expect(!admin.canManageUsers(in: "org2"))
        #expect(!admin.canSeeMembers(in: "org2"))
        #expect(!admin.canSeeGroups(in: "org2"))
        #expect(!admin.canSeeRoles(in: "org2"))
    }

    @Test func aPlatformAdministratorReachesEveryOrganization() {
        let platform = Self.access(["platform:administer"], mujin: true)
        #expect(platform.canManageUsers(in: "org2"))
        #expect(platform.canDeactivateUsers(in: "org2"))
        #expect(platform.canEditGroups(in: "org2"))
        #expect(platform.canEditRoles(in: "org2"))
        #expect(platform.hasPeopleEntry)
    }

    @Test func aMujinUserWithoutAdministratorRightsReadsMembersButChangesNothingElsewhere() {
        let staff = Self.access(["user:manage", "group:manage", "role:manage"], mujin: true)
        #expect(staff.canSeeMembers(in: "org2"))
        #expect(!staff.canManageUsers(in: "org2"))
        #expect(!staff.canSeeGroups(in: "org2"))
        #expect(!staff.canEditRoles(in: "org2"))
        // In their own organization the permissions count.
        #expect(staff.canManageUsers(in: "org1"))
        #expect(staff.canEditRoles(in: "org1"))
    }

    @Test func aSingleVerbOpensOnlyWhatItCovers() {
        let deactivator = Self.access(["user:deactivate"])
        #expect(deactivator.canDeactivateUsers(in: "org1"))
        #expect(!deactivator.canManageUsers(in: "org1"))
        #expect(!deactivator.canSeeGroups(in: "org1"))
        #expect(!deactivator.canOpenRoles(in: "org1"))
        #expect(deactivator.hasPeopleScreens(in: "org1"))
    }

    @Test func groupManagementWithoutAdministratorRightsCannotOpenTheList() {
        // The server lists groups for administrators only, so the screen is not offered to a holder of group:manage alone.
        let manager = Self.access(["group:manage"])
        #expect(!manager.canSeeGroups(in: "org1"))
        #expect(!manager.canEditGroups(in: "org1"))
    }

    @Test func anOrdinaryMemberHasNoPeopleEntry() {
        let member = Self.access(["ticket:read", "site:read"])
        #expect(!member.hasPeopleEntry)
        #expect(!member.hasPeopleScreens(in: "org1"))
        #expect(!member.canManageUsers(in: "org1"))
        #expect(!member.canDeactivateUsers(in: "org1"))
        #expect(member.canSeeMembers(in: "org1"))
        #expect(!Self.access([], own: nil).canSeeMembers(in: nil))
    }

    @Test func membersAreFoundByNameOrAddressAndDeactivatedOnesAreHiddenByDefault() {
        let members = [
            OrganizationMember(id: "u1", email: "robin@example.test", name: "Robin Demo"),
            OrganizationMember(id: "u2", email: "sam@example.test", name: "Sam Sample", isActive: false),
            OrganizationMember(id: "u3", email: "alex@example.test", name: "Alex Example", isActive: true),
            OrganizationMember(id: "u4", email: "nameless@example.test", name: ""),
        ]
        #expect(MemberDirectory.filter(members).map(\.id) == ["u3", "u4", "u1"])
        #expect(MemberDirectory.filter(members, includesDeactivated: true).map(\.id) == ["u3", "u4", "u1", "u2"])
        #expect(MemberDirectory.filter(members, query: "SAMPLE", includesDeactivated: true).map(\.id) == ["u2"])
        #expect(MemberDirectory.filter(members, query: "nameless").map(\.id) == ["u4"])
        #expect(MemberDirectory.filter(members, query: "sample").isEmpty)
        #expect(MemberDirectory.deactivatedCount(members) == 1)
        #expect(members[3].shownName == "nameless@example.test")
    }

    @Test func thePermissionCatalogIsGroupedByWhatItIsAbout() {
        let groups = PermissionCatalog.grouped(["ticket:modify", "site:read", "ticket:create", "virtual_controller:create", "ticket:create", "standalone"])
        #expect(groups.map(\.resource) == ["site", "standalone", "ticket", "virtual_controller"])
        #expect(groups[2].permissions == ["ticket:create", "ticket:modify"])
        #expect(groups[3].title == "Virtual controller")
        #expect(groups[1].permissions == ["standalone"])
        #expect(groups[2].selectedCount(in: ["ticket:modify", "site:read"]) == 1)
        #expect(PermissionCatalog.grouped([]).isEmpty)
    }

    @Test func switchingAPermissionKeepsTheRestAndTheOrder() {
        #expect(PermissionCatalog.setting("ticket:create", isOn: true, in: ["site:read", "audit:read"]) == ["audit:read", "site:read", "ticket:create"])
        #expect(PermissionCatalog.setting("site:read", isOn: false, in: ["site:read", "audit:read"]) == ["audit:read"])
        #expect(PermissionCatalog.setting("site:read", isOn: true, in: ["site:read"]) == ["site:read"])
        // A permission the catalog no longer offers stays, so saving does not quietly remove it.
        #expect(PermissionCatalog.setting("site:read", isOn: false, in: ["site:read", "retired:thing"]) == ["retired:thing"])
    }

    @Test func aChangedSelectionAddsAndRemovesOnlyTheDifference() {
        let changes = SelectionChanges(current: ["a", "b", "c"], wanted: ["b", "c", "d", "e"])
        #expect(changes.added == ["d", "e"])
        #expect(changes.removed == ["a"])
        #expect(!changes.isEmpty)
        #expect(SelectionChanges(current: ["a"], wanted: ["a"]).isEmpty)
    }

    @Test func aPersonsRolesAreListedPerSiteWithRoleNames() throws {
        let sites = [
            SiteSummary(id: "s2", name: "Packing hall"), SiteSummary(id: "s1", name: "Dock"), SiteSummary(id: "s3", name: "Closed", isArchived: true),
            SiteSummary(id: "s4", name: "Annex"),
        ]
        let assignments = [
            SiteRoleAssignment(userId: "u1", siteId: "s1", roleId: "r2"), SiteRoleAssignment(userId: "u1", siteId: "s1", roleId: "r1"),
            SiteRoleAssignment(userId: "u1", siteId: "s1", roleId: "r1"), SiteRoleAssignment(userId: "u1", siteId: "s2", roleId: "r9"),
        ]
        let rows = UserSites.roles(sites: sites, assignments: assignments, roleNames: ["r1": "Operator", "r2": "Auditor"])
        #expect(rows.map(\.siteName) == ["Annex", "Dock", "Packing hall"])
        #expect(rows[1].roleNames == ["Auditor", "Operator"])
        // A role whose name cannot be read is left out rather than shown as an id.
        #expect(rows[2].roleNames.isEmpty)
        #expect(rows[0].roleNames.isEmpty)
    }

    @Test func groupsComeDefaultFirstThenByName() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            [
                "ListGroups": [
                    "groups": [["id": "g1", "name": "Shift leads", "siteIds": ["s1", "s2"], "roles": ["r1"]], ["id": "g2", "name": "Everyone", "isDefault": true], ["id": "g3", "name": "Admins"]]
                ]
            ]
        }
        let groups = try await connection.groups(organizationId: "org1")
        #expect(groups.map(\.id) == ["g2", "g3", "g1"])
        #expect(groups[2].siteCount == 2)
        #expect(groups[2].roleCount == 1)
        #expect(sentVariables(transport.requests[0])["organizationId"] as? String == "org1")
    }

    @Test func creatingAGroupSendsTheEmptySignInMappingTheServerRequires() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["CreateGroup": ["group": ["id": "g9"]]] }
        let identifier = try await connection.createGroup(organizationId: "org1", name: "Pick team", description: "")
        #expect(identifier == "g9")
        let variables = sentVariables(transport.requests[0])
        #expect(variables["oidcGroupName"] as? String == "")
        #expect(variables["oidcRoleName"] as? String == "")
        #expect(variables["name"] as? String == "Pick team")
    }

    @Test func membersAreReadPageAfterPageUntilTheTotal() async throws {
        let (connection, transport) = scriptedConnection { _, variables in
            let offset = ((variables["options"] as? [String: Any])?["after"] as? Int) ?? 0
            let rows: [[String: Any]] = offset == 0 ? [["id": "u1"], ["id": "u2"]] : [["id": "u3"]]
            return ["ListOrganizationUsers": ["users": rows, "meta": ["totalCount": 3]]]
        }
        let members = try await connection.organizationMembers(organizationId: "org1", pageSize: 2)
        #expect(members.map(\.id) == ["u1", "u2", "u3"])
        #expect(transport.requests.count == 2)
    }

    @Test func rolesLeaveOutDeletedOnesAndSortByName() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            ["ListRoles": ["roles": [["id": "r1", "name": "Operator", "permissions": ["site:read"]], ["id": "r2", "name": "Auditor"], ["id": "r3", "name": "Old", "deletedAt": "2026-01-01T00:00:00Z"]]]]
        }
        let roles = try await connection.roles(organizationId: "org1")
        #expect(roles.map(\.id) == ["r2", "r1"])
        #expect(roles[1].permissionCount == 1)
    }

    @Test func savingRolePermissionsSendsTheWholeSet() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["SetRolePermissions": ["role": ["id": "r1"]]] }
        try await connection.setRolePermissions(roleId: "r1", permissions: ["audit:read", "site:read"])
        let variables = sentVariables(transport.requests[0])
        #expect(variables["roleId"] as? String == "r1")
        #expect(variables["permissions"] as? [String] == ["audit:read", "site:read"])
    }

    @Test func aGroupRosterChangeWithNobodyIsNotSent() async throws {
        let (connection, transport) = scriptedConnection { _, _ in [:] }
        try await connection.assignUsers([], toGroup: "g1")
        try await connection.removeUsers([], fromGroup: "g1")
        #expect(transport.requests.isEmpty)
    }

    @Test func aMissingUserIsReportedInPlainWords() async {
        let (connection, _) = scriptedConnection { _, _ in ["GetUser": NSNull()] }
        await #expect(throws: PortalError.refused("That person was not found.")) { _ = try await connection.userProfile(id: "u1") }
    }
}
