import Foundation

/// SiteGroup is the sites of one organization, as the staff Sites list shows them.
public struct SiteGroup: Equatable, Identifiable, Sendable {
    public let organizationId: String
    /// Nil when no name is known for the organization.
    public let organizationName: String?
    public let sites: [SiteSummary]
    public var id: String { organizationId }
}

public enum SiteGroups {
    /// One group per organization, groups sorted by organization name and sites by name; archived sites are left out.
    /// A search matches a site's name or its organization's name, and an organization that matches shows all its sites.
    public static func group(_ sites: [SiteSummary], organizationNames: [String: String], query: String = "") -> [SiteGroup] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let grouped = Dictionary(grouping: sites.filter { $0.isArchived != true }) { $0.organizationId ?? "" }
        var groups: [SiteGroup] = []
        for (organizationId, members) in grouped {
            let name = organizationNames[organizationId].flatMap { $0.isEmpty ? nil : $0 }
            var shown = members
            if !text.isEmpty, !(name ?? "").localizedCaseInsensitiveContains(text) {
                shown = members.filter { ($0.name ?? "").localizedCaseInsensitiveContains(text) }
            }
            guard !shown.isEmpty else { continue }
            groups.append(
                SiteGroup(
                    organizationId: organizationId, organizationName: name,
                    sites: shown.sorted { ($0.name ?? $0.id).localizedCaseInsensitiveCompare($1.name ?? $1.id) == .orderedAscending }))
        }
        return groups.sorted {
            let first = $0.organizationName ?? ""
            let second = $1.organizationName ?? ""
            // Organizations with no known name go last.
            if first.isEmpty != second.isEmpty { return second.isEmpty }
            let order = first.localizedCaseInsensitiveCompare(second)
            return order == .orderedSame ? $0.organizationId < $1.organizationId : order == .orderedAscending
        }
    }
}
