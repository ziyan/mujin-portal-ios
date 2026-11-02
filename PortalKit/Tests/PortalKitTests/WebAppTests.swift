import Foundation
import Testing

@testable import PortalKit

@Suite struct WebAppTests {
    let server = try! ServerAddress("https://portal.example.test")

    @Test func theListIsReadWithTheControllerIdAndKeepsOnlyAppsThatCanBeOpened() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in
            #expect(operation == "ListControllerWebApps")
            return [
                "ListControllerWebApps": [
                    "isAvailable": true, "source": "live",
                    "webApps": [
                        ["webAppId": "sample-app", "name": "Sample", "versionString": "1.0.0", "openPath": "/app/sample", "iconUrl": "/api/v1/controller/controller01/webapp/sample-app/icon"],
                        ["webAppId": "no-page", "name": "No page", "openPath": ""],
                        ["name": "No id"],
                        ["webAppId": "plain-app", "name": "  ", "openPath": "/app/plain", "iconUrl": NSNull()],
                    ],
                ]
            ]
        }
        let list = try await connection.controllerWebApps(controllerId: "controller01")
        #expect(list.isAvailable)
        #expect(list.source == "live")
        #expect(list.webApps.map(\.webAppId) == ["sample-app", "plain-app"])
        #expect(list.webApps[1].displayName == "plain-app")
        let variables = sentVariables(transport.requests.last!)
        #expect(variables["controllerId"] as? String == "controller01")
        #expect(variables["virtualControllerId"] == nil)
    }

    @Test func aVirtualControllerIsAskedByItsOwnId() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            ["ListControllerWebApps": ["isAvailable": true, "source": "virtual", "webApps": []]]
        }
        let list = try await connection.controllerWebApps(virtualControllerId: "virtual01")
        #expect(list == ControllerWebAppList(isAvailable: true, source: "virtual", webApps: []))
        let variables = sentVariables(transport.requests.last!)
        #expect(variables["virtualControllerId"] as? String == "virtual01")
        #expect(variables["controllerId"] == nil)
    }

    @Test func anUnavailableAnswerHasNoApps() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            ["ListControllerWebApps": ["isAvailable": false, "source": NSNull(), "webApps": []]]
        }
        let list = try await connection.controllerWebApps(controllerId: "controller01")
        #expect(!list.isAvailable)
        #expect(list.webApps.isEmpty)
    }

    @Test func anAppOpensOnTheHostOfTheListsSource() {
        #expect(
            ControllerLinks.appURL(controllerId: "controller01", source: "live", openPath: "/app/sample", server: server)?.absoluteString
                == "https://controller01-live.portal.example.test/app/sample")
        #expect(
            ControllerLinks.appURL(controllerId: "controller01", source: "cloud", openPath: "/app/sample", server: server)?.absoluteString
                == "https://controller01-cloud.portal.example.test/app/sample")
        #expect(
            ControllerLinks.virtualAppURL(virtualControllerId: "virtual01", openPath: "/app/plain%20route", server: server)?.absoluteString
                == "https://virtual01-virtual.portal.example.test/app/plain%20route")
    }

    @Test func aPathThatIsNotAnAppPageIsRefused() {
        for path in ["/", "/api/v2/graphql", "/app/../admin", "/app//x", "/app/x?next=1", "/app/x#top", "/app/x\\y", "app/x", "/app/x\n"] {
            #expect(ControllerLinks.appURL(controllerId: "controller01", source: "live", openPath: path, server: server) == nil, "\(path)")
        }
    }

    @Test func anIconIsFetchedOnlyFromAPathOfThePortalApi() {
        let good = ControllerWebApp(webAppId: "a", versionString: "2", iconUrl: "/api/v1/controller/controller01/webapp/a/icon")
        #expect(good.iconSubject?.path == "/api/v1/controller/controller01/webapp/a/icon")
        #expect(good.iconSubject?.cacheKey.hasSuffix("@2") == true)
        for bad in [nil, "", "https://elsewhere.example.test/icon.png", "/other/icon", "/api/v1/../icon", "/api/v1/x?y=1"] {
            #expect(ControllerWebApp(webAppId: "a", iconUrl: bad).iconSubject == nil, "\(bad ?? "nil")")
        }
    }

    @Test func theFeatureIsOfferedOnlyWhenTheServerHasTheQuery() {
        #expect(!ServerCapabilities().offersControllerWebApps)
        #expect(ServerCapabilities(queryNames: ["ListControllerWebApps"]).offersControllerWebApps)
    }
}
