import Foundation
import Testing

@testable import PortalKit

@Suite struct LinkClassifierTests {
    let server = try! ServerAddress("https://portal.example.test")

    func kind(_ text: String, server: ServerAddress? = nil) -> LinkKind {
        LinkClassifier.classify(URL(string: text)!, server: server ?? self.server)
    }

    @Test func theServerItselfIsPortal() {
        #expect(kind("https://portal.example.test/ticket/12") == .portal)
        #expect(kind("https://PORTAL.example.test") == .portal)
        #expect(kind("http://portal.example.test/x") == .portal)
    }

    @Test func theThreeProxyHostsAreControllers() {
        #expect(kind("https://controller01-live.portal.example.test/") == .controller)
        #expect(kind("https://controller01-cloud.portal.example.test/path?q=1") == .controller)
        #expect(kind("https://virtual01-virtual.portal.example.test/") == .controller)
    }

    @Test func otherSubdomainsAndLookalikeHostsAreNotControllers() {
        #expect(kind("https://controller01.portal.example.test/") == .external)
        #expect(kind("https://a.b.portal.example.test/path") == .external)
        #expect(kind("https://controller01-other.portal.example.test/") == .external)
        #expect(kind("https://-live.portal.example.test/") == .external)
        #expect(kind("https://a-b-live.portal.example.test/") == .external)
        #expect(kind("https://controller01-live.evil.test/") == .external)
        #expect(kind("https://controller01-live.portal.example.test.evil.test/") == .external)
        #expect(kind("https://x.controller01-live.portal.example.test/") == .external)
    }

    @Test func lookalikesAreExternal() {
        #expect(kind("https://example.test/") == .external)
        #expect(kind("https://evilportal.example.test/") == .external)
        #expect(kind("https://portal.example.test.evil.test/") == .external)
        #expect(kind("https://other.example.org") == .external)
    }

    @Test func theClassificationFollowsTheAccountsServer() {
        let other = try! ServerAddress("https://portal.other.test")
        #expect(kind("https://controller01-live.portal.other.test/", server: other) == .controller)
        #expect(kind("https://controller01-live.portal.other.test/") == .external)
        #expect(kind("https://controller01-live.portal.example.test/", server: other) == .external)
    }

    @Test func aServerWithAPortHasTheSameBaseDomain() {
        let local = try! ServerAddress("http://localhost:8080")
        #expect(kind("http://localhost:8080/a", server: local) == .portal)
        #expect(kind("http://controller01-live.localhost:8080/", server: local) == .controller)
    }

    @Test func nonWebAddressesAreLeftToTheSystem() {
        #expect(kind("mailto:alex@example.test") == .other)
        #expect(kind("tel:+15550100") == .other)
        #expect(kind("com.ziyan.mujinportal:/oauth") == .other)
    }

    @Test func onlyPortalAndControllersOpenInTheApp() {
        #expect(LinkClassifier.opensInApp(.portal))
        #expect(LinkClassifier.opensInApp(.controller))
        #expect(!LinkClassifier.opensInApp(.external))
        #expect(!LinkClassifier.opensInApp(.other))
    }
}

@Suite struct WebSessionHandoffTests {
    func connection(offered: Bool, handoff: String?) -> Connection {
        let transport = ScriptedTransport { request in
            let body = request.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            let query = body?["query"]?.stringValue ?? ""
            if query.contains("__type") {
                let names: [[String: String]] = offered ? [["name": "CreateWebSessionHandoff"]] : [["name": "SendMessage"]]
                return (200, ScriptedTransport.json(["data": ["__type": ["fields": names]]]))
            }
            if let handoff { return (200, ScriptedTransport.json(["data": ["CreateWebSessionHandoff": ["url": handoff, "expiresAt": "2030-01-01T00:00:00Z"]]])) }
            return (200, ScriptedTransport.json(["errors": [["message": "permission denied"]]]))
        }
        return Connection(account: makeAccount(), transport: transport)
    }

    @Test func aServerThatOffersItReturnsTheOneTimeAddress() async {
        let url = await connection(offered: true, handoff: "https://portal.example.test/handoff/abc").webSessionHandoff(to: URL(string: "https://controller01-live.portal.example.test/")!)
        #expect(url?.absoluteString == "https://portal.example.test/handoff/abc")
    }

    @Test func aServerWithoutItGivesNothingSoThePageOpensAsItIs() async {
        #expect(await connection(offered: false, handoff: nil).webSessionHandoff(to: URL(string: "https://controller01-live.portal.example.test/")!) == nil)
    }

    @Test func aRefusalOrAnOddAddressGivesNothing() async {
        let target = URL(string: "https://controller01.portal.example.test/")!
        #expect(await connection(offered: true, handoff: nil).webSessionHandoff(to: target) == nil)
        #expect(await connection(offered: true, handoff: "javascript:alert(1)").webSessionHandoff(to: target) == nil)
    }

