import Foundation

/// AccountDemo answers the account and people documents on the demo server, from invented people, groups, roles, sessions, tokens
/// and keys. A change the app makes (revoking a session, renaming a key, switching a permission) sticks until the app is closed.
/// Every name here is made up.
enum AccountDemo {
    /// The screens of the screenshot run that belong here.
    static func owns(_ screen: String) -> Bool { screen.hasPrefix("account-") || screen.hasPrefix("people-") }

    /// The screens under More the screenshot run opens on.
    static func morePath(_ screen: String) -> [MoreDestination] {
        let customer = "organization01"
        switch screen {
        case "account-profile": return [.account(.profile)]
        case "account-sessions", "account-sessions-detail": return [.account(.sessions)]
        case "account-passkeys": return [.account(.passkeys)]
        case "account-tokens": return [.account(.tokens)]
        case "account-apps", "account-apps-detail": return [.account(.authorizedApps)]
        case "account-vpn": return [.account(.vpn)]
        case "account-ssh", "account-ssh-detail": return [.account(.sshKeys)]
        case "people-organizations": return [.account(.organizations)]
        case "people-hub": return [.account(.people(organizationId: customer))]
        case "people-members": return [.account(.members(organizationId: customer))]
        case "people-user": return [.account(.members(organizationId: customer)), .account(.user(id: "user03", organizationId: customer))]
        case "people-user-deactivated": return [.account(.members(organizationId: customer)), .account(.user(id: "user05", organizationId: customer))]
        case "people-groups": return [.account(.groups(organizationId: customer))]
        case "people-group": return [.account(.groups(organizationId: customer)), .account(.group(id: "group02", organizationId: customer))]
        case "people-roles": return [.account(.roles(organizationId: customer))]
        case "people-role": return [.account(.roles(organizationId: customer)), .account(.role(id: "role02", organizationId: customer))]
        case "people-staff-members": return [.account(.organizations), .account(.people(organizationId: "organization02")), .account(.members(organizationId: "organization02"))]
        default: return []
        }
    }

    /// Whether the screen opens the first row of its list, as a person taps it.
    static func opensFirstItem(_ screen: String?) -> Bool { (screen ?? "").hasSuffix("-detail") }

    /// The answer to a document, or nil when it is not one of these.
    static func respond(operation: String, variables: [String: Any]) -> [String: Any]? {
        store.withData { data in answer(operation: operation, variables: variables, data: &data) }
    }

    // MARK: data

    private struct DemoData {
        var users: [[String: Any]]
        var sessions: [[String: Any]]
        var tokens: [[String: Any]]
        var passkeys: [[String: Any]]
        var consents: [[String: Any]]
        var peers: [[String: Any]]
        var keys: [[String: Any]]
        var roles: [[String: Any]]
        var groups: [[String: Any]]
        var groupUsers: [String: [String]]
        var nextNumber = 100
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var data = AccountDemo.makeData()

        func withData<Result>(_ body: (inout DemoData) -> Result) -> Result {
            lock.lock()
            defer { lock.unlock() }
            return body(&data)
        }
    }

    private static let store = Store()

