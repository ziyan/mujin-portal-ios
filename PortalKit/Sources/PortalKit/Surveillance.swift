import Foundation

/// SurveillanceGroup is the cameras of one site, as the camera wall shows them under the site's name.
public struct SurveillanceGroup: Equatable, Identifiable, Sendable {
    public let siteId: String
    /// Nil when no name is known for the site.
    public let siteName: String?
    public let organizationId: String?
    /// Nil when no name is known for the organization.
    public let organizationName: String?
    public let cameras: [Camera]
    public var id: String { siteId }

    public var onlineCount: Int { cameras.filter(\.isStreamable).count }
}

/// SurveillanceSite is a site that has cameras, for the filter that narrows the wall.
public struct SurveillanceSite: Equatable, Identifiable, Sendable {
    public let siteId: String
    public let siteName: String?
    public let organizationId: String?
    public let organizationName: String?
    public let cameraCount: Int
    public var id: String { siteId }
}

public enum Surveillance {
    /// One group per site, the organizations in name order and the sites of each by name; a camera with no site goes last in its organization. A site that
    /// is not selected is left out when any are, and a search matches a camera's, a site's or an organization's name.
    public static func group(
        cameras: [Camera], siteNames: [String: String], organizationNames: [String: String], selectedSiteIds: Set<String> = [], query: String = ""
    ) -> [SurveillanceGroup] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let grouped = Dictionary(grouping: cameras.filter { selectedSiteIds.isEmpty || selectedSiteIds.contains($0.siteId ?? "") }) { $0.siteId ?? "" }
        var groups: [SurveillanceGroup] = []
        for (siteId, members) in grouped {
            let siteName = siteNames[siteId].flatMap { $0.isEmpty ? nil : $0 }
            let organizationId = members.compactMap(\.organizationId).first { !$0.isEmpty }
            let organizationName = organizationId.flatMap { organizationNames[$0] }.flatMap { $0.isEmpty ? nil : $0 }
            var shown = members
            if !text.isEmpty, !(siteName ?? "").localizedCaseInsensitiveContains(text), !(organizationName ?? "").localizedCaseInsensitiveContains(text) {
                shown = members.filter { $0.displayName.localizedCaseInsensitiveContains(text) }
            }
            guard !shown.isEmpty else { continue }
            groups.append(
                SurveillanceGroup(
                    siteId: siteId, siteName: siteName, organizationId: organizationId, organizationName: organizationName,
                    cameras: CameraOrdering.ordered(shown)))
        }
        return groups.sorted { left, right in
            let leftOrganization = left.organizationName ?? ""
            let rightOrganization = right.organizationName ?? ""
            if leftOrganization != rightOrganization {
                // Organizations with no known name go last.
                if leftOrganization.isEmpty != rightOrganization.isEmpty { return rightOrganization.isEmpty }
                return leftOrganization.localizedCaseInsensitiveCompare(rightOrganization) == .orderedAscending
            }
            let leftSite = left.siteName ?? ""
            let rightSite = right.siteName ?? ""
            if leftSite.isEmpty != rightSite.isEmpty { return rightSite.isEmpty }
            let order = leftSite.localizedCaseInsensitiveCompare(rightSite)
            return order == .orderedSame ? left.siteId < right.siteId : order == .orderedAscending
        }
    }

    /// The sites that have cameras, in the order the wall lists them.
    public static func sites(of cameras: [Camera], siteNames: [String: String], organizationNames: [String: String]) -> [SurveillanceSite] {
        group(cameras: cameras, siteNames: siteNames, organizationNames: organizationNames).map {
            SurveillanceSite(
                siteId: $0.siteId, siteName: $0.siteName, organizationId: $0.organizationId, organizationName: $0.organizationName,
                cameraCount: $0.cameras.count)
        }
    }

    /// "3 of 5 online".
    public static func onlineCount(_ cameras: [Camera]) -> Int { cameras.filter(\.isStreamable).count }
}

extension Connection {
    /// Every camera the person can see, across sites. The server narrows the read to the sites they may read, so there is nothing to ask.
    public func allCameras() async throws -> [Camera] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let cameras: [Lossy<Camera>?]? }
            let ListCameras: List?
        }
        let rows = try await execute(Documents.listCameras, as: Answer.self).ListCameras?.cameras ?? []
        return CameraOrdering.ordered(rows.compactMap { $0?.value })
    }
}
