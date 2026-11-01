import Foundation

/// WebDataRemoval remembers which web data stores belong to accounts that were removed.
/// A store is deleted at the next launch, before any web view of the process exists,
/// because WebKit crashes when a store is removed while a web view still uses it.
public struct WebDataRemoval: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "webDataStoresToRemove"

    public init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    /// Notes a store as ready to delete at the next launch.
    public func record(_ identifier: UUID) {
        var identifiers = defaults.stringArray(forKey: Self.key) ?? []
        if !identifiers.contains(identifier.uuidString) { identifiers.append(identifier.uuidString) }
        defaults.set(identifiers, forKey: Self.key)
    }

    /// The stores to delete now, forgotten once handed over.
    public func takeAll() -> [UUID] {
        let identifiers = defaults.stringArray(forKey: Self.key) ?? []
        defaults.removeObject(forKey: Self.key)
        return identifiers.compactMap(UUID.init(uuidString:))
    }
}