    @Test func anOlderKeptAccountWithoutAStoreIdStillReads() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(makeAccount())) as! [String: Any]
        object.removeValue(forKey: "webDataStoreId")
        let decoded = try JSONDecoder().decode(Account.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.userId == "user01")
    }

    @Test func theStoreIdIsKeptWithTheAccount() throws {
        let account = makeAccount()
        let decoded = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(account))
        #expect(decoded.webDataStoreId == account.webDataStoreId)
    }
}

@Suite struct WebDataStoreTests {
    @Test func signingInAgainKeepsTheWebDataStore() {
        var ring = AccountRing()
        let first = makeAccount(accessToken: "old")
        ring.put(first)
        ring.put(makeAccount(accessToken: "new"))
        #expect(ring.accounts.count == 1)
        #expect(ring.accounts[0].accessToken == "new")
        #expect(ring.accounts[0].webDataStoreId == first.webDataStoreId)
    }

    @Test func eachAccountHasItsOwnStore() {
        var ring = AccountRing()
        ring.put(makeAccount(userId: "user01"))
        ring.put(makeAccount(userId: "user02"))
        #expect(Set(ring.accounts.map(\.webDataStoreId)).count == 2)
    }
}

@Suite struct ControllerLinkTests {
    let server = try! ServerAddress("https://portal.example.test")

    func controller(online: Bool = true, capabilities: [String] = ["controller:connect", "controller:write"]) -> ControllerSummary {
        ControllerSummary(id: "controller01", connection: online ? .init(id: "connection01") : nil, viewerCapabilities: capabilities)
    }

    @Test func liveAndCloudAndVirtualAddressesUseTheProxyHosts() {
        #expect(ControllerLinks.liveURL(controllerId: "controller01", server: server)?.absoluteString == "https://controller01-live.portal.example.test/")
        #expect(ControllerLinks.cloudURL(controllerId: "controller01", server: server)?.absoluteString == "https://controller01-cloud.portal.example.test/")
        #expect(ControllerLinks.virtualURL(virtualControllerId: "virtual01", server: server)?.absoluteString == "https://virtual01-virtual.portal.example.test/")
    }

    @Test func theSchemeAndPortOfTheServerAreKept() {
        let local = try! ServerAddress("http://localhost:8080")
        #expect(ControllerLinks.liveURL(controllerId: "controller01", server: local)?.absoluteString == "http://controller01-live.localhost:8080/")
    }

    @Test func anIdentifierThatCouldChangeTheHostIsRefused() {
        #expect(ControllerLinks.liveURL(controllerId: "a.b", server: server) == nil)
        #expect(ControllerLinks.liveURL(controllerId: "a-b", server: server) == nil)
        #expect(ControllerLinks.liveURL(controllerId: "", server: server) == nil)
    }

    @Test func theScreenPagesAreOnPortalsOwnHost() {
        #expect(ControllerLinks.screenURL(controllerId: "controller01", server: server)?.absoluteString == "https://portal.example.test/screen/controller/controller01")
        #expect(ControllerLinks.virtualScreenURL(virtualControllerId: "virtual01", server: server)?.absoluteString == "https://portal.example.test/screen/virtualcontroller/virtual01")
    }

    @Test func liveOpensOnlyForAnOnlineControllerTheViewerMayConnectTo() {
        #expect(controller().liveEntry(server: server) == .open(URL(string: "https://controller01-live.portal.example.test/")!))
        #expect(controller(online: false).liveEntry(server: server) == .blocked(.offline))
        #expect(controller(capabilities: []).liveEntry(server: server) == .blocked(.noConnectPermission))
    }

    @Test func cloudNeedsThePermissionAndAtLeastOneSyncedUser() {
        #expect(controller(capabilities: []).cloudEntry(server: server, syncedUsers: SyncedUserCount(count: 3)) == .blocked(.noConnectPermission))
        #expect(controller().cloudEntry(server: server, syncedUsers: nil) == .hidden)
        #expect(controller().cloudEntry(server: server, syncedUsers: SyncedUserCount(count: 0, isAvailable: false)) == .blocked(.syncedUsersUnavailable))
        #expect(controller().cloudEntry(server: server, syncedUsers: SyncedUserCount(count: 0)) == .blocked(.noSyncedUsers))
        #expect(controller(online: false).cloudEntry(server: server, syncedUsers: SyncedUserCount(count: 2)) == .open(URL(string: "https://controller01-cloud.portal.example.test/")!))
    }

    @Test func theScreenNeedsAnOnlineControllerAndWriteAccess() {
        #expect(controller().screenEntry(server: server) == .open(URL(string: "https://portal.example.test/screen/controller/controller01")!))
        #expect(controller(online: false).screenEntry(server: server) == .blocked(.offline))
        #expect(controller(capabilities: ["controller:connect"]).screenEntry(server: server) == .blocked(.noWritePermission))
    }
}