    private static func stamp(_ secondsAgo: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo))
    }

    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3_600
    private static let day: TimeInterval = 86_400

    private static let permissionCatalog = [
        "site:read", "site:modify", "site:create", "site:delete", "site:assign", "controller:edit", "controller:connect", "controller:write", "controller:link",
        "backup:delete", "virtual_controller:create", "virtual_controller:modify", "virtual_controller:destroy", "virtual_controller:connect",
        "virtual_controller:write", "ticket:create", "ticket:modify", "ticket:assign", "ticket:transition", "ticket:comment", "ticket:read-org",
        "ticket:create-org", "ticket:comment-org", "ticket:read-site", "incident:annotate", "incident:transition", "incident:link", "page:edit",
        "page:publish", "page:delete", "audit:read", "group:manage", "group:members", "role:manage", "user:manage", "user:deactivate",
        "organization:modify", "organization:operate-all", "organization:read-all", "billing:read", "billing:manage", "memory:write",
    ]

    private static func makeData() -> DemoData {
        func user(_ id: String, _ name: String, _ email: String, _ organizationId: String, active: Bool = true, role: String = "", seen: TimeInterval = 3 * hour) -> [String: Any] {
            [
                "id": id, "name": name, "email": email, "organizationId": organizationId, "isActive": active, "hasAvatar": false, "jobRole": role,
                "jobActivities": id == "user01" ? ["operations", "safety"] : [], "timezone": "America/New_York", "locale": "en",
                "createdAt": stamp(200 * day), "loggedInAt": stamp(seen), "modifiedAt": "2026-01-01T00:00:00Z",
            ]
        }
        func session(_ id: String, _ agent: String, _ address: String, _ city: String, used: TimeInterval, created: TimeInterval) -> [String: Any] {
            [
                "id": id, "comment": "", "userAgent": agent, "ip": address, "location": ["city": city, "country": "US"], "usedAt": stamp(used),
                "createdAt": stamp(created), "authorizedAt": stamp(created), "expiresAt": NSNull(), "revokedAt": NSNull(),
            ]
        }
        func token(_ id: String, _ comment: String, created: TimeInterval, used: TimeInterval?, expires: TimeInterval?, address: String? = nil) -> [String: Any] {
            [
                "id": id, "comment": comment, "createdAt": stamp(created), "authorizedAt": stamp(created), "usedAt": used.map(stamp) ?? NSNull(),
                "expiresAt": expires.map { stamp(-$0) } ?? NSNull(), "revokedAt": NSNull(), "ip": address ?? NSNull(), "userAgent": NSNull(), "location": NSNull(),
            ]
        }
        func role(_ id: String, _ name: String, _ description: String, _ organizationId: String, _ permissions: [String]) -> [String: Any] {
            ["id": id, "name": name, "description": description, "organizationId": organizationId, "permissions": permissions, "createdAt": stamp(150 * day), "modifiedAt": stamp(20 * day), "deletedAt": NSNull()]
        }
        func group(_ id: String, _ name: String, _ description: String, isDefault: Bool = false, sites: [String], roles: [String], organizationId: String = "organization01") -> [String: Any] {
            [
                "id": id, "name": name, "description": description, "organizationId": organizationId, "isDefault": isDefault, "siteIds": sites, "roles": roles,
                "oidcGroupName": "", "oidcRoleName": "", "createdAt": stamp(150 * day), "modifiedAt": stamp(10 * day),
            ]
        }
        return DemoData(
            users: [
                user("user01", "Alex Example", "alex@example.test", "organization01", role: "Operations lead", seen: 5 * minute),
                user("user02", "Sam Sample", "sam@example.test", "organization01", role: "Site manager", seen: 2 * hour),
                user("user03", "Robin Demo", "robin@example.test", "organization01", role: "Shift supervisor", seen: day),
                user("user04", "Jordan Placeholder", "jordan@example.test", "organization01", seen: 6 * day),
                user("user05", "Casey Illustration", "casey@example.test", "organization01", active: false, seen: 120 * day),
                user("user06", "Morgan Fictional", "morgan@example.test", "organization01", seen: 30 * day),
                user("user07", "Taylor Imaginary", "taylor@example.test", "organization01", seen: 2 * day),
                user("user11", "Pat Sampleton", "pat@example.test", "organization02", seen: day),
                user("user12", "Lee Mockwell", "lee@example.test", "organization02", seen: 4 * day),
                user("user13", "Dana Invented", "dana@example.test", "organization02", seen: 9 * day),
                user("user21", "Ana Support", "ana@example.test", "organization00", seen: 3 * hour),
            ],
            sessions: [
                session("session01", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", "203.0.113.24", "Springfield", used: 5 * minute, created: 3 * day),
                session("session02", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", "198.51.100.7", "Metropolis", used: 2 * hour, created: 12 * day),
                session("session03", "Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0", "192.0.2.55", "Capital City", used: 3 * day, created: 20 * day),
                session("session04", "curl/8.5.0", "203.0.113.99", "Springfield", used: 9 * day, created: 9 * day),
            ],
            tokens: [
                token("token01", "Nightly export script", created: 40 * day, used: day, expires: 50 * day, address: "203.0.113.80"),
                token("token02", "Dashboard sync", created: 10 * day, used: 3 * hour, expires: nil, address: "198.51.100.12"),
                token("token03", "Spreadsheet add-in", created: 90 * day, used: nil, expires: 20 * day),
            ],
            passkeys: [
                ["id": "passkey01", "name": "Alex's iPhone", "createdAt": stamp(60 * day), "usedAt": stamp(day), "backupEligible": true, "backupState": true],
                ["id": "passkey02", "name": "Office laptop", "createdAt": stamp(30 * day), "usedAt": stamp(9 * day), "backupEligible": false, "backupState": false],
                ["id": "passkey03", "name": "Security key", "createdAt": stamp(200 * day), "usedAt": NSNull(), "backupEligible": false, "backupState": false],
            ],
            consents: [
                ["id": "consent01", "clientId": "mujin-portal-ios", "clientName": "Mujin Portal for iPhone", "grantedScopes": ["api:read", "api:write"], "createdAt": stamp(20 * day), "modifiedAt": stamp(20 * day)],
                ["id": "consent02", "clientId": "fleet-dashboard-example", "clientName": "Fleet dashboard (example)", "grantedScopes": ["api:read"], "createdAt": stamp(50 * day), "modifiedAt": stamp(50 * day)],
                ["id": "consent03", "clientId": "reporting-notebook-example", "clientName": "Reporting notebook", "grantedScopes": ["api:read", "api:write"], "createdAt": stamp(5 * day), "modifiedAt": stamp(5 * day)],
            ],
            peers: [
                ["id": "peer01", "comment": "Home laptop", "publicKey": "FkQGLQvznnol7JRQ5DGfPPAH+Zp6uFiclKvs1DiSmdg=", "createdAt": stamp(100 * day), "modifiedAt": stamp(100 * day), "lastHandshakeAt": stamp(2 * hour), "revokedAt": NSNull()],
                ["id": "peer02", "comment": "Tablet", "publicKey": "kVlf7GJ6DC8wOsvq2XC9yKkuvE6WVa5GVtViUyh4ppQ=", "createdAt": stamp(15 * day), "modifiedAt": stamp(15 * day), "lastHandshakeAt": NSNull(), "revokedAt": NSNull()],
            ],
            keys: [
                ["id": "key01", "comment": "work-laptop", "publicKey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICycyCqsiXxn6a4o5TKG8ju7v2hXUI70olpYIej0XSWW demo-laptop", "createdAt": stamp(80 * day), "modifiedAt": stamp(80 * day), "lastUsedAt": stamp(2 * day), "revokedAt": NSNull()],
                ["id": "key02", "comment": "build-box", "publicKey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIIg+P3UZ1c84zhC7nsnU/utSk95HsSauSH1gYekX1Z build-box", "createdAt": stamp(12 * day), "modifiedAt": stamp(12 * day), "lastUsedAt": NSNull(), "revokedAt": NSNull()],
            ],
            roles: [
                role("role01", "Operator", "Runs the floor: sees sites, connects to controllers and works tickets.", "organization01", ["site:read", "controller:connect", "ticket:create", "ticket:comment", "incident:annotate"]),
                role("role02", "Site manager", "Everything an operator can do, and changes how a site is set up.", "organization01", ["site:read", "site:modify", "controller:connect", "controller:write", "controller:edit", "ticket:create", "ticket:modify", "ticket:assign", "ticket:transition", "ticket:comment", "incident:annotate", "incident:transition", "page:edit"]),
                role("role03", "Auditor", "Reads sites and the audit trail, and changes nothing.", "organization01", ["site:read", "audit:read", "ticket:read-site"]),
                role("role04", "Administrator", "Runs the organization.", "organization01", ["organization:operate-all"]),
                role("role11", "Line operator", "Works the line.", "organization02", ["site:read", "controller:connect"]),
                role("role12", "Supervisor", "Leads a shift.", "organization02", ["site:read", "controller:connect", "ticket:create"]),
            ],
            groups: [
                group("group01", "Everyone", "Every member of the organization.", isDefault: true, sites: ["site01", "site02"], roles: ["role01"]),
                group("group02", "Shift leads", "People who run a shift and can change a site.", sites: ["site01"], roles: ["role02"]),
                group("group03", "Auditors", "Read-only access for reviews.", sites: ["site01", "site02"], roles: ["role03"]),
                group("group04", "Administrators", "", sites: ["site01", "site02"], roles: ["role04"]),
                group("group11", "Line crew", "", isDefault: true, sites: ["site03", "site04"], roles: ["role11"], organizationId: "organization02"),
            ],
            groupUsers: [
                "group01": ["user01", "user02", "user03", "user04", "user06", "user07"], "group02": ["user02", "user03"], "group03": ["user04"], "group04": ["user01"],
                "group11": ["user11", "user12", "user13"],
            ])
    }

    // MARK: answers

    private static func answer(operation: String, variables: [String: Any], data: inout DemoData) -> [String: Any]? {
        let identifier = { (key: String) in variables[key] as? String ?? "" }
        let organizationId = identifier("organizationId")
        switch operation {
        case "Me":
            let screen = DemoOptions.screen ?? ""
            guard screen == "people-limited" || DemoOptions.isStaff else { return nil }
            let permissions = screen == "people-limited" ? ["ticket:read", "ticket:write", "site:read"] : ["ticket:read", "ticket:write", "site:read", "organization:operate-all", "platform:administer"]
            return ["Me": ["id": "user01", "email": "alex@example.test", "name": "Alex Example", "organizationId": "organization01", "hasAvatar": false, "modifiedAt": "2026-01-01T00:00:00Z", "permissions": permissions]]
        // The person's own security.
        case "ListSessions":
            return ["ListSessions": ["currentSessionId": "", "sessions": data.sessions, "meta": ["totalCount": data.sessions.count]]]
        case "RevokeSession":
            data.sessions.removeAll { ($0["id"] as? String) == identifier("sessionId") }
            return ["RevokeSession": true]
        case "ListTokens":
            return ["ListTokens": ["tokens": data.tokens, "meta": ["totalCount": data.tokens.count]]]
        case "RevokeToken":
            data.tokens.removeAll { ($0["id"] as? String) == identifier("tokenId") }
            return ["RevokeToken": true]
        case "RevokeTokens":
            let identifiers = variables["tokenIds"] as? [String] ?? []
            data.tokens.removeAll { identifiers.contains($0["id"] as? String ?? "") }
            return ["RevokeTokens": ["tokenIds": identifiers]]
        case "ListPasskeys":
            return ["ListPasskeys": ["passkeys": data.passkeys, "meta": ["totalCount": data.passkeys.count]]]
        case "ModifyPasskey":
            rename(&data.passkeys, identifier("passkeyId"), key: "name", to: identifier("name"))
            return ["ModifyPasskey": ["passkey": ["id": identifier("passkeyId"), "name": identifier("name")]]]
        case "DeletePasskey":
            data.passkeys.removeAll { ($0["id"] as? String) == identifier("passkeyId") }
            return ["DeletePasskey": ["passkeyId": identifier("passkeyId")]]
        case "ListOAuthConsents":
            return ["ListOAuthConsents": ["oauthConsents": data.consents, "meta": ["totalCount": data.consents.count]]]
        case "RevokeOAuthConsent":
            data.consents.removeAll { ($0["id"] as? String) == identifier("oauthConsentId") }
            return ["RevokeOAuthConsent": true]
        case "ListWireGuardPeers":
            return ["ListWireGuardPeers": ["wireGuardPeers": data.peers, "meta": ["totalCount": data.peers.count]]]
        case "ModifyWireGuardPeer":
            rename(&data.peers, identifier("wireGuardPeerId"), key: "comment", to: identifier("comment"))
            return ["ModifyWireGuardPeer": ["wireGuardPeer": ["id": identifier("wireGuardPeerId"), "comment": identifier("comment")]]]
        case "RevokeWireGuardPeer":
            data.peers.removeAll { ($0["id"] as? String) == identifier("wireGuardPeerId") }
            return ["RevokeWireGuardPeer": ["wireGuardPeer": ["id": identifier("wireGuardPeerId"), "revokedAt": stamp(0)]]]
        case "ListSSHKeys":
            return ["ListSSHKeys": ["sshKeys": data.keys, "meta": ["totalCount": data.keys.count]]]
        case "ModifySSHKey":
            rename(&data.keys, identifier("sshKeyId"), key: "comment", to: identifier("comment"))
            return ["ModifySSHKey": ["sshKey": ["id": identifier("sshKeyId"), "comment": identifier("comment")]]]
        case "RevokeSSHKey":
            data.keys.removeAll { ($0["id"] as? String) == identifier("sshKeyId") }
            return ["RevokeSSHKey": ["sshKey": ["id": identifier("sshKeyId"), "revokedAt": stamp(0)]]]
        case "ModifyUser":
            if let name = (variables["user"] as? [String: Any])?["name"] as? String { rename(&data.users, identifier("userId"), key: "name", to: name) }
            return ["ModifyUser": ["user": ["id": identifier("userId")]]]
        case "ModifyMyProfessionalProfile":
            if let index = data.users.firstIndex(where: { ($0["id"] as? String) == "user01" }) {
                data.users[index]["jobRole"] = variables["jobRole"] as? String ?? ""
                data.users[index]["jobActivities"] = variables["jobActivities"] as? [String] ?? []
            }
            return ["ModifyMyProfessionalProfile": ["user": ["id": "user01"]]]
        // The people of an organization.
        case "ListOrganizationUsers":
            let scope = organizationId.isEmpty ? "organization01" : organizationId
            let members = data.users.filter { ($0["organizationId"] as? String) == scope }
            return ["ListOrganizationUsers": ["users": members, "meta": ["totalCount": members.count]]]
        case "GetUser":
            guard let found = data.users.first(where: { ($0["id"] as? String) == identifier("userId") }) else { return nil }
            return ["GetUser": found]
        case "SetUserActive":
            if let index = data.users.firstIndex(where: { ($0["id"] as? String) == identifier("userId") }) { data.users[index]["isActive"] = variables["isActive"] as? Bool ?? true }
            return ["SetUserActive": ["user": ["id": identifier("userId"), "isActive": variables["isActive"] as? Bool ?? true]]]
        case "ListUserSites":
            let home = data.users.first { ($0["id"] as? String) == identifier("userId") }?["organizationId"] as? String
            let sites: [[String: Any]] = home == "organization02"
                ? [["id": "site03", "name": "Bakery line", "organizationId": "organization02", "isArchived": false], ["id": "site04", "name": "Cold store", "organizationId": "organization02", "isArchived": false]]
                : [["id": "site01", "name": "site01", "organizationId": "organization01", "isArchived": false], ["id": "site02", "name": "site02", "organizationId": "organization01", "isArchived": false]]
            return ["ListUserSites": sites]
        case "ListSiteRoleAssignments":
            let userId = identifier("userId")
            let groups = data.groups.filter { (data.groupUsers[$0["id"] as? String ?? ""] ?? []).contains(userId) }
            var assignments: [[String: Any]] = []
            for group in groups {
                for siteId in group["siteIds"] as? [String] ?? [] {
                    for roleId in group["roles"] as? [String] ?? [] { assignments.append(["userId": userId, "siteId": siteId, "roleId": roleId]) }
                }
            }
            return ["ListSiteRoleAssignments": assignments]
        case "ListUserGroups":
            let userId = identifier("userId")
            return ["ListUserGroups": data.groups.filter { (data.groupUsers[$0["id"] as? String ?? ""] ?? []).contains(userId) }]
        // Groups.
        case "ListGroups":
            let groups = data.groups.filter { ($0["organizationId"] as? String) == (organizationId.isEmpty ? "organization01" : organizationId) }
            return ["ListGroups": ["groups": groups, "meta": ["totalCount": groups.count]]]
        case "GetGroup":
            guard let found = data.groups.first(where: { ($0["id"] as? String) == identifier("groupId") }) else { return nil }
            return ["GetGroup": found]
        case "ListGroupUserIDs":
            return ["ListGroupUserIDs": data.groupUsers[identifier("groupId")] ?? []]
        case "CreateGroup":
            data.nextNumber += 1
            let newId = "group\(data.nextNumber)"
            data.groups.append([
                "id": newId, "name": identifier("name"), "description": identifier("description"), "organizationId": organizationId, "isDefault": false, "siteIds": [String](),
                "roles": [String](), "oidcGroupName": "", "oidcRoleName": "", "createdAt": stamp(0), "modifiedAt": stamp(0),
            ])
            return ["CreateGroup": ["group": ["id": newId]]]
        case "ModifyGroup":
            rename(&data.groups, identifier("groupId"), key: "name", to: identifier("name"))
            rename(&data.groups, identifier("groupId"), key: "description", to: identifier("description"))
            return ["ModifyGroup": ["group": ["id": identifier("groupId")]]]
        case "DeleteGroup":
            data.groups.removeAll { ($0["id"] as? String) == identifier("groupId") }
            return ["DeleteGroup": ["groupId": identifier("groupId")]]
        case "SetDefaultGroup":
            for index in data.groups.indices { data.groups[index]["isDefault"] = (data.groups[index]["id"] as? String) == identifier("groupId") }
            return ["SetDefaultGroup": ["group": ["id": identifier("groupId"), "isDefault": true]]]
        case "AssignSiteToGroup", "RemoveSiteFromGroup":
            if let index = data.groups.firstIndex(where: { ($0["id"] as? String) == identifier("groupId") }) {
                var sites = data.groups[index]["siteIds"] as? [String] ?? []
                if operation == "AssignSiteToGroup" { if !sites.contains(identifier("siteId")) { sites.append(identifier("siteId")) } } else { sites.removeAll { $0 == identifier("siteId") } }
                data.groups[index]["siteIds"] = sites
            }
            return [operation: ["group": ["id": identifier("groupId")]]]
        case "SetGroupRoles":
            if let index = data.groups.firstIndex(where: { ($0["id"] as? String) == identifier("groupId") }) { data.groups[index]["roles"] = variables["roleIds"] as? [String] ?? [] }
            return ["SetGroupRoles": ["group": ["id": identifier("groupId")]]]
        case "AssignUsersToGroup":
            let added = variables["userIds"] as? [String] ?? []
            let existing = data.groupUsers[identifier("groupId")] ?? []
            data.groupUsers[identifier("groupId"), default: []] += added.filter { !existing.contains($0) }
            return ["AssignUsersToGroup": ["groupId": identifier("groupId"), "userIds": added]]
        case "RemoveUsersFromGroup":
            let removed = variables["userIds"] as? [String] ?? []
            data.groupUsers[identifier("groupId"), default: []].removeAll { removed.contains($0) }
            return ["RemoveUsersFromGroup": ["groupId": identifier("groupId"), "userIds": removed]]
        // Roles.
        case "ListRoles":
            let roles = organizationId.isEmpty ? data.roles : data.roles.filter { ($0["organizationId"] as? String) == organizationId }
            return ["ListRoles": ["roles": roles, "meta": ["totalCount": roles.count]]]
        case "GetRole":
            guard let found = data.roles.first(where: { ($0["id"] as? String) == identifier("roleId") }) else { return nil }
            return ["GetRole": found]
        case "ListPermissionCatalog":
            return ["ListPermissionCatalog": permissionCatalog]
        case "CreateRole":
            data.nextNumber += 1
            let newId = "role\(data.nextNumber)"
            data.roles.append(["id": newId, "name": identifier("name"), "description": identifier("description"), "organizationId": organizationId, "permissions": [String](), "createdAt": stamp(0), "modifiedAt": stamp(0), "deletedAt": NSNull()])
            return ["CreateRole": ["role": ["id": newId]]]
        case "ModifyRole":
            rename(&data.roles, identifier("roleId"), key: "name", to: identifier("name"))
            rename(&data.roles, identifier("roleId"), key: "description", to: identifier("description"))
            return ["ModifyRole": ["role": ["id": identifier("roleId")]]]
        case "DeleteRole":
            data.roles.removeAll { ($0["id"] as? String) == identifier("roleId") }
            return ["DeleteRole": ["roleId": identifier("roleId")]]
        case "SetRolePermissions":
            if let index = data.roles.firstIndex(where: { ($0["id"] as? String) == identifier("roleId") }) { data.roles[index]["permissions"] = variables["permissions"] as? [String] ?? [] }
            return ["SetRolePermissions": ["role": ["id": identifier("roleId")]]]
        default:
            return nil
        }
    }

    private static func rename(_ rows: inout [[String: Any]], _ identifier: String, key: String, to value: String) {
        if let index = rows.firstIndex(where: { ($0["id"] as? String) == identifier }) { rows[index][key] = value }
    }
}
