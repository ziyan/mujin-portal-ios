import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// SignInPlace is where a sign-in came from, as far as the server could tell.
public struct SignInPlace: Codable, Equatable, Hashable, Sendable {
    public let city: String?
    public let country: String?

    /// "City, Country", or whichever of the two is known, or nil.
    public var text: String? {
        let parts = [city, country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// SignInRecord is one session or one API token. Portal lists both with the
/// same fields: when it was made, when it was last used, and where from.
public struct SignInRecord: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let comment: String?
    public let createdAt: String?
    public let authorizedAt: String?
    public let expiresAt: String?
    public let usedAt: String?
    public let revokedAt: String?
    public let ip: String?
    public let userAgent: String?
    public let location: SignInPlace?

    public var createdDate: Date? { PortalDate.parse(createdAt) }
    public var expiresDate: Date? { PortalDate.parse(expiresAt) }
    /// When it was last used, or made when it never was used again.
    public var lastSeenDate: Date? { PortalDate.parse(usedAt) ?? PortalDate.parse(createdAt) }
    public var isRevoked: Bool { !(revokedAt ?? "").isEmpty }

    public func isExpired(at now: Date = Date()) -> Bool {
        guard let expiresDate else { return false }
        return expiresDate <= now
    }

    /// The browser and system the user agent names, such as "Safari on iPhone".
    public var deviceName: String? { DeviceDescription.name(userAgent: userAgent) }
}

/// SessionList is the person's sessions with the one the request came in on.
public struct SessionList: Equatable, Sendable {
    public let currentSessionId: String
    public let sessions: [SignInRecord]
}

public enum SignInRecords {
    /// Records that still work, most recently used first. Revoked and expired ones are left out.
    public static func active(_ records: [SignInRecord], now: Date = Date()) -> [SignInRecord] {
        records.filter { !$0.isRevoked && !$0.isExpired(at: now) }
            .sorted { ($0.lastSeenDate ?? .distantPast) > ($1.lastSeenDate ?? .distantPast) }
    }

    /// Splits sessions into the current one, if the server named one that is listed, and the others.
    public static func splitCurrent(_ list: SessionList, now: Date = Date()) -> (current: SignInRecord?, others: [SignInRecord]) {
        let sessions = active(list.sessions, now: now)
        guard !list.currentSessionId.isEmpty else { return (nil, sessions) }
        return (sessions.first { $0.id == list.currentSessionId }, sessions.filter { $0.id != list.currentSessionId })
    }
}

/// DeviceDescription turns a user agent string into words a person recognizes.
public enum DeviceDescription {
    /// "Safari on iPhone", "Chrome on Windows", the program name for a command line tool, or nil when nothing is known.
    public static func name(userAgent: String?) -> String? {
        let text = (userAgent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard text.hasPrefix("Mozilla/") else {
            // A program such as a command line client names itself first: "curl/8.4.0".
            let program = text.split(whereSeparator: { $0 == "/" || $0 == " " }).first.map(String.init) ?? text
            return program.isEmpty ? nil : program
        }
        let system = system(in: text)
        let browser = browser(in: text)
        switch (browser, system) {
        case let (browser?, system?): return "\(browser) on \(system)"
        case let (browser?, nil): return browser
        case let (nil, system?): return system
        default: return nil
        }
    }

    private static func browser(in text: String) -> String? {
        // The order matters: Edge and Opera also say Chrome, and Chrome also says Safari.
        let browsers: [(marker: String, name: String)] = [
            ("Edg/", "Edge"), ("EdgA/", "Edge"), ("EdgiOS/", "Edge"), ("OPR/", "Opera"), ("Firefox/", "Firefox"), ("FxiOS/", "Firefox"),
            ("CriOS/", "Chrome"), ("Chrome/", "Chrome"), ("Safari/", "Safari"),
        ]
        return browsers.first { text.contains($0.marker) }?.name
    }

    private static func system(in text: String) -> String? {
        // The order matters again: an iPhone says "like Mac OS X", Android says Linux.
        let systems: [(marker: String, name: String)] = [
            ("iPhone", "iPhone"), ("iPad", "iPad"), ("Android", "Android"), ("Windows", "Windows"), ("CrOS", "ChromeOS"),
            ("Macintosh", "Mac"), ("Linux", "Linux"),
        ]
        return systems.first { text.contains($0.marker) }?.name
    }
}

/// Passkey is a sign-in key kept on one of the person's devices or in their password manager.
public struct Passkey: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let createdAt: String?
    public let usedAt: String?
    public let backupEligible: Bool?
    public let backupState: Bool?

    public var shownName: String { (name ?? "").isEmpty ? "Passkey" : name! }
    /// Whether the passkey is synced between the person's devices, which is what makes it survive losing one.
    public var isSynced: Bool { backupState == true }
}

/// AuthorizedApp is an app the person let sign in as them.
public struct AuthorizedApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let clientId: String?
    public let clientName: String?
    public let grantedScopes: [String]?
    public let createdAt: String?
    public let modifiedAt: String?

    public var shownName: String { (clientName ?? "").isEmpty ? (clientId ?? "App") : clientName! }
    /// This app itself. Its consent is shared by every phone and tablet signed in to the account, so it is ended with Sign out and not here.
    public var isThisApp: Bool { clientId == PortalClient.builtInClientId }
}

/// WireGuardPeer is one device allowed to join the person's VPN.
public struct WireGuardPeer: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let comment: String?
    public let publicKey: String?
    public let createdAt: String?
    public let modifiedAt: String?
    public let lastHandshakeAt: String?
    public let revokedAt: String?

