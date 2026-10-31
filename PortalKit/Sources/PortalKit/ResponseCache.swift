import Foundation

/// CacheKey names one query for one account: the same query with other
/// variables, or for another account, is another entry.
public struct CacheKey: Hashable, Sendable {
    public let accountKey: String
    public let name: String
    public let variables: String

    public init(accountKey: String, name: String, variables: String = "") {
        self.accountKey = accountKey
        self.name = name
        self.variables = variables
    }
}

/// ResponseCache keeps what screens loaded, so going back to one shows it at
/// once and reads it again in the background only when it is old
/// (stale-while-revalidate). It holds the last `capacity` entries it was
/// asked for, an entry is fresh for `freshFor` seconds, and a mutation can
/// change an entry in place from its own result instead of reading it again.
public final class ResponseCache: @unchecked Sendable {
    private struct Entry {
        var value: any Sendable
        var fetchedAt: Date
        var lastUsedAt: Date
    }

    public let capacity: Int
    public let freshFor: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var entries: [CacheKey: Entry] = [:]

    public init(capacity: Int = 50, freshFor: TimeInterval = 30, now: @escaping @Sendable () -> Date = { Date() }) {
        self.capacity = capacity
        self.freshFor = freshFor
        self.now = now
    }

    public var count: Int { locked { entries.count } }

    /// What is held for the key and whether it is still fresh. Nil when nothing is, or it holds another type.
    public func hit<Value: Sendable>(_ key: CacheKey, as type: Value.Type = Value.self) -> (value: Value, isFresh: Bool)? {
        locked {
            guard var entry = entries[key], let value = entry.value as? Value else { return nil }
            entry.lastUsedAt = now()
            entries[key] = entry
            return (value, now().timeIntervalSince(entry.fetchedAt) < freshFor)
        }
    }

    public func store<Value: Sendable>(_ value: Value, for key: CacheKey) {
        locked {
            let moment = now()
            entries[key] = Entry(value: value, fetchedAt: moment, lastUsedAt: moment)
            evictIfNeeded()
        }
    }

    /// Changes a held value from a mutation's result. The entry keeps its age: it is as fresh as it was.
    /// Returns false when nothing is held, so the caller knows to read it.
    @discardableResult
    public func update<Value: Sendable>(_ key: CacheKey, as type: Value.Type = Value.self, _ change: (inout Value) -> Void) -> Bool {
        locked {
            guard var entry = entries[key], var value = entry.value as? Value else { return false }
            change(&value)
            entry.value = value
            entry.lastUsedAt = now()
            entries[key] = entry
            return true
        }
    }

    public func remove(_ key: CacheKey) { locked { _ = entries.removeValue(forKey: key) } }

    /// Forgets everything of one account, such as at sign-out or when another account takes over.
    public func clear(accountKey: String? = nil) {
        locked {
            if let accountKey { entries = entries.filter { $0.key.accountKey != accountKey } } else { entries = [:] }
        }
    }

    /// Reads through the cache: what is held is handed to `show` at once, and `fetch` runs only when
    /// nothing is held, the entry is stale or `force` is set (pull to refresh). The fetched value is
    /// stored, shown and returned.
    @discardableResult
    public func load<Value: Sendable>(
        _ key: CacheKey, force: Bool = false, show: (Value) -> Void, fetch: () async throws -> Value,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Value {
        if let held: (value: Value, isFresh: Bool) = hit(key) {
            show(held.value)
            if held.isFresh && !force { return held.value }
        }
        let fetched = try await fetch()
        store(fetched, for: key)
        show(fetched)
        return fetched
    }

    private func evictIfNeeded() {
        while entries.count > capacity, let oldest = entries.min(by: { $0.value.lastUsedAt < $1.value.lastUsedAt })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    private func locked<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
