import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// AvatarSubject names one picture on the server: a person's avatar or an
/// organization's logo, at the version it was last uploaded.
public struct AvatarSubject: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case user
        case organization
        /// Any other picture of the server, such as a web app's icon: `id` is its path.
        case picture
    }

    public let kind: Kind
    public let id: String
    /// The `modifiedAt` of the user or organization, so a new upload is fetched again. Nil when the list the person came from does not carry it.
    public let modifiedAt: String?

    public init(kind: Kind, id: String, modifiedAt: String? = nil) {
        self.kind = kind
        self.id = id
        self.modifiedAt = modifiedAt
    }

    public var path: String {
        switch kind {
        case .user: "/api/v1/user/\(id)/avatar"
        case .organization: "/api/v1/organization/\(id)/logo"
        case .picture: id
        }
    }

    /// The cache key: the same picture at the same version is one entry.
    public var cacheKey: String { "\(kind.rawValue)-\(id)@\(modifiedAt ?? "-")" }
}

/// AvatarStore keeps the pictures one account has fetched, in memory and on
/// disk, and fetches the ones it lacks through the account's connection so
/// the token renews. It never fetches the same picture twice at once.
public actor AvatarStore {
    /// How long a picture whose version is unknown is trusted. A versioned one never goes stale: a new upload has a new key.
    static let unversionedLifetime: TimeInterval = 3600
    /// How long a refused fetch (no picture there) is remembered.
    static let missingLifetime: TimeInterval = 600

    private let connection: Connection
    private let directory: URL?
    private var memory: [String: Data] = [:]
    private var missing: [String: Date] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]

    /// `directory` is where this account's pictures are kept between launches; nil keeps them in memory only.
    public init(connection: Connection, directory: URL?) {
        self.connection = connection
        self.directory = directory
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }

    /// The pictures already in memory, so a view can draw one with no wait.
    public func cachedData(for subject: AvatarSubject) -> Data? {
        memory[subject.cacheKey]
    }

    /// The picture's bytes, or nil when there is none or it cannot be fetched now.
    public func data(for subject: AvatarSubject, now: Date = Date()) async -> Data? {
        let key = subject.cacheKey
        if let found = memory[key] { return found }
        if let since = missing[key], now.timeIntervalSince(since) < Self.missingLifetime { return nil }
        if let stored = readFromDisk(subject, now: now) {
            memory[key] = stored
            return stored
        }
        if let running = inFlight[key] { return await running.value }
        let connection = self.connection
        let task = Task { () -> Data? in
            try? await connection.fetchPicture(at: subject.path)
        }
        inFlight[key] = task
        let fetched = await task.value
        inFlight[key] = nil
        if let fetched {
            memory[key] = fetched
            writeToDisk(subject, fetched)
        } else {
            missing[key] = now
        }
        return fetched
    }

    /// Forgets everything, at sign-out.
    public func clear() {
        memory = [:]
        missing = [:]
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func file(for subject: AvatarSubject) -> URL? {
        guard let directory else { return nil }
        let safe = subject.cacheKey.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "@" ? String($0) : "_" }.joined()
        return directory.appendingPathComponent(safe)
    }

    private func readFromDisk(_ subject: AvatarSubject, now: Date) -> Data? {
        guard let url = file(for: subject), let data = try? Data(contentsOf: url) else { return nil }
        if subject.modifiedAt == nil {
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            guard let modified, now.timeIntervalSince(modified) < Self.unversionedLifetime else { return nil }
        }
        return data
    }

    private func writeToDisk(_ subject: AvatarSubject, _ data: Data) {
        guard let url = file(for: subject) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension Connection {
    /// Fetches an image from a path of the server with the account's token, or nil when there is none (a 404).
    func fetchPicture(at path: String) async throws -> Data? {
        var request = URLRequest(url: account.server.endpoint(path))
        request.timeoutInterval = 30
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await send(authorizing: request)
        guard response.statusCode == 200, !data.isEmpty else { return nil }
        return data
    }
}
