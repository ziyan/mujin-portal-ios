import Foundation
import Testing

@testable import PortalKit

@Suite struct SurveillanceTests {
    static func camera(_ id: String, _ name: String, site: String?, organization: String = "org1", online: Bool = true) -> Camera {
        Camera(
            id: id, organizationId: organization, siteId: site, controllerId: "controller-\(id)", originCameraId: "origin-\(id)", name: name,
            status: online ? "online" : "offline", isControllerConnected: true)
    }

    static let siteNames = ["siteA": "Packing hall", "siteB": "Dock", "siteC": "Annex"]
    static let organizationNames = ["org1": "Example Foods", "org2": "Sample Freight"]

    static let cameras = [
        camera("c1", "Door 1", site: "siteA"), camera("c2", "Aisle 4", site: "siteA", online: false), camera("c3", "Gate", site: "siteB"),
        camera("c4", "Yard", site: "siteC", organization: "org2"), camera("c5", "Loose", site: nil),
    ]

    @Test func camerasAreGroupedBySiteUnderTheirOrganizationInNameOrder() {
        let groups = Surveillance.group(cameras: Self.cameras, siteNames: Self.siteNames, organizationNames: Self.organizationNames)
        #expect(groups.map(\.siteId) == ["siteB", "siteA", "", "siteC"])
        #expect(groups[1].cameras.map(\.id) == ["c1", "c2"])
        #expect(groups[1].onlineCount == 1)
        #expect(groups[0].organizationName == "Example Foods")
    }

    @Test func aSelectionKeepsOnlyThoseSites() {
        let groups = Surveillance.group(
            cameras: Self.cameras, siteNames: Self.siteNames, organizationNames: Self.organizationNames, selectedSiteIds: ["siteC", "siteB"])
        #expect(groups.map(\.siteId) == ["siteB", "siteC"])
    }

    @Test func aSearchMatchesACameraASiteOrAnOrganization() {
        func found(_ query: String) -> [String] {
            Surveillance.group(cameras: Self.cameras, siteNames: Self.siteNames, organizationNames: Self.organizationNames, query: query).flatMap(\.cameras).map(\.id)
        }
        #expect(found("aisle") == ["c2"])
        // A site that matches shows all of its cameras.
        #expect(found("packing") == ["c1", "c2"])
        #expect(found("freight") == ["c4"])
        #expect(found("nothing like this").isEmpty)
    }

    @Test func theFilterListsTheSitesThatHaveCameras() {
        let sites = Surveillance.sites(of: Self.cameras, siteNames: Self.siteNames, organizationNames: Self.organizationNames)
        #expect(sites.map(\.siteId) == ["siteB", "siteA", "", "siteC"])
        #expect(sites[1].cameraCount == 2)
    }

    @Test func allCamerasAsksForNoSiteAndSkipsRowsItCannotRead() async throws {
        let transport = ScriptedTransport { _ in
            (
                200,
                ScriptedTransport.json([
                    "data": [
                        "ListCameras": [
                            "cameras": [
                                ["id": "c1", "controllerId": "k1", "originCameraId": "o1", "name": "Door", "status": "online", "isControllerConnected": true, "siteId": "siteA"],
                                ["id": "broken"],
                            ]
                        ]
                    ]
                ])
            )
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        let cameras = try await connection.allCameras()
        #expect(cameras.map(\.id) == ["c1"])
        let body = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody ?? Data()) as? [String: Any]
        #expect((body?["variables"] as? [String: Any])?.isEmpty == true)
    }
}