    public var isRevoked: Bool { !(revokedAt ?? "").isEmpty }
    public var shownName: String { (comment ?? "").isEmpty ? "VPN device" : comment! }
}

/// SSHKey is a public key the person may sign in to a controller with.
public struct SSHKey: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let comment: String?
    public let publicKey: String?
    public let createdAt: String?
    public let modifiedAt: String?
    public let lastUsedAt: String?
    public let revokedAt: String?

    public var isRevoked: Bool { !(revokedAt ?? "").isEmpty }
    public var shownName: String { (comment ?? "").isEmpty ? "SSH key" : comment! }
    /// The key's fingerprint as `ssh-keygen -l` writes it, which is how a key is told apart from another.
    public var fingerprint: String? { SSHFingerprint.sha256(publicKey: publicKey) }
}

public enum SSHFingerprint {
    /// "SHA256:" and the unpadded base64 of the SHA-256 of the key's decoded body, or nil when the text is not an OpenSSH public key.
    public static func sha256(publicKey: String?) -> String? {
        let fields = (publicKey ?? "").split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        guard fields.count >= 2, let body = Data(base64Encoded: String(fields[1])), !body.isEmpty else { return nil }
        var encoded = Data(SHA256.hash(data: body)).base64EncodedString()
        while encoded.hasSuffix("=") { encoded.removeLast() }
        return "SHA256:" + encoded
    }
}

/// WireGuardKey shortens a public key to the start and end of it, enough to tell two apart.
public enum WireGuardKey {
    public static func abbreviated(_ publicKey: String?) -> String? {
        let key = (publicKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count > 12 else { return key.isEmpty ? nil : key }
        return key.prefix(6) + "…" + key.suffix(6)
    }
}

/// ProfessionalProfile is what the person says about their work, which Portal asks for beside their name.
public enum ProfessionalProfile {
    /// The responsibilities Portal suggests, in its order. A person may also type their own.
    public static let activityCodes = [
        "operations", "troubleshooting", "maintenance", "automation", "commissioning", "integration", "fleet", "fulfillment", "it", "safety",
        "improvement", "project",
    ]
    public static let maximumActivityCount = 5
    public static let maximumJobRoleLength = 64

    /// The responsibilities with one switched on or off. Switching one on past the limit changes nothing.
    public static func toggling(_ activities: [String], _ activity: String) -> [String] {
        if activities.contains(activity) { return activities.filter { $0 != activity } }
        guard activities.count < maximumActivityCount else { return activities }
        return activities + [activity]
    }

    public static func canAddActivity(to activities: [String]) -> Bool { activities.count < maximumActivityCount }
}

extension Documents {
    static let signInRecordFields = "id comment createdAt authorizedAt expiresAt usedAt revokedAt ip userAgent location { city country }"

    public static let listSessions = """
        query ListSessions($includeRevoked: Boolean, $options: ListOptionsInput) {
          ListSessions(includeRevoked: $includeRevoked, options: $options) {
            currentSessionId
            sessions { \(signInRecordFields) }
            meta { totalCount }
          }
        }
        """

    public static let revokeSession = """
        mutation RevokeSession($sessionId: String!) { RevokeSession(sessionId: $sessionId) }
        """

    public static let listPasskeys = """
        query ListPasskeys($userId: String, $options: ListOptionsInput) {
          ListPasskeys(userId: $userId, options: $options) {
            passkeys { id name createdAt usedAt backupEligible backupState }
            meta { totalCount }
          }
        }
        """

    public static let modifyPasskey = """
        mutation ModifyPasskey($passkeyId: String!, $name: String!) {
          ModifyPasskey(passkeyId: $passkeyId, name: $name) { passkey { id name } }
        }
        """

    public static let deletePasskey = """
        mutation DeletePasskey($passkeyId: String!) { DeletePasskey(passkeyId: $passkeyId) { passkeyId } }
        """

