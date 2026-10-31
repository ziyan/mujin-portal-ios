import Foundation

/// SiteSelection decides which site a site screen shows. The choice belongs
/// to the place, not to the view, so a view appearing again never changes it.
public enum SiteSelection {
    /// The site to show: the one already selected while it is in the list,
    /// else the one remembered from an earlier launch, else the first.
    public static func resolve(current: String?, remembered: String?, availableIds: [String]) -> String? {
        if let current, availableIds.contains(current) { return current }
        if let remembered, availableIds.contains(remembered) { return remembered }
        return availableIds.first
    }
}

/// SiteSelectionStore remembers the selected site of each scope (the
/// person's own sites, or one organization's) per account across launches.
public struct SiteSelectionStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(accountKey: String, organizationKey: String) -> String {
        "selectedSite|\(accountKey)|\(organizationKey)"
    }

    public func load(accountKey: String, organizationKey: String) -> String? {
        defaults.string(forKey: key(accountKey: accountKey, organizationKey: organizationKey))
    }

    public func save(_ siteId: String?, accountKey: String, organizationKey: String) {
        let storageKey = key(accountKey: accountKey, organizationKey: organizationKey)
        if let siteId { defaults.set(siteId, forKey: storageKey) } else { defaults.removeObject(forKey: storageKey) }
    }
}
