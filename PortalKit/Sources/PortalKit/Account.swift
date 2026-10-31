import Foundation

/// Account is one person's sign-in on one Portal instance.
public struct Account: Codable, Equatable, Sendable {
    public let server: ServerAddress
    public let clientId: String
    public let userId: String
    public var displayName: String
    public var email: String
    public var accessToken: String
    public var refreshToken: String
    public var accessTokenExpiresAt: Date
    /// Names this account's web data store (cookies and site data of the
    /// built-in browser), so accounts never share cookies. Removed with the account.
    public var webDataStoreId: UUID

    public init(
        server: ServerAddress, clientId: String, userId: String, displayName: String, email: String,
        accessToken: String, refreshToken: String, accessTokenExpiresAt: Date, webDataStoreId: UUID = UUID()
    ) {
        self.webDataStoreId = webDataStoreId
        self.server = server
        self.clientId = clientId
        self.userId = userId
        self.displayName = displayName
        self.email = email
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }

    enum CodingKeys: String, CodingKey {
        case server, clientId, userId, displayName, email, accessToken, refreshToken, accessTokenExpiresAt, webDataStoreId
    }

    /// Reads an account kept by an older build, which had no web data store id.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        server = try container.decode(ServerAddress.self, forKey: .server)
        clientId = try container.decode(String.self, forKey: .clientId)
        userId = try container.decode(String.self, forKey: .userId)
        displayName = try container.decode(String.self, forKey: .displayName)
        email = try container.decode(String.self, forKey: .email)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        accessTokenExpiresAt = try container.decode(Date.self, forKey: .accessTokenExpiresAt)
        webDataStoreId = try container.decodeIfPresent(UUID.self, forKey: .webDataStoreId) ?? UUID()
    }

    /// Which sign-in this is: one person on one server. Signing in again as
    /// the same person replaces the sign-in rather than adding another.
    public var accountKey: String { "\(server.description)|\(userId)" }
}

/// AccountRing is every sign-in the app keeps, and the one in use.
public struct AccountRing: Codable, Equatable, Sendable {
    public private(set) var accounts: [Account]
    public private(set) var activeAccountKey: String?

    public init(accounts: [Account] = [], activeAccountKey: String? = nil) {
        self.accounts = accounts
        self.activeAccountKey = activeAccountKey
    }

    /// The sign-in in use; the first one when none is chosen.
    public var active: Account? {
        accounts.first { $0.accountKey == activeAccountKey } ?? accounts.first
    }

    /// Keeps a sign-in, replacing the one for the same person on the same
    /// server. The first one kept is the one in use.
    public mutating func put(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.accountKey == account.accountKey }) {
            // Signing in again keeps the web data store, so no store is left behind.
            var replacement = account
            replacement.webDataStoreId = accounts[index].webDataStoreId
            accounts[index] = replacement
        } else {
            accounts.append(account)
        }
        if active?.accountKey != activeAccountKey {
            activeAccountKey = active?.accountKey
        }
    }

    /// Puts a kept sign-in to use; nothing happens for one that is not kept.
    public mutating func activate(_ accountKey: String) {
        if accounts.contains(where: { $0.accountKey == accountKey }) {
            activeAccountKey = accountKey
        }
    }

    /// Forgets a sign-in. When it was the one in use, the next one is.
    public mutating func remove(_ accountKey: String) {
        accounts.removeAll { $0.accountKey == accountKey }
        if activeAccountKey == accountKey || active?.accountKey != activeAccountKey {
            activeAccountKey = accounts.first?.accountKey
        }
    }
}

/// AccountStore keeps the ring between launches: the keychain in the app,
/// memory in a test.
public protocol AccountStore: Sendable {
    func loadRing() throws -> AccountRing
    func saveRing(_ ring: AccountRing) throws
}

extension AccountStore {
    /// Keeps a renewed or new sign-in without changing which one is in use.
    public func save(_ account: Account) throws {
        var ring = try loadRing()
        ring.put(account)
        try saveRing(ring)
    }

    /// Keeps a sign-in and puts it to use.
    public func add(_ account: Account) throws {
        var ring = try loadRing()
        ring.put(account)
        ring.activate(account.accountKey)
        try saveRing(ring)
    }

    public func activate(_ accountKey: String) throws {
        var ring = try loadRing()
        ring.activate(accountKey)
        try saveRing(ring)
    }

    public func remove(_ accountKey: String) throws {
        var ring = try loadRing()
        ring.remove(accountKey)
        try saveRing(ring)
    }

    public func load(accountKey: String) throws -> Account? {
        try loadRing().accounts.first { $0.accountKey == accountKey }
    }
}

/// MemoryAccountStore keeps the ring in memory, for tests and the demo.
public final class MemoryAccountStore: AccountStore, @unchecked Sendable {
    private let lock = NSLock()
    private var ring: AccountRing

    public init(ring: AccountRing = AccountRing()) {
        self.ring = ring
    }

    public func loadRing() throws -> AccountRing {
        lock.lock()
        defer { lock.unlock() }
        return ring
    }

    public func saveRing(_ newRing: AccountRing) throws {
        lock.lock()
        defer { lock.unlock() }
        ring = newRing
    }
}