    public static let listTokens = """
        query ListTokens($includeRevoked: Boolean, $options: ListOptionsInput) {
          ListTokens(includeRevoked: $includeRevoked, options: $options) {
            tokens { \(signInRecordFields) }
            meta { totalCount }
          }
        }
        """

    public static let revokeToken = """
        mutation RevokeToken($tokenId: String!) { RevokeToken(tokenId: $tokenId) }
        """

    public static let revokeTokens = """
        mutation RevokeTokens($tokenIds: [String!]!) { RevokeTokens(tokenIds: $tokenIds) { tokenIds } }
        """

    public static let listOAuthConsents = """
        query ListOAuthConsents {
          ListOAuthConsents { oauthConsents { id clientId clientName grantedScopes createdAt modifiedAt } meta { totalCount } }
        }
        """

    public static let revokeOAuthConsent = """
        mutation RevokeOAuthConsent($oauthConsentId: String!) { RevokeOAuthConsent(oauthConsentId: $oauthConsentId) }
        """

    public static let listWireGuardPeers = """
        query ListWireGuardPeers($options: ListOptionsInput) {
          ListWireGuardPeers(options: $options) {
            wireGuardPeers { id comment publicKey createdAt modifiedAt lastHandshakeAt revokedAt }
            meta { totalCount }
          }
        }
        """

    public static let modifyWireGuardPeer = """
        mutation ModifyWireGuardPeer($wireGuardPeerId: String!, $comment: String!) {
          ModifyWireGuardPeer(wireGuardPeerId: $wireGuardPeerId, comment: $comment) { wireGuardPeer { id comment modifiedAt } }
        }
        """

    public static let revokeWireGuardPeer = """
        mutation RevokeWireGuardPeer($wireGuardPeerId: String!) {
          RevokeWireGuardPeer(wireGuardPeerId: $wireGuardPeerId) { wireGuardPeer { id revokedAt } }
        }
        """

    public static let listSSHKeys = """
        query ListSSHKeys($options: ListOptionsInput) {
          ListSSHKeys(options: $options) {
            sshKeys { id comment publicKey createdAt modifiedAt lastUsedAt revokedAt }
            meta { totalCount }
          }
        }
        """

    public static let modifySSHKey = """
        mutation ModifySSHKey($sshKeyId: String!, $comment: String!) {
          ModifySSHKey(sshKeyId: $sshKeyId, comment: $comment) { sshKey { id comment modifiedAt } }
        }
        """

    public static let revokeSSHKey = """
        mutation RevokeSSHKey($sshKeyId: String!) {
          RevokeSSHKey(sshKeyId: $sshKeyId) { sshKey { id revokedAt } }
        }
        """

    public static let modifyUser = """
        mutation ModifyUser($userId: String!, $user: UserInput!) {
          ModifyUser(userId: $userId, user: $user) { user { id name modifiedAt } }
        }
        """

    public static let modifyMyProfessionalProfile = """
        mutation ModifyMyProfessionalProfile($jobRole: String!, $jobActivities: [String]!) {
          ModifyMyProfessionalProfile(jobRole: $jobRole, jobActivities: $jobActivities) { user { id jobRole jobActivities modifiedAt } }
        }
        """

    static var accountSecurityDocuments: [String] {
        [
            listSessions, revokeSession, listPasskeys, modifyPasskey, deletePasskey, listTokens, revokeToken, revokeTokens, listOAuthConsents,
            revokeOAuthConsent, listWireGuardPeers, modifyWireGuardPeer, revokeWireGuardPeer, listSSHKeys, modifySSHKey, revokeSSHKey, modifyUser,
            modifyMyProfessionalProfile,
        ]
    }
}

extension Connection {
    private static let firstPage: [String: JSONValue] = ["options": .object(["first": .number(200)])]

    /// The person's sessions that were not revoked. The app's own sign-in is not a session, so it is not listed.
    public func sessions() async throws -> SessionList {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable {
                let currentSessionId: String?
                let sessions: [SignInRecord]?
            }
            let ListSessions: List?
        }
        var variables = Self.firstPage
        variables["includeRevoked"] = .bool(false)
        let list = try await execute(Documents.listSessions, variables: variables, as: Answer.self).ListSessions
        return SessionList(currentSessionId: list?.currentSessionId ?? "", sessions: list?.sessions ?? [])
    }

    public func revokeSession(id: String) async throws {
        _ = try await execute(Documents.revokeSession, variables: ["sessionId": .string(id)], as: JSONValue.self)
    }

