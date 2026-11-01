import Foundation
import Testing

@testable import PortalKit

@Suite struct SiteGroupTests {
    private let names = ["org1": "Sample Foods", "org2": "Example Logistics", "org3": "Support"]
    private let sites = [
        SiteSummary(id: "s1", name: "Cold store", organizationId: "org1"),
        SiteSummary(id: "s2", name: "Bakery line", organizationId: "org1"),
        SiteSummary(id: "s3", name: "Riverside depot", organizationId: "org2"),
        SiteSummary(id: "s4", name: "Retired yard", organizationId: "org2", isArchived: true),
        SiteSummary(id: "s5", name: "Lab cell", organizationId: "org3"),
        SiteSummary(id: "s6", name: "Orphan", organizationId: "org9"),
    ]

    @Test func groupsAreSortedByOrganizationNameAndSitesByName() {
        let groups = SiteGroups.group(sites, organizationNames: names)
        #expect(groups.map(\.organizationName) == ["Example Logistics", "Sample Foods", "Support", nil])
        #expect(groups[1].sites.map(\.id) == ["s2", "s1"])
        #expect(!groups.flatMap(\.sites).contains { $0.id == "s4" })
    }

    @Test func aSearchMatchesASiteOrAWholeOrganization() {
        let bySite = SiteGroups.group(sites, organizationNames: names, query: "cold")
        #expect(bySite.map(\.organizationId) == ["org1"])
        #expect(bySite[0].sites.map(\.id) == ["s1"])
        let byOrganization = SiteGroups.group(sites, organizationNames: names, query: "sample")
        #expect(byOrganization[0].sites.map(\.id) == ["s2", "s1"])
        #expect(SiteGroups.group(sites, organizationNames: names, query: "nothing like it").isEmpty)
    }

    @Test func everyPageOfSitesIsAskedForUntilTheTotalIsReached() async throws {
        let account = Account(
            server: try ServerAddress("https://portal.example.test"), clientId: "client01", userId: "user01", displayName: "Alex", email: "alex@example.test",
            accessToken: "token", refreshToken: "refresh", accessTokenExpiresAt: Date().addingTimeInterval(3600))
        let calls = Guarded<[Int]>([])
        let transport = ScriptedTransport { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
            let after = Int(body["variables"]?["options"]?["after"]?.numberValue ?? 0)
            calls.withValue { $0.append(after) }
            let total = 5
            let rows = (after..<min(after + 2, total)).map { ["id": "s\($0)", "name": "Site \($0)", "organizationId": "org1", "isArchived": false] as [String: Any] }
            return (200, ScriptedTransport.json(["data": ["ListSites": ["sites": rows, "meta": ["totalCount": total]]]]))
        }
        let connection = Connection(account: account, transport: transport)
        let all = try await connection.allSites(pageSize: 2)
        #expect(all.count == 5)
        #expect(calls.withValue { $0 } == [0, 2, 4])
    }
}