    public func passkeys() async throws -> [Passkey] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let passkeys: [Passkey]? }
            let ListPasskeys: List?
        }
        let rows = try await execute(Documents.listPasskeys, variables: Self.firstPage, as: Answer.self).ListPasskeys?.passkeys ?? []
        return rows.sorted { (PortalDate.parse($0.createdAt) ?? .distantPast) > (PortalDate.parse($1.createdAt) ?? .distantPast) }
    }

    public func renamePasskey(id: String, name: String) async throws {
        _ = try await execute(Documents.modifyPasskey, variables: ["passkeyId": .string(id), "name": .string(name)], as: JSONValue.self)
    }

    public func deletePasskey(id: String) async throws {
        _ = try await execute(Documents.deletePasskey, variables: ["passkeyId": .string(id)], as: JSONValue.self)
    }

    /// The person's API tokens that were not revoked or have not run out, most recently used first.
    public func apiTokens() async throws -> [SignInRecord] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let tokens: [SignInRecord]? }
            let ListTokens: List?
        }
        var variables = Self.firstPage
        variables["includeRevoked"] = .bool(false)
        return SignInRecords.active(try await execute(Documents.listTokens, variables: variables, as: Answer.self).ListTokens?.tokens ?? [])
    }

    public func revokeToken(id: String) async throws {
        _ = try await execute(Documents.revokeToken, variables: ["tokenId": .string(id)], as: JSONValue.self)
    }

    public func revokeTokens(ids: [String]) async throws {
        _ = try await execute(Documents.revokeTokens, variables: ["tokenIds": .array(ids.map { .string($0) })], as: JSONValue.self)
    }

    /// The apps the person let sign in as them, newest first.
    public func authorizedApps() async throws -> [AuthorizedApp] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let oauthConsents: [AuthorizedApp]? }
            let ListOAuthConsents: List?
        }
        let rows = try await execute(Documents.listOAuthConsents, as: Answer.self).ListOAuthConsents?.oauthConsents ?? []
        return rows.sorted { (PortalDate.parse($0.createdAt) ?? .distantPast) > (PortalDate.parse($1.createdAt) ?? .distantPast) }
    }

    public func revokeAuthorizedApp(id: String) async throws {
        _ = try await execute(Documents.revokeOAuthConsent, variables: ["oauthConsentId": .string(id)], as: JSONValue.self)
    }

    public func wireGuardPeers() async throws -> [WireGuardPeer] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let wireGuardPeers: [WireGuardPeer]? }
            let ListWireGuardPeers: List?
        }
        let rows = try await execute(Documents.listWireGuardPeers, variables: Self.firstPage, as: Answer.self).ListWireGuardPeers?.wireGuardPeers ?? []
        return rows.filter { !$0.isRevoked }.sorted { (PortalDate.parse($0.createdAt) ?? .distantPast) > (PortalDate.parse($1.createdAt) ?? .distantPast) }
    }

    public func renameWireGuardPeer(id: String, name: String) async throws {
        _ = try await execute(Documents.modifyWireGuardPeer, variables: ["wireGuardPeerId": .string(id), "comment": .string(name)], as: JSONValue.self)
    }

    public func revokeWireGuardPeer(id: String) async throws {
        _ = try await execute(Documents.revokeWireGuardPeer, variables: ["wireGuardPeerId": .string(id)], as: JSONValue.self)
    }

    public func sshKeys() async throws -> [SSHKey] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let sshKeys: [SSHKey]? }
            let ListSSHKeys: List?
        }
        let rows = try await execute(Documents.listSSHKeys, variables: Self.firstPage, as: Answer.self).ListSSHKeys?.sshKeys ?? []
        return rows.filter { !$0.isRevoked }.sorted { (PortalDate.parse($0.createdAt) ?? .distantPast) > (PortalDate.parse($1.createdAt) ?? .distantPast) }
    }

    public func renameSSHKey(id: String, name: String) async throws {
        _ = try await execute(Documents.modifySSHKey, variables: ["sshKeyId": .string(id), "comment": .string(name)], as: JSONValue.self)
    }

    public func revokeSSHKey(id: String) async throws {
        _ = try await execute(Documents.revokeSSHKey, variables: ["sshKeyId": .string(id)], as: JSONValue.self)
    }

    /// Changes the person's own name.
    public func renameUser(id: String, name: String) async throws {
        _ = try await execute(Documents.modifyUser, variables: ["userId": .string(id), "user": .object(["name": .string(name)])], as: JSONValue.self)
    }

    public func saveProfessionalProfile(jobRole: String, jobActivities: [String]) async throws {
        _ = try await execute(
            Documents.modifyMyProfessionalProfile,
            variables: ["jobRole": .string(jobRole), "jobActivities": .array(jobActivities.map { .string($0) })], as: JSONValue.self)
    }
}
